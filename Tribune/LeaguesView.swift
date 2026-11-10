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
                if Launch.take("league") { path.append(Route.league(Competition.all[0])) }
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

    enum Pane: String, CaseIterable, Identifiable { case table = "Classement", matches = "Matchs"; var id: String { rawValue } }

    @State private var section: Pane = .table
    @State private var standings: [StandingGroup]? = nil
    @State private var matches: [Match] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(.white.opacity(0.92)).frame(width: 88, height: 88)
                            .shadow(color: competition.tint.opacity(0.8), radius: 26)
                        LeagueLogo(league: competition.id, size: 58).environment(\.colorScheme, .light)
                    }
                    Text(competition.name).font(.title.weight(.bold))
                    Text(competition.area).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

                if !(standings ?? []).isEmpty {
                    GlassTabs(tabs: Pane.allCases, selection: $section, tint: competition.tint) { $0.rawValue }
                }

                if loading {
                    ProgressView().padding(.vertical, 60)
                } else if section == .table, let s = standings, !s.isEmpty {
                    StandingsTable(league: competition.id, preloaded: s).transition(.opacity)
                } else {
                    VStack(spacing: 16) { matchList }.transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background { AmbientBackground(colors: [competition.tint, competition.tint.opacity(0.7), .brand], intensity: 1.1) }
        .navigationTitle(competition.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private var matchList: some View {
        let upcoming = matches.filter { $0.state != .post }.sorted { $0.date < $1.date }
        let results = matches.filter { $0.state == .post }.sorted { $0.date > $1.date }
        if matches.isEmpty {
            ContentUnavailableView("Aucun match", systemImage: "calendar", description: Text("Pas de match dans les semaines à venir."))
                .padding(.vertical, 30)
        }
        if !upcoming.isEmpty { DatedMatchList(title: "À venir", matches: upcoming) }
        if !results.isEmpty { DatedMatchList(title: "Résultats", matches: results) }
    }

    func load() async {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -10, to: .now) ?? .now
        let to = cal.date(byAdding: .day, value: 21, to: .now) ?? .now
        async let s = loadStandings(competition.id)
        async let m = ESPN.range(competition.id, from: from, to: to)
        let (st, sb) = await (s, m)
        standings = st
        var seen = Set<String>()
        matches = sb.events.compactMap { Match($0, league: competition.id, leagueName: competition.name) }.filter { seen.insert($0.id).inserted }
        if let l = sb.league { store.setLogos(competition.id, l) }
        if (st ?? []).isEmpty { section = .matches }
        loading = false
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
