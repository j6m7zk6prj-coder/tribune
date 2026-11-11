import SwiftUI

enum Route: Hashable {
    case match(Match)
    case league(Competition)
    case team(TeamRef)
}

extension View {
    func tribuneDestinations() -> some View {
        navigationDestination(for: Route.self) { r in
            switch r {
            case .match(let m): MatchDetailView(match: m)
            case .league(let c): CompetitionView(competition: c)
            case .team(let t): TeamView(team: t)
            }
        }
    }
}

struct MatchesView: View {
    @Environment(AppStore.self) private var store
    @State private var path = NavigationPath()
    @State private var offset: Int = Int(Launch.value("-day") ?? "0") ?? 0
    @State private var liveOnly = false
    @State private var showSettings = Launch.args.contains("-settings")
    @State private var palette: [Color] = [.brand, Color(red: 0.1, green: 0.45, blue: 0.75), Color(red: 0.35, green: 0.2, blue: 0.7)]
    private let range = -7...7

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                DayStrip(selection: $offset, range: range)
                TabView(selection: $offset) {
                    ForEach(range, id: \.self) { off in
                        DayPage(day: Self.day(off), isToday: off == 0, isActive: abs(off - offset) <= 1, isSelected: off == offset, liveOnly: liveOnly,
                                open: { m in path.append(Route.match(m)) },
                                onPalette: { cs in if off == offset { palette = cs } })
                        .tag(off)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background { AmbientBackground(colors: palette, intensity: 0.9) }
            .navigationTitle("Tribune")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.smooth) { liveOnly.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            if liveOnly { LiveDot() } else { Circle().fill(Color.secondary).frame(width: 7, height: 7) }
                            Text("Live").font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(liveOnly ? Color.brand : .primary)
                    }
                    .sensoryFeedback(.selection, trigger: liveOnly)
                    .accessibilityLabel(liveOnly ? "Afficher tous les matchs" : "Afficher seulement les matchs en direct")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Compétitions et réglages")
                }
            }
            .tribuneDestinations()
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    static func day(_ off: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: off, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }
}

// MARK: - Bandeau des jours

struct DayStrip: View {
    @Binding var selection: Int
    let range: ClosedRange<Int>
    @Namespace private var ns

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(range, id: \.self) { off in
                        Button {
                            withAnimation(.smooth(duration: 0.4)) { selection = off }
                        } label: {
                            VStack(spacing: 1) {
                                Text(top(off)).font(.caption2.weight(.semibold)).textCase(.uppercase)
                                    .foregroundStyle(selection == off ? Color.white.opacity(0.85) : Color.secondary)
                                Text(bottom(off)).font(.subheadline.weight(.bold))
                                    .foregroundStyle(selection == off ? Color.white : Color.primary)
                            }
                            .frame(minWidth: 52)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background {
                                if selection == off {
                                    Capsule()
                                        .fill(LinearGradient(colors: [Color.brand, Color.brand.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                                        .shadow(color: Color.brand.opacity(0.5), radius: 10, y: 3)
                                        .matchedGeometryEffect(id: "day", in: ns)
                                }
                            }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(off)
                    }
                }
                .padding(5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .glassSurface(cornerRadius: 30)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .sensoryFeedback(.selection, trigger: selection)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, v in withAnimation(.smooth(duration: 0.4)) { proxy.scrollTo(v, anchor: .center) } }
        }
    }

    func top(_ off: Int) -> String {
        switch off {
        case -1: return "Hier"
        case 0: return "Auj."
        case 1: return "Demain"
        default: return MatchesView.day(off).formatted(.dateTime.weekday(.abbreviated).locale(fr)).replacingOccurrences(of: ".", with: "")
        }
    }

    func bottom(_ off: Int) -> String {
        MatchesView.day(off).formatted(.dateTime.day().locale(fr)) + " " + MatchesView.day(off).formatted(.dateTime.month(.abbreviated).locale(fr)).replacingOccurrences(of: ".", with: "")
    }
}

// MARK: - Page d'un jour

struct TaskKey: Equatable { let enabled: Set<String>; let active: Bool }

struct LeagueBlock: Identifiable {
    let id: String
    let name: String
    let order: Int
    var matches: [Match]
}

struct DayPage: View {
    @Environment(AppStore.self) private var store
    let day: Date
    let isToday: Bool
    let isActive: Bool
    let isSelected: Bool
    let liveOnly: Bool
    let open: (Match) -> Void
    var onPalette: ([Color]) -> Void = { _ in }

    @State private var matches: [Match] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        let shown = liveOnly ? matches.filter { $0.state == .live } : matches
        let favs = store.favoriteIDs
        let followed = shown.filter { $0.involves(favs) }.sorted { $0.date < $1.date }
        let blocks = Self.blocks(shown)

        ScrollView {
            LazyVStack(spacing: 10) {
                if !followed.isEmpty {
                    SectionTitle(text: "Mes équipes", icon: "star.fill")
                    ForEach(followed) { m in
                        NavigationLink(value: Route.match(m)) { MatchCard(match: m, showLeague: true) }
                            .buttonStyle(Pressable())
                            .floatIn()
                    }
                }
                ForEach(blocks) { b in
                    NavigationLink(value: Route.league(Competition.named(b.id) ?? Competition(id: b.id, name: b.name, area: "", group: .others))) {
                        LeagueHeaderRow(league: b.id, name: b.name)
                    }
                    .buttonStyle(.plain)
                    ForEach(b.matches) { m in
                        NavigationLink(value: Route.match(m)) { MatchCard(match: m) }
                            .buttonStyle(Pressable())
                            .floatIn()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
            .animation(.smooth(duration: 0.4), value: shown.map(\.id))
        }
        .scrollIndicators(.hidden)
        .overlay {
            LoadingOrEmpty(loading: loading && matches.isEmpty, empty: shown.isEmpty, failed: failed && matches.isEmpty,
                           emptyTitle: liveOnly ? "Aucun match en direct" : "Aucun match",
                           emptyIcon: liveOnly ? "dot.radiowaves.left.and.right" : "calendar",
                           emptyText: liveOnly ? nil : "Aucun match ce jour-là dans tes compétitions.") {
                Task { await load() }
            }
        }
        .refreshable { await load() }
        .onChange(of: isSelected) { _, sel in if sel { onPalette(Self.palette(matches, favs: store.favoriteIDs)) } }
        .task(id: TaskKey(enabled: store.enabled, active: isActive)) {
            guard isActive else { return }
            await load()
            if isSelected, Launch.take("plmatch"), let m = matches.first(where: { $0.league == "eng.1" && $0.state == .post && (Int($0.home.score ?? "") ?? 0) + (Int($0.away.score ?? "") ?? 0) >= 2 }) {
                try? await Task.sleep(for: .milliseconds(300))
                open(m)
            }
            if isSelected, Launch.take("nextmatch"), let m = matches.first(where: { $0.state == .pre }) {
                try? await Task.sleep(for: .milliseconds(300))
                open(m)
            }
            if isSelected, Launch.take("match"), let m = (matches.first { $0.state == .post } ?? matches.first) {
                try? await Task.sleep(for: .milliseconds(300))
                open(m)
            }
            // Rafraîchissement automatique pendant les matchs.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                if isToday || matches.contains(where: { $0.state == .live }) { await load() }
            }
        }
    }

    func load() async {
        let r = await ESPN.matches(on: day, competitions: store.enabledCompetitions) { league, l in
            store.setLogos(league, l)
        }
        failed = r.failed
        if !r.failed || matches.isEmpty {
            withAnimation(.smooth(duration: 0.4)) { matches = r.matches.sorted { $0.date < $1.date } }
        }
        loading = false
        if isSelected { onPalette(Self.palette(matches, favs: store.favoriteIDs)) }
    }

    /// Couleurs du fond : celles des équipes suivies, sinon des premiers matchs du jour.
    static func palette(_ ms: [Match], favs: Set<String>) -> [Color] {
        let ordered = ms.filter { $0.involves(favs) } + ms.filter { $0.state == .live } + ms
        var out: [Color] = []
        var seen = Set<String>()
        for m in ordered {
            for s in [m.home, m.away] where seen.insert(s.id).inserted && usableHex(s.color, s.altColor) != nil {
                out.append(s.tint)
                if out.count == 3 { return out }
            }
        }
        return out.isEmpty ? [.brand] : out
    }

    static func blocks(_ ms: [Match]) -> [LeagueBlock] {
        var dict: [String: LeagueBlock] = [:]
        for m in ms {
            dict[m.league, default: LeagueBlock(id: m.league, name: m.leagueName, order: Competition.named(m.league)?.order ?? 999, matches: [])].matches.append(m)
        }
        return dict.values.sorted { $0.order < $1.order }.map { b in
            var b = b; b.matches.sort { ($0.date, $0.home.short) < ($1.date, $1.home.short) }; return b
        }
    }
}
