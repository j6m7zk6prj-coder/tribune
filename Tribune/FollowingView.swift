import SwiftUI

struct FollowingView: View {
    @Environment(AppStore.self) private var store
    @State private var path = NavigationPath()
    @State private var showPicker = false
    @State private var showSettings = false
    @State private var nextMatches: [String: Match] = [:]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(store.favorites) { t in
                        NavigationLink(value: Route.team(t)) {
                            TeamTile(team: t, next: nextMatches[t.id], line: nextMatches[t.id].map { nextLine($0, team: t) })
                        }
                        .buttonStyle(Pressable())
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation(.smooth) { store.toggle(t) }
                            } label: { Label("Ne plus suivre", systemImage: "star.slash") }
                        }
                        .floatIn()
                    }
                    if !store.favorites.isEmpty {
                        Button { showPicker = true } label: {
                            VStack(spacing: 10) {
                                Image(systemName: "plus").font(.title2.weight(.semibold))
                                Text("Ajouter").font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(Color.brand)
                            .frame(maxWidth: .infinity, minHeight: 168)
                            .glassSurface(cornerRadius: 28, tint: .brand)
                        }
                        .buttonStyle(Pressable())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .animation(.smooth(duration: 0.4), value: store.favorites)
            }
            .scrollIndicators(.hidden)
            .background { AmbientBackground(colors: store.favorites.isEmpty ? [.brand] : store.favorites.prefix(3).map(\.tint), intensity: 0.9) }
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
        case .live: return "\(m.home.score ?? "0") – \(m.away.score ?? "0") contre \(opp)"
        default:
            let d = m.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(fr))
            return "\(opp)\n\(d.capitalizedFirst) · \(m.kickoff)"
        }
    }

    func loadNext() async {
        await withTaskGroup(of: (String, Match?).self) { g in
            for t in store.favorites {
                g.addTask {
                    let ms = await ESPN.teamMatches(t, upcomingOnly: true)
                    let next = ms.filter { $0.state == .live }.first ?? ms.filter { $0.state == .pre && $0.date > .now }.min { $0.date < $1.date }
                    return (t.id, next)
                }
            }
            for await (id, m) in g { nextMatches[id] = m }
        }
    }
}

struct TeamTile: View {
    let team: TeamRef
    let next: Match?
    let line: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                FloatingLogo(url: team.logoURL, tint: team.tint, size: 50, delay: Double(team.id.count % 3) * 0.6)
                Spacer()
                if next?.state == .live { LiveDot(size: 8).padding(6) }
            }
            Spacer(minLength: 12)
            Text(team.name).font(.headline).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
            if let line {
                Text(line).font(.caption).foregroundStyle(next?.state == .live ? Color.brand : Color.secondary)
                    .lineLimit(2).multilineTextAlignment(.leading).padding(.top, 3)
            } else {
                Text(Competition.named(team.league)?.name ?? " ").font(.caption).foregroundStyle(.secondary).padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
        .padding(14)
        .glassSurface(cornerRadius: 28, wash: [team.tint, team.tint.opacity(0.35)], washOpacity: 0.5)
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
            let ref = TeamRef(id: t.id ?? "", name: t.displayName ?? "—", league: competition.id, logo: t.logoURL?.absoluteString, color: usableHex(t.color, t.alternateColor))
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

    /// Couleur de l'équipe : celle enregistrée, sinon celle trouvée dans ses matchs.
    private var tint: Color {
        if team.color != nil { return team.tint }
        for m in matches {
            for s in [m.home, m.away] where s.id == team.id && usableHex(s.color, s.altColor) != nil { return s.tint }
        }
        return team.tint
    }

    var body: some View {
        let upcoming = matches.filter { $0.state != .post }.sorted { $0.date < $1.date }
        let results = matches.filter { $0.state == .post }.sorted { $0.date > $1.date }
        let following = store.isFavorite(team.id)
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 14) {
                    FloatingLogo(url: team.logoURL, tint: tint, size: 100)
                        .padding(.top, 10)
                    Text(team.name).font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
                    Button {
                        withAnimation(.smooth) { store.toggle(team) }
                    } label: {
                        Label(following ? "Suivie" : "Suivre", systemImage: following ? "checkmark" : "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(following ? Color.primary : Color.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background { if !following { Capsule().fill(tint.gradient) } }
                            .glassSurface(cornerRadius: 22, tint: following ? nil : tint, interactive: true)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(Pressable())
                    .sensoryFeedback(.selection, trigger: following)
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
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background { AmbientBackground(colors: [tint, tint.opacity(0.8), tint], intensity: 1.15) }
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let ms = await ESPN.teamMatches(team)
            withAnimation(.smooth(duration: 0.4)) {
                matches = ms
                loading = false
            }
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
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(r.1.gradient))
                    .shadow(color: r.1.opacity(0.5), radius: 6)
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 24)
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
