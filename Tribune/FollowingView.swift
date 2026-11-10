import SwiftUI

struct FollowingView: View {
    @Environment(AppStore.self) private var store
    @State private var path = NavigationPath()
    @State private var showPicker = false
    @State private var showSettings = false
    @State private var nextMatches: [String: Match] = [:]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !store.favorites.isEmpty {
                    Section("Équipes") {
                        ForEach(store.favorites) { t in
                            NavigationLink(value: Route.team(t)) {
                                HStack(spacing: 12) {
                                    Logo(url: t.logoURL, size: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.name).font(.body)
                                        if let m = nextMatches[t.id] {
                                            Text(nextLine(m, team: t)).font(.footnote).foregroundStyle(m.state == .live ? Color.brand : .secondary)
                                        } else {
                                            Text(Competition.named(t.league)?.name ?? "").font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .onDelete { store.favorites.remove(atOffsets: $0) }
                        .onMove { store.favorites.move(fromOffsets: $0, toOffset: $1) }
                    }
                }
                Section {
                    Button { showPicker = true } label: {
                        Label("Ajouter des équipes", systemImage: "plus")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if store.favorites.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune équipe suivie", systemImage: "star")
                    } description: {
                        Text("Suis tes clubs et tes sélections pour voir leurs matchs en premier.")
                    } actions: {
                        Button("Ajouter des équipes") { showPicker = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Suivis")
            .toolbar {
                if !store.favorites.isEmpty { ToolbarItem(placement: .topBarLeading) { EditButton() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Réglages")
                }
            }
            .tribuneDestinations()
            .sheet(isPresented: $showPicker) { TeamPicker() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task(id: store.favorites) {
                if Launch.take("team"), let t = store.favorites.first { path.append(Route.team(t)) }
                await loadNext()
            }
        }
    }

    func nextLine(_ m: Match, team: TeamRef) -> String {
        let opp = m.home.id == team.id ? m.away.short : m.home.short
        switch m.state {
        case .live: return "En direct · \(m.home.score ?? "0") - \(m.away.score ?? "0") contre \(opp)"
        default:
            let d = m.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(fr))
            return "\(d) · \(m.kickoff) contre \(opp)"
        }
    }

    func loadNext() async {
        await withTaskGroup(of: (String, Match?).self) { g in
            for t in store.favorites {
                g.addTask {
                    let evs = await ESPN.schedule(t.league, team: t.id)
                    let ms = evs.compactMap { Match($0, league: t.league) }
                    let next = ms.filter { $0.state == .live }.first ?? ms.filter { $0.state == .pre && $0.date > .now }.min { $0.date < $1.date }
                    return (t.id, next)
                }
            }
            for await (id, m) in g { nextMatches[id] = m }
        }
    }
}

// MARK: - Choisir des équipes

struct TeamPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                ForEach(CompGroup.allCases.filter { $0 != .cups }) { g in
                    Section(g.rawValue) {
                        ForEach(Competition.all.filter { $0.group == g }) { c in
                            NavigationLink {
                                LeagueTeamsList(competition: c)
                            } label: {
                                HStack(spacing: 12) {
                                    LeagueLogo(league: c.id, size: 24)
                                    Text(c.name)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ajouter des équipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
        }
    }
}

struct LeagueTeamsList: View {
    @Environment(AppStore.self) private var store
    let competition: Competition
    @State private var teams: [ESPNTeam] = []
    @State private var loading = true
    @State private var query = ""

    var body: some View {
        let shown = teams.filter { query.isEmpty || ($0.displayName ?? "").localizedCaseInsensitiveContains(query) }
        List(shown, id: \.id) { t in
            let ref = TeamRef(id: t.id ?? "", name: t.displayName ?? "—", league: competition.id, logo: t.logoURL?.absoluteString)
            Button { store.toggle(ref) } label: {
                HStack(spacing: 12) {
                    Logo(url: t.logoURL, size: 28)
                    Text(ref.name).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: store.isFavorite(ref.id) ? "star.fill" : "star")
                        .foregroundStyle(store.isFavorite(ref.id) ? Color.brand : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .sensoryFeedback(.selection, trigger: store.isFavorite(ref.id))
        }
        .overlay {
            LoadingOrEmpty(loading: loading, empty: teams.isEmpty, failed: false, emptyTitle: "Aucune équipe", emptyIcon: "person.3")
        }
        .searchable(text: $query, prompt: "Rechercher")
        .navigationTitle(competition.name)
        .task {
            teams = ((try? await ESPN.teams(competition.id)) ?? []).filter { $0.id != nil }
                .sorted { ($0.displayName ?? "") < ($1.displayName ?? "") }
            loading = false
        }
    }
}

// MARK: - Page d'une équipe

struct TeamView: View {
    @Environment(AppStore.self) private var store
    let team: TeamRef
    @State private var matches: [Match] = []
    @State private var loading = true

    var body: some View {
        let upcoming = matches.filter { $0.state != .post }.sorted { $0.date < $1.date }
        let results = matches.filter { $0.state == .post }.sorted { $0.date > $1.date }
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Logo(url: team.logoURL, size: 76)
                    Text(team.name).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                    if let c = Competition.named(team.league) {
                        NavigationLink(value: Route.league(c)) {
                            HStack(spacing: 6) {
                                LeagueLogo(league: c.id, size: 16)
                                Text(c.name).font(.subheadline)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                if !results.isEmpty { FormStrip(team: team, results: Array(results.prefix(5))) }

                if loading {
                    ProgressView().padding(.vertical, 40)
                } else if matches.isEmpty {
                    ContentUnavailableView("Aucun match", systemImage: "calendar")
                } else {
                    if !upcoming.isEmpty { DatedMatchList(title: "Prochains matchs", matches: Array(upcoming.prefix(8))) }
                    if !results.isEmpty { DatedMatchList(title: "Derniers résultats", matches: Array(results.prefix(10))) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggle(team) } label: {
                    Image(systemName: store.isFavorite(team.id) ? "star.fill" : "star")
                        .contentTransition(.symbolEffect(.replace))
                }
                .sensoryFeedback(.selection, trigger: store.isFavorite(team.id))
                .accessibilityLabel(store.isFavorite(team.id) ? "Ne plus suivre" : "Suivre")
            }
        }
        .task {
            let evs = await ESPN.schedule(team.league, team: team.id)
            matches = evs.compactMap { Match($0, league: team.league) }
            loading = false
        }
    }
}

/// Forme récente : V / N / D.
struct FormStrip: View {
    let team: TeamRef
    let results: [Match]
    var body: some View {
        HStack(spacing: 8) {
            Text("Forme").font(.subheadline.weight(.semibold))
            Spacer()
            ForEach(Array(results.reversed())) { m in
                let r = outcome(m)
                Text(r.0)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(r.1))
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    func outcome(_ m: Match) -> (String, Color) {
        let home = m.home.id == team.id
        let mine = Int((home ? m.home.score : m.away.score) ?? "") ?? 0
        let theirs = Int((home ? m.away.score : m.home.score) ?? "") ?? 0
        let win = home ? m.home.winner : m.away.winner
        let lose = home ? m.away.winner : m.home.winner
        if win || (!lose && mine > theirs) { return ("V", Color.brand) }
        if lose || mine < theirs { return ("D", Color(.systemRed)) }
        return ("N", Color(.systemGray))
    }
}
