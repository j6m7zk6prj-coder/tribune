import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case facts = "Résumé", lineups = "Compos", stats = "Stats", table = "Classement"
    var id: String { rawValue }
    static var fromLaunch: DetailTab {
        switch Launch.value("-detailTab") {
        case "compos": .lineups
        case "stats": .stats
        case "table": .table
        default: .facts
        }
    }
}

struct MatchDetailView: View {
    @Environment(AppStore.self) private var store
    @State private var match: Match
    @State private var summary: SummaryResponse?
    @State private var loading = true
    @State private var tab: DetailTab = .fromLaunch

    init(match: Match) { _match = State(initialValue: match) }

    private var events: [KeyEvent] {
        (summary?.keyEvents ?? []).sorted { ($0.period ?? 0, $0.clockValue ?? 0) < ($1.period ?? 0, $1.clockValue ?? 0) }
    }
    private var hasLineups: Bool { summary?.rosters.contains { $0.players.contains(where: \.starter) } ?? false }
    private var hasStats: Bool { summary?.boxTeams.contains { !$0.statistics.isEmpty } ?? false }
    private var tabs: [DetailTab] {
        var t: [DetailTab] = [.facts]
        if hasLineups { t.append(.lineups) }
        if hasStats { t.append(.stats) }
        t.append(.table)
        return t
    }

    var body: some View {
        let colors = teamColors(match)
        ScrollView {
            VStack(spacing: 0) {
                MatchHeader(match: match, events: events, colors: colors)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 22)

                GlassTabs(tabs: tabs, selection: $tab, tint: colors.0) { $0.rawValue }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                Group {
                    switch tab {
                    case .facts: FactsView(match: match, events: events, summary: summary, loading: loading, colors: colors)
                    case .lineups: LineupView(match: match, rosters: summary?.rosters ?? [], events: events)
                    case .stats: StatsView(match: match, teams: summary?.boxTeams ?? [])
                    case .table: StandingsTable(league: match.league, highlight: [match.home.id, match.away.id], compact: false)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 12)))
                .id(tab)
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .background { AmbientBackground(colors: [colors.0, colors.1, colors.0], intensity: 1.15) }
        .navigationTitle(match.leagueName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach([match.home, match.away], id: \.id) { s in
                        let t = TeamRef(s, league: match.league)
                        Button {
                            store.toggle(t)
                        } label: {
                            Label(store.isFavorite(s.id) ? "Ne plus suivre \(s.short)" : "Suivre \(s.short)",
                                  systemImage: store.isFavorite(s.id) ? "star.slash" : "star")
                        }
                    }
                } label: {
                    Image(systemName: store.isFavorite(match.home.id) || store.isFavorite(match.away.id) ? "star.fill" : "star")
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel("Suivre une équipe")
            }
        }
        .task {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(match.state == .live ? 30 : 120))
                if Task.isCancelled { break }
                if match.state != .post { await load() }
            }
        }
        .onChange(of: tabs) { _, t in if !t.contains(tab) { tab = .facts } }
    }

    func load() async {
        if let s = try? await ESPN.summary(match.league, event: match.id) {
            withAnimation(.smooth(duration: 0.4)) {
                summary = s
                if let e = s.event, var m = Match(e, league: match.league, leagueName: match.leagueName) {
                    // L'en-tête de la fiche ne donne pas toujours les couleurs : on garde celles déjà connues.
                    if m.home.color == nil { m.home.color = match.home.color; m.home.altColor = match.home.altColor }
                    if m.away.color == nil { m.away.color = match.away.color; m.away.altColor = match.away.altColor }
                    match = m
                }
            }
        }
        loading = false
    }
}

// MARK: - En-tête

struct MatchHeader: View {
    let match: Match
    let events: [KeyEvent]
    let colors: (Color, Color)

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 0) {
                TeamColumn(side: match.home, league: match.league, tint: colors.0, delay: 0)
                VStack(spacing: 10) {
                    if match.hasScore {
                        HStack(spacing: 10) {
                            Text(match.home.score ?? "0").contentTransition(.numericText())
                            Text("–").foregroundStyle(.secondary)
                            Text(match.away.score ?? "0").contentTransition(.numericText())
                        }
                        .font(.system(size: 50, weight: .heavy, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        if let h = match.home.shootout, let a = match.away.shootout {
                            Text("Tirs au but \(h) – \(a)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(match.kickoff)
                            .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    StatusChip(match: match)
                }
                .frame(width: 140)
                .padding(.top, 16)
                TeamColumn(side: match.away, league: match.league, tint: colors.1, delay: 1.3)
            }

            let goals = events.filter { $0.kind.isGoal }
            if !goals.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    ScorerList(lines: Self.scorers(goals.filter { $0.teamID == match.home.id }), alignment: .trailing)
                    Image(systemName: "soccerball").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 40).padding(.top, 1)
                    ScorerList(lines: Self.scorers(goals.filter { $0.teamID == match.away.id }), alignment: .leading)
                }
                .transition(.opacity)
            }
        }
    }

    /// « Mbappé 12', 67' (pén.) »
    static func scorers(_ goals: [KeyEvent]) -> [String] {
        var order: [String] = []
        var minutes: [String: [String]] = [:]
        for g in goals {
            let who = g.athletes.first.map { $0.lastName ?? $0.shortName ?? $0.displayName ?? "" } ?? ""
            let name = who.isEmpty ? "But" : who
            if minutes[name] == nil { order.append(name) }
            var m = g.clockDisplay ?? ""
            if g.kind == .penaltyGoal { m += " (pén.)" }
            if g.kind == .ownGoal { m += " (csc)" }
            minutes[name, default: []].append(m)
        }
        return order.map { "\($0) \(minutes[$0]!.joined(separator: ", "))" }
    }
}

struct StatusChip: View {
    let match: Match
    var body: some View {
        HStack(spacing: 6) {
            if match.state == .live { LiveDot() }
            Text(match.longStatus)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(match.state == .live ? Color.brand : Color.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassSurface(cornerRadius: 16, tint: match.state == .live ? Color.brand : nil)
    }
}

struct ScorerList: View {
    let lines: [String]
    let alignment: HorizontalAlignment
    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            ForEach(lines, id: \.self) { Text($0) }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }
}

struct TeamColumn: View {
    let side: Side
    let league: String
    let tint: Color
    var delay: Double = 0
    var body: some View {
        NavigationLink(value: Route.team(TeamRef(side, league: league))) {
            VStack(spacing: 12) {
                FloatingLogo(url: side.logo, tint: tint, size: 74, delay: delay)
                Text(side.short)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(Pressable())
    }
}

// MARK: - Résumé (déroulé du match)

struct FactsView: View {
    let match: Match
    let events: [KeyEvent]
    let summary: SummaryResponse?
    let loading: Bool
    let colors: (Color, Color)

    var body: some View {
        VStack(spacing: 14) {
            let shown = events.filter { [EventKind]([.goal, .penaltyGoal, .ownGoal, .penaltyMissed, .yellow, .secondYellow, .red, .sub, .halftime]).contains($0.kind) }
            if !shown.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(timeline(shown).enumerated()), id: \.offset) { i, item in
                        item
                    }
                }
                .padding(.vertical, 6)
                .glassSurface(cornerRadius: 26)
            } else if loading {
                ProgressView().padding(.vertical, 40)
            } else if match.state == .pre {
                InfoRow(icon: "clock", text: "Coup d’envoi à \(match.kickoff)")
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(cornerRadius: 22)
            }

            VStack(alignment: .leading, spacing: 12) {
                InfoRow(icon: "calendar", text: match.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute().locale(fr)).capitalizedFirst)
                InfoRow(icon: "trophy", text: match.leagueName)
                if let v = summary?.venue?.fullName ?? match.venue {
                    InfoRow(icon: "sportscourt", text: [v, summary?.venue?.city].compactMap { $0 }.joined(separator: ", "))
                }
                if let a = summary?.attendance, a > 0 {
                    InfoRow(icon: "person.3", text: "\(a.formatted(.number.locale(fr))) spectateurs")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 22)
        }
    }

    func timeline(_ evs: [KeyEvent]) -> [AnyView] {
        var h = 0, a = 0
        var rows: [AnyView] = []
        for e in evs {
            if e.kind == .halftime {
                rows.append(AnyView(
                    HStack(spacing: 10) {
                        Capsule().fill(Color.primary.opacity(0.12)).frame(height: 1)
                        Text("Mi-temps  \(h) – \(a)")
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Capsule().fill(Color.primary.opacity(0.12)).frame(height: 1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                ))
                continue
            }
            var scoreText: String? = nil
            if e.kind.isGoal {
                if e.teamID == match.home.id { h += 1 } else if e.teamID == match.away.id { a += 1 }
                scoreText = "\(h) - \(a)"
            }
            rows.append(AnyView(EventRow(event: e, isHome: e.teamID == match.home.id, score: scoreText, tint: e.teamID == match.home.id ? colors.0 : colors.1)))
        }
        return rows
    }
}

struct InfoRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 22)
            Text(text).font(.subheadline)
        }
    }
}

struct EventIcon: View {
    let kind: EventKind
    var body: some View {
        switch kind {
        case .goal, .penaltyGoal:
            Image(systemName: "soccerball").font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
        case .ownGoal:
            Image(systemName: "soccerball").font(.system(size: 15, weight: .semibold)).foregroundStyle(.red)
        case .penaltyMissed:
            Image(systemName: "xmark.circle").font(.system(size: 15)).foregroundStyle(.red)
        case .yellow:
            RoundedRectangle(cornerRadius: 2).fill(Color.yellow).frame(width: 11, height: 15)
        case .red:
            RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 11, height: 15)
        case .secondYellow:
            ZStack {
                RoundedRectangle(cornerRadius: 2).fill(Color.yellow).frame(width: 11, height: 15).offset(x: -3, y: -2)
                RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 11, height: 15).offset(x: 2, y: 1)
            }
        case .sub:
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
        default:
            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.secondary)
        }
    }
}

struct EventRow: View {
    let event: KeyEvent
    let isHome: Bool
    let score: String?
    var tint: Color = .brand

    var body: some View {
        HStack(spacing: 12) {
            if isHome {
                minute
                EventIcon(kind: event.kind).frame(width: 20)
                texts(.leading)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                texts(.trailing)
                EventIcon(kind: event.kind).frame(width: 20)
                minute
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            if event.kind.isGoal {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: isHome ? [tint.opacity(0.45), tint.opacity(0.05)] : [tint.opacity(0.05), tint.opacity(0.45)],
                                         startPoint: .leading, endPoint: .trailing))
                    .padding(.horizontal, 6)
            }
        }
    }

    private var minute: some View {
        Text(event.clockDisplay ?? "")
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: isHome ? .leading : .trailing)
    }

    private func name(_ a: ESPNAthlete?) -> String { a?.displayName ?? a?.shortName ?? "" }

    @ViewBuilder private func texts(_ al: HorizontalAlignment) -> some View {
        VStack(alignment: al, spacing: 2) {
            switch event.kind {
            case .sub:
                Text(name(event.athletes.first)).font(.subheadline).foregroundStyle(Color.brand)
                if event.athletes.count > 1 { Text(name(event.athletes[1])).font(.footnote).foregroundStyle(.secondary) }
            case .goal, .penaltyGoal, .ownGoal:
                HStack(spacing: 6) {
                    if !isHome, let score { Text(score).font(.subheadline.weight(.bold).monospacedDigit()) }
                    Text(name(event.athletes.first)).font(.subheadline.weight(.semibold))
                    if isHome, let score { Text(score).font(.subheadline.weight(.bold).monospacedDigit()) }
                }
                if event.kind == .penaltyGoal { Text("Penalty").font(.footnote).foregroundStyle(.secondary) }
                else if event.kind == .ownGoal { Text("Contre son camp").font(.footnote).foregroundStyle(.secondary) }
                else if event.athletes.count > 1 { Text("Passe : \(name(event.athletes[1]))").font(.footnote).foregroundStyle(.secondary) }
            case .penaltyMissed:
                Text(name(event.athletes.first)).font(.subheadline)
                Text("Penalty manqué").font(.footnote).foregroundStyle(.secondary)
            default:
                Text(name(event.athletes.first).isEmpty ? event.typeText : name(event.athletes.first)).font(.subheadline)
            }
        }
        .multilineTextAlignment(al == .leading ? .leading : .trailing)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
