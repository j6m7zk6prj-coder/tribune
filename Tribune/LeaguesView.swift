import SwiftUI

struct LeaguesView: View {
    @Environment(AppStore.self) private var store
    @State private var path = NavigationPath()
    @State private var query = ""

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(CompGroup.allCases) { g in
                        let comps = Competition.all.filter { $0.group == g && matches($0) }
                        if !comps.isEmpty {
                            SectionTitle(text: g.rawValue).id(g.id)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ForEach(comps) { c in
                                    NavigationLink(value: Route.league(c)) { LeagueTile(competition: c) }
                                        .buttonStyle(Pressable())
                                        .floatIn()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .task {
                if Launch.args.contains("-scroll") {
                    try? await Task.sleep(for: .seconds(1))
                    proxy.scrollTo(CompGroup.europe.id, anchor: .top)
                }
            }
            }
            .background { AmbientBackground(colors: [Color(red: 0.42, green: 0.17, blue: 0.57), Color(red: 0.12, green: 0.25, blue: 0.66), .brand], intensity: 0.8) }
            .navigationTitle("Ligues")
            .searchable(text: $query, prompt: "Rechercher une compétition")
            .tribuneDestinations()
            .task {
                if Launch.take("league") { path.append(Route.league(Competition.named(Launch.value("-league") ?? "") ?? Competition.all[0])) }
                await fetchMissingLogos()
            }
        }
    }

    func matches(_ c: Competition) -> Bool {
        query.isEmpty || c.name.localizedCaseInsensitiveContains(query) || c.area.localizedCaseInsensitiveContains(query)
    }

    func fetchMissingLogos() async {
        let missing = Competition.all.filter { store.logo(for: $0.id) == nil }
        await withTaskGroup(of: (String, ESPNLeague?).self) { g in
            for c in missing {
                g.addTask {
                    let r = try? await ESPN.scoreboard(c.id)
                    return (c.id, r?.leagues.first)
                }
            }
            for await (id, l) in g { if let l { store.setLogos(id, l) } }
        }
    }
}

struct LeagueTile: View {
    let competition: Competition
    private var theme: CompetitionTheme? { CompetitionTheme(competition.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LeagueBadge(league: competition.id, size: 50, darkDisc: theme?.base[0] ?? Color(red: 0.06, green: 0.08, blue: 0.2),
                        glow: theme?.accent ?? competition.tint)
            Spacer(minLength: 14)
            Text(competition.name).font(.headline).foregroundStyle(theme != nil ? Color.white : Color.primary).lineLimit(2).multilineTextAlignment(.leading)
            Text(competition.area).font(.caption).foregroundStyle(theme != nil ? Color.white.opacity(0.7) : Color.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .padding(14)
        .background {
            if let theme { ThemedTileBackground(theme: theme).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous)) }
        }
        .glassSurface(cornerRadius: 26, wash: theme == nil ? [competition.tint, competition.tint.opacity(0.4)] : [], washOpacity: 0.45)
    }
}

/// Fond fixe des tuiles de coupes d'Europe : dégradé du thème, rubans de lumière, étoiles pour la LdC.
struct ThemedTileBackground: View {
    let theme: CompetitionTheme
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: theme.base), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            for (i, c) in theme.streaks.prefix(3).enumerated() {
                var l = ctx
                l.translateBy(x: size.width * 0.72 + Double(i) * 12, y: -10)
                l.rotate(by: .degrees(22))
                let rect = CGRect(x: -1.5, y: 0, width: 3, height: size.height * 1.4)
                let shade = GraphicsContext.Shading.linearGradient(Gradient(colors: [c.opacity(0), c, c.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 1.4))
                l.drawLayer { g in g.addFilter(.blur(radius: 8)); g.fill(Path(rect.insetBy(dx: -4, dy: 0)), with: shade) }
                l.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: shade)
            }
            if theme.stars {
                let pts: [(Double, Double, Double)] = [(0.55, 0.18, 2.2), (0.85, 0.35, 1.6), (0.35, 0.55, 1.2), (0.9, 0.8, 2), (0.62, 0.62, 1.4), (0.2, 0.85, 1.1), (0.75, 0.1, 1.3)]
                for p in pts {
                    let r = p.2
                    ctx.fill(Path(ellipseIn: CGRect(x: p.0 * size.width - r, y: p.1 * size.height - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.85)))
                }
            }
        }
    }
}

// MARK: - Page d'une compétition

struct CompetitionView: View {
    @Environment(AppStore.self) private var store
    let competition: Competition

    enum Pane: String, CaseIterable, Identifiable {
        case table = "Classement", bracket = "Phase finale", matches = "Matchs", stats = "Stats"
        var id: String { rawValue }
    }

    @State private var season: Int
    @State private var section: Pane
    @State private var standings: [StandingGroup]? = nil
    @State private var matches: [Match] = []
    @State private var rounds: [Round] = []
    @State private var leaders: [LeaderCategory] = []
    @State private var loading = true
    @State private var loadingLeaders = true
    @State private var showAllResults = false

    init(competition: Competition) {
        self.competition = competition
        let launchSeason = Launch.value("-season").flatMap { Int($0) }
        _season = State(initialValue: launchSeason.flatMap { s in competition.seasons.contains(s) ? s : nil } ?? competition.seasons.first ?? Competition.currentSeason)
        let pane: Pane
        switch Launch.value("-pane") {
        case "final": pane = .bracket
        case "stats": pane = .stats
        case "matches": pane = .matches
        default: pane = .table
        }
        _section = State(initialValue: pane)
    }

    private var panes: [Pane] {
        var p: [Pane] = []
        if !(standings ?? []).isEmpty { p.append(.table) }
        if !rounds.isEmpty { p.append(.bracket) }
        p.append(.matches)
        if !leaders.isEmpty || loadingLeaders { p.append(.stats) }
        return p
    }

    private var theme: CompetitionTheme? { CompetitionTheme(competition.id) }
    private var accent: Color { theme?.accent ?? competition.tint }
    @State private var logoIn = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    ZStack {
                        if theme != nil {
                            Circle()
                                .strokeBorder(AngularGradient(colors: (theme?.streaks ?? []) + [theme?.streaks.first ?? .white], center: .center), lineWidth: 2.5)
                                .frame(width: 100, height: 100)
                                .blur(radius: 0.5)
                                .rotationEffect(.degrees(logoIn ? 360 : 0))
                                .animation(.linear(duration: 14).repeatForever(autoreverses: false), value: logoIn)
                        }
                        LeagueBadge(league: competition.id, size: 88, darkDisc: theme?.base[0] ?? Color(red: 0.06, green: 0.08, blue: 0.2), glow: accent)
                            .shadow(color: accent.opacity(0.6), radius: logoIn ? 24 : 4)
                    }
                    .scaleEffect(logoIn ? 1 : 0.7)
                    .opacity(logoIn ? 1 : 0)
                    .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.15)) { logoIn = true } }
                    Text(competition.name).font(.title.weight(.bold))
                    Menu {
                        Picker("Saison", selection: $season) {
                            ForEach(competition.seasons, id: \.self) { y in Text(competition.seasonLabel(y)).tag(y) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(competition.isTournament ? "Édition \(competition.seasonLabel(season))" : "Saison \(competition.seasonLabel(season))")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.down").font(.caption.weight(.bold))
                        }
                        .foregroundStyle(theme != nil ? Color.white : Color.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .glassSurface(cornerRadius: 20, tint: accent, interactive: true)
                    }
                    .sensoryFeedback(.selection, trigger: season)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

                if panes.count > 1 {
                    GlassTabs(tabs: panes, selection: $section, tint: accent) { $0.rawValue }
                }

                Group {
                    if loading {
                        ProgressView().padding(.vertical, 60)
                    } else {
                        switch section {
                        case .table:
                            if let s = standings, !s.isEmpty { StandingsTable(league: competition.id, preloaded: s) }
                        case .bracket:
                            KnockoutView(rounds: rounds)
                        case .matches:
                            VStack(spacing: 16) { matchList }
                        case .stats:
                            if loadingLeaders { ProgressView().padding(.vertical, 60) }
                            else if leaders.isEmpty {
                                ContentUnavailableView("Pas de statistiques", systemImage: "chart.bar", description: Text("ESPN ne fournit pas les meilleurs joueurs pour cette saison."))
                            } else { LeadersView(categories: leaders, tint: accent) }
                        }
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 10)))
                .id("\(section.rawValue)-\(season)")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background {
            if let theme { ThemedBackground(theme: theme) }
            else { AmbientBackground(colors: [competition.tint, competition.tint.opacity(0.7), .brand], intensity: 1.1) }
        }
        .themedDark(theme != nil)
        .tint(accent)
        .navigationTitle(competition.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: season) { await load() }
        .refreshable { await load() }
        .onChange(of: panes) { _, p in if !p.contains(section) { section = p.first ?? .matches } }
    }

    @ViewBuilder private var matchList: some View {
        let upcoming = matches.filter { $0.state != .post }.sorted { $0.date < $1.date }
        let results = matches.filter { $0.state == .post }.sorted { $0.date > $1.date }
        if matches.isEmpty {
            ContentUnavailableView("Aucun match", systemImage: "calendar", description: Text("Pas de match pour cette saison."))
                .padding(.vertical, 30)
        }
        if !upcoming.isEmpty { DatedMatchList(title: "À venir", matches: Array(upcoming.prefix(20))) }
        if !results.isEmpty {
            DatedMatchList(title: "Résultats", matches: Array(results.prefix(showAllResults ? 400 : 30)))
            if results.count > 30 && !showAllResults {
                Button { withAnimation(.smooth) { showAllResults = true } } label: {
                    Text("Afficher les \(results.count) résultats").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .glassSurface(cornerRadius: 20, tint: accent, interactive: true)
                }
                .buttonStyle(Pressable())
            }
        }
    }

    func load() async {
        let y = season
        withAnimation(.smooth) { loading = true; loadingLeaders = true; showAllResults = false }
        async let s = loadStandings(competition.id, season: y == Competition.currentSeason && !competition.isTournament ? nil : y)
        async let m = ESPN.season(competition, year: y)
        let (st, ms) = await (s, m)
        guard y == season else { return }
        withAnimation(.smooth(duration: 0.4)) {
            standings = st
            matches = ms
            rounds = Knockout.rounds(ms)
            loading = false
        }
        let l = await LeadersAPI.load(competition.id, season: y)
        guard y == season else { return }
        withAnimation(.smooth(duration: 0.4)) { leaders = l; loadingLeaders = false }
    }
}

/// Liste de matchs groupés par jour.
struct DatedMatchList: View {
    let title: String
    let matches: [Match]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title)
            let days = groupByDay(matches)
            ForEach(days) { pair in
                Text(pair.day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(fr)).capitalizedFirst)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                ForEach(pair.matches) { m in
                    NavigationLink(value: Route.match(m)) { MatchCard(match: m) }
                        .buttonStyle(Pressable())
                        .floatIn()
                }
            }
        }
    }

    struct DayGroup: Identifiable { let day: Date; let matches: [Match]; var id: Date { day } }

    func groupByDay(_ ms: [Match]) -> [DayGroup] {
        let cal = Calendar.current
        var order: [Date] = []
        var dict: [Date: [Match]] = [:]
        for m in ms {
            let d = cal.startOfDay(for: m.date)
            if dict[d] == nil { order.append(d) }
            dict[d, default: []].append(m)
        }
        return order.map { DayGroup(day: $0, matches: dict[$0]!) }
    }
}

extension View {
    /// Les pages à thème restent toujours en mode sombre.
    @ViewBuilder func themedDark(_ on: Bool) -> some View {
        if on { self.environment(\.colorScheme, .dark).toolbarColorScheme(.dark, for: .navigationBar) }
        else { self }
    }
}
