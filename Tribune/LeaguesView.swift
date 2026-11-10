import SwiftUI

struct LeaguesView: View {
    @Environment(AppStore.self) private var store
    @State private var path = NavigationPath()
    @State private var query = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(CompGroup.allCases) { g in
                    let comps = Competition.all.filter { $0.group == g && matches($0) }
                    if !comps.isEmpty {
                        Section(g.rawValue) {
                            ForEach(comps) { c in
                                NavigationLink(value: Route.league(c)) {
                                    HStack(spacing: 12) {
                                        LeagueLogo(league: c.id, size: 26)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(c.name).font(.body)
                                            Text(c.area).font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
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
                HStack(spacing: 14) {
                    LeagueLogo(league: competition.id, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(competition.name).font(.title2.weight(.bold))
                        Text(competition.area).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.top, 4)

                if !(standings ?? []).isEmpty {
                    Picker("Section", selection: $section) {
                        ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if loading {
                    ProgressView().padding(.vertical, 60)
                } else if section == .table, let s = standings, !s.isEmpty {
                    StandingsTable(league: competition.id, preloaded: s)
                } else {
                    matchList
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.bold)).padding(.horizontal, 4).padding(.top, 4)
            let days = groupByDay(matches)
            ForEach(days) { pair in
                VStack(alignment: .leading, spacing: 0) {
                    Text(pair.day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(fr)).capitalizedFirst)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    ForEach(pair.matches) { m in
                        NavigationLink(value: Route.match(m)) {
                            MatchRow(match: m).padding(.horizontal, 14).padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 6)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
