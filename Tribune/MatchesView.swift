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
    private let range = -7...7

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                DayStrip(selection: $offset, range: range)
                Divider()
                TabView(selection: $offset) {
                    ForEach(range, id: \.self) { off in
                        DayPage(day: Self.day(off), isToday: off == 0, isActive: abs(off - offset) <= 1, isSelected: off == offset, liveOnly: liveOnly) { m in
                            path.append(Route.match(m))
                        }
                        .tag(off)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Matchs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { liveOnly.toggle() } label: {
                        HStack(spacing: 5) {
                            Circle().fill(liveOnly ? Color.brand : Color.secondary).frame(width: 7, height: 7)
                            Text("Live").font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(liveOnly ? Color.brand : .primary)
                    }
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
                HStack(spacing: 22) {
                    ForEach(range, id: \.self) { off in
                        Button {
                            withAnimation(.snappy(duration: 0.3)) { selection = off }
                        } label: {
                            VStack(spacing: 7) {
                                Text(label(off))
                                    .font(.subheadline.weight(selection == off ? .semibold : .regular))
                                    .foregroundStyle(selection == off ? .primary : .secondary)
                                ZStack {
                                    Capsule().fill(.clear).frame(height: 3)
                                    if selection == off {
                                        Capsule().fill(Color.brand).frame(height: 3)
                                            .matchedGeometryEffect(id: "underline", in: ns)
                                    }
                                }
                            }
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                        .id(off)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, v in withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(v, anchor: .center) } }
        }
    }

    func label(_ off: Int) -> String {
        switch off {
        case -1: return "Hier"
        case 0: return "Aujourd’hui"
        case 1: return "Demain"
        default:
            let s = MatchesView.day(off).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(fr))
            return s.prefix(1).uppercased() + s.dropFirst()
        }
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

    @State private var matches: [Match] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        let shown = liveOnly ? matches.filter { $0.state == .live } : matches
        let favs = store.favoriteIDs
        let followed = shown.filter { $0.involves(favs) }.sorted { $0.date < $1.date }
        let blocks = Self.blocks(shown)

        List {
            if !followed.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "star.fill").font(.system(size: 13)).foregroundStyle(Color.brand).frame(width: 20)
                        Text("Mes équipes").font(.subheadline.weight(.semibold))
                    }
                    ForEach(followed) { m in
                        PlainLink(value: Route.match(m)) { MatchRow(match: m) }
                    }
                }
            }
            ForEach(blocks) { b in
                Section {
                    PlainLink(value: Route.league(Competition.named(b.id) ?? Competition(id: b.id, name: b.name, area: "", group: .others))) {
                        LeagueHeaderRow(league: b.id, name: b.name)
                    }
                    ForEach(b.matches) { m in
                        PlainLink(value: Route.match(m)) { MatchRow(match: m) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .contentMargins(.top, 10, for: .scrollContent)
        .overlay {
            LoadingOrEmpty(loading: loading && matches.isEmpty, empty: shown.isEmpty, failed: failed && matches.isEmpty,
                           emptyTitle: liveOnly ? "Aucun match en direct" : "Aucun match",
                           emptyIcon: liveOnly ? "dot.radiowaves.left.and.right" : "calendar",
                           emptyText: liveOnly ? nil : "Aucun match ce jour-là dans tes compétitions.") {
                Task { await load() }
            }
        }
        .refreshable { await load() }
        .task(id: TaskKey(enabled: store.enabled, active: isActive)) {
            guard isActive else { return }
            await load()
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
        let r = await ESPN.matches(on: day, competitions: store.enabledCompetitions) { league, url in
            store.setLogo(league, url)
        }
        failed = r.failed
        if !r.failed || matches.isEmpty { matches = r.matches.sorted { $0.date < $1.date } }
        loading = false
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
