import SwiftUI

struct LeaguesView: View {
    @Environment(AppStore.self) private var store
    @State private var path = NavigationPath()
    @State private var query = ""

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(CompGroup.allCases) { g in
                        let comps = Competition.all.filter { $0.group == g && matches($0) }
                        if !comps.isEmpty {
                            SectionTitle(text: g.rawValue)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Circle().fill(.white.opacity(0.9)).frame(width: 46, height: 46)
                    .shadow(color: competition.tint.opacity(0.6), radius: 10)
                LeagueLogo(league: competition.id, size: 30)
                    .environment(\.colorScheme, .light)
            }
            Spacer(minLength: 14)
            Text(competition.name).font(.headline).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
            Text(competition.area).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .padding(14)
        .glassSurface(cornerRadius: 26, wash: [competition.tint, competition.tint.opacity(0.4)], washOpacity: 0.45)
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
                        Circle().fill(theme?.lightLogo == true ? AnyShapeStyle(LinearGradient(colors: [theme!.base[0], .black], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.92)))
                            .frame(width: 88, height: 88)
                            .shadow(color: accent.opacity(0.85), radius: logoIn ? 30 : 6)
                        LeagueLogo(league: competition.id, size: 58).environment(\.colorScheme, theme?.lightLogo == true ? .dark : .light)
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
