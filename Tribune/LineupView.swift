import SwiftUI

struct LineupView: View {
    let match: Match
    let rosters: [Roster]
    let events: [KeyEvent]

    private var home: Roster? { rosters.first { $0.homeAway == "home" } ?? rosters.first }
    private var away: Roster? { rosters.first { $0.homeAway == "away" } ?? (rosters.count > 1 ? rosters[1] : nil) }
    @State private var picked: PlayerPick?

    var body: some View {
        let marks = PlayerMarks(events)
        let colors = teamColors(match)
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                TeamBar(side: match.home, formation: home?.formation)
                PitchView(home: home?.players.filter(\.starter) ?? [], away: away?.players.filter(\.starter) ?? [],
                          homeFormation: home?.formation, awayFormation: away?.formation,
                          homeColor: colors.0, awayColor: colors.1, marks: marks)
                TeamBar(side: match.away, formation: away?.formation)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .glassSurface(cornerRadius: 26)

            Bench(title: "Remplaçants", home: home?.players.filter { !$0.starter } ?? [], away: away?.players.filter { !$0.starter } ?? [], marks: marks)
        }
        .environment(\.onPlayerTap) { p in
            let isHome = home?.players.contains { $0.id == p.id } ?? true
            picked = PlayerPick(player: p, isHome: isHome)
        }
        .sheet(item: $picked) { pick in
            PlayerSheet(player: pick.player, side: pick.isHome ? match.home : match.away,
                        opponent: pick.isHome ? match.away : match.home,
                        tint: pick.isHome ? colors.0 : colors.1, match: match, marks: marks)
        }
        .task(id: rosters.count) {
            // Capture d'écran automatique : ouvre la fiche du premier buteur.
            if Launch.args.contains("-player"), !Launch.consumed.contains("player"), let first = (home?.players ?? []).first(where: { marks.goals[$0.id] != nil }) ?? (away?.players ?? []).first(where: { marks.goals[$0.id] != nil }) ?? home?.players.first {
                Launch.consumed.insert("player")
                let isHome = home?.players.contains { $0.id == first.id } ?? true
                picked = PlayerPick(player: first, isHome: isHome)
            }
        }
    }
}

struct PlayerPick: Identifiable {
    let player: RosterPlayer
    let isHome: Bool
    var id: String { player.id }
}

struct PlayerTapKey: EnvironmentKey {
    static let defaultValue: (RosterPlayer) -> Void = { _ in }
}

extension EnvironmentValues {
    var onPlayerTap: (RosterPlayer) -> Void {
        get { self[PlayerTapKey.self] }
        set { self[PlayerTapKey.self] = newValue }
    }
}

struct TeamBar: View {
    let side: Side
    let formation: String?
    var body: some View {
        HStack(spacing: 10) {
            Logo(url: side.logo, size: 22)
            Text(side.short).font(.subheadline.weight(.semibold))
            Spacer()
            if let formation { Text(formation).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Buts, cartons et remplacements de chaque joueur.
struct PlayerMarks {
    var goals: [String: Int] = [:]
    var yellow: Set<String> = []
    var red: Set<String> = []
    var subbedOff: Set<String> = []
    var subbedOn: Set<String> = []
    var assists: [String: Int] = [:]
    /// Minutes clés de chaque joueur (but, passe, carton, entrée, sortie).
    var moments: [String: [(String, String)]] = [:]
    init(_ evs: [KeyEvent]) {
        for e in evs {
            guard let id = e.athletes.first?.id else { continue }
            let minute = e.clockDisplay ?? ""
            switch e.kind {
            case .goal, .penaltyGoal:
                goals[id, default: 0] += 1
                moments[id, default: []].append((e.kind == .penaltyGoal ? "But (penalty)" : "But", minute))
                if e.athletes.count > 1, let a = e.athletes[1].id {
                    assists[a, default: 0] += 1
                    moments[a, default: []].append(("Passe décisive", minute))
                }
            case .ownGoal: moments[id, default: []].append(("But contre son camp", minute))
            case .yellow: yellow.insert(id); moments[id, default: []].append(("Carton jaune", minute))
            case .red, .secondYellow: red.insert(id); moments[id, default: []].append(("Carton rouge", minute))
            case .sub:
                subbedOn.insert(id); moments[id, default: []].append(("Entré en jeu", minute))
                if e.athletes.count > 1, let o = e.athletes[1].id { subbedOff.insert(o); moments[o, default: []].append(("Remplacé", minute)) }
            default: break
            }
        }
    }
}

// MARK: - Terrain

struct PitchView: View {
    let home: [RosterPlayer]
    let away: [RosterPlayer]
    let homeFormation: String?
    let awayFormation: String?
    let homeColor: Color
    let awayColor: Color
    let marks: PlayerMarks

    var body: some View {
        VStack(spacing: 0) {
            Half(lines: Self.lines(home, formation: homeFormation), color: homeColor, marks: marks)
            Half(lines: Array(Self.lines(away, formation: awayFormation).reversed()), color: awayColor, marks: marks)
        }
        .padding(.vertical, 10)
        .frame(height: 640)
        .background { PitchLines() }
        .background {
            ZStack {
                Color(red: 0.06, green: 0.22, blue: 0.14)
                // Bandes de tonte.
                VStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { i in
                        Rectangle().fill(Color.white.opacity(i % 2 == 0 ? 0.035 : 0))
                    }
                }
                LinearGradient(colors: [homeColor.opacity(0.42), .clear, .clear, awayColor.opacity(0.42)], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    /// Range les titulaires en lignes, du gardien aux attaquants.
    static func lines(_ players: [RosterPlayer], formation: String?) -> [[RosterPlayer]] {
        guard !players.isEmpty else { return [] }
        // Si la formation est connue (ex. 3-4-2-1), on la respecte : joueurs triés du gardien
        // vers l'attaque, puis découpés selon la formation.
        let counts = (formation ?? "").split(separator: "-").compactMap { Int($0) }
        if !counts.isEmpty, counts.reduce(0, +) == players.count - 1 {
            let ordered = players.sorted {
                (lineIndex($0.position), $0.formationPlace ?? 99) < (lineIndex($1.position), $1.formationPlace ?? 99)
            }
            var result: [[RosterPlayer]] = [[ordered[0]]]
            var rest = Array(ordered.dropFirst())
            for n in counts {
                let line = rest.prefix(n).sorted { (sideIndex($0.position), $0.formationPlace ?? 99) < (sideIndex($1.position), $1.formationPlace ?? 99) }
                result.append(line); rest = Array(rest.dropFirst(n))
            }
            return result
        }
        let withPos = players.filter { $0.position != nil }
        if withPos.count >= players.count - 1 {
            var rows: [Int: [RosterPlayer]] = [:]
            for p in players { rows[lineIndex(p.position), default: []].append(p) }
            return rows.keys.sorted().map { k in
                rows[k]!.sorted { (sideIndex($0.position), $0.formationPlace ?? 99) < (sideIndex($1.position), $1.formationPlace ?? 99) }
            }
        }
        // Repli : découpe selon la formation (ex. 4-3-3) dans l'ordre des postes.
        let sorted = players.sorted { ($0.formationPlace ?? 99) < ($1.formationPlace ?? 99) }
        var result: [[RosterPlayer]] = [[sorted[0]]]
        var rest = Array(sorted.dropFirst())
        let fallbackCounts = (formation ?? "").split(separator: "-").compactMap { Int($0) }
        for n in fallbackCounts where !rest.isEmpty {
            result.append(Array(rest.prefix(n))); rest = Array(rest.dropFirst(n))
        }
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    static func lineIndex(_ pos: String?) -> Int {
        let p = (pos ?? "").uppercased()
        if p == "G" || p == "GK" { return 0 }
        if p == "D" || p.hasPrefix("CD") || p.hasPrefix("CB") || p == "LB" || p == "RB" || p.hasSuffix("WB") || p.hasPrefix("SW") || p.hasPrefix("LB") || p.hasPrefix("RB") { return 1 }
        if p.hasPrefix("DM") { return 2 }
        if p.hasPrefix("AM") { return 4 }
        if p.contains("M") { return 3 }
        return 5
    }

    static func sideIndex(_ pos: String?) -> Int {
        let p = (pos ?? "").uppercased()
        if p.hasSuffix("-L") || (p.hasPrefix("L") && p.count <= 3) { return 0 }
        if p.hasSuffix("-R") || (p.hasPrefix("R") && p.count <= 3) { return 2 }
        return 1
    }
}

private struct Half: View {
    let lines: [[RosterPlayer]]
    let color: Color
    let marks: PlayerMarks
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 0) {
                    ForEach(line) { p in
                        PlayerDot(player: p, color: color, marks: marks).frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 6)
    }
}

private struct PlayerDot: View {
    let player: RosterPlayer
    let color: Color
    let marks: PlayerMarks
    @Environment(\.onPlayerTap) private var onTap

    var body: some View {
        let id = player.athlete?.id ?? ""
        Button { onTap(player) } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                        .shadow(color: color.opacity(0.8), radius: 8)
                    Text(player.jersey ?? "")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1)
                }
                .overlay(alignment: .topTrailing) {
                    if marks.red.contains(id) {
                        RoundedRectangle(cornerRadius: 1.5).fill(.red).frame(width: 8, height: 11).offset(x: 4, y: -2)
                    } else if marks.yellow.contains(id) {
                        RoundedRectangle(cornerRadius: 1.5).fill(.yellow).frame(width: 8, height: 11).offset(x: 4, y: -2)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let g = marks.goals[id], g > 0 {
                        Badge(icon: "soccerball", count: g).offset(x: -8, y: -4)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let a = marks.assists[id], a > 0 {
                        Badge(icon: "shoe.fill", count: a).offset(x: -8, y: 4)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if marks.subbedOff.contains(id) || player.subbedOut {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(Color.red))
                            .offset(x: 4, y: 3)
                    }
                }
                Text(player.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 2)
            }
        }
        .buttonStyle(Pressable())
        .accessibilityLabel("\(player.athlete?.displayName ?? player.name), voir ses statistiques")
    }
}

/// Pastille d'action sur un joueur (but, passe décisive).
struct Badge: View {
    let icon: String
    let count: Int
    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            if count > 1 { Text("\(count)").font(.system(size: 9, weight: .heavy)) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, count > 1 ? 4 : 3)
        .padding(.vertical, 3)
        .background(Capsule().fill(.black.opacity(0.62)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
    }
}

private struct PitchLines: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let inset: CGFloat = 10
            let rect = CGRect(x: inset, y: inset, width: w - inset * 2, height: h - inset * 2)
            var p = Path()
            p.addRect(rect)
            p.move(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addEllipse(in: CGRect(x: rect.midX - 44, y: rect.midY - 44, width: 88, height: 88))
            let boxW = rect.width * 0.56, boxH = rect.height * 0.12
            let sixW = rect.width * 0.26, sixH = rect.height * 0.045
            p.addRect(CGRect(x: rect.midX - boxW / 2, y: rect.minY, width: boxW, height: boxH))
            p.addRect(CGRect(x: rect.midX - boxW / 2, y: rect.maxY - boxH, width: boxW, height: boxH))
            p.addRect(CGRect(x: rect.midX - sixW / 2, y: rect.minY, width: sixW, height: sixH))
            p.addRect(CGRect(x: rect.midX - sixW / 2, y: rect.maxY - sixH, width: sixW, height: sixH))
            ctx.stroke(p, with: .color(.white.opacity(0.16)), lineWidth: 1.2)
            ctx.fill(Path(ellipseIn: CGRect(x: rect.midX - 2.5, y: rect.midY - 2.5, width: 5, height: 5)), with: .color(.white.opacity(0.2)))
        }
    }
}

// MARK: - Remplaçants

private struct Bench: View {
    @Environment(\.onPlayerTap) private var onTap
    let title: String
    let home: [RosterPlayer]
    let away: [RosterPlayer]
    let marks: PlayerMarks

    var body: some View {
        if !home.isEmpty || !away.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.subheadline.weight(.semibold)).padding(14)
                Divider().padding(.leading, 14)
                HStack(alignment: .top, spacing: 0) {
                    column(home)
                    Divider()
                    column(away)
                }
            }
            .glassSurface(cornerRadius: 26)
        }
    }

    func column(_ ps: [RosterPlayer]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ps) { p in
                let pid = p.athlete?.id ?? ""
                let came = marks.subbedOn.contains(pid) || p.subbedIn
                Button { onTap(p) } label: {
                    HStack(spacing: 6) {
                        Text(p.jersey ?? "").font(.footnote.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                        Text(p.athlete?.shortName ?? p.name).font(.footnote).foregroundStyle(.primary).lineLimit(1)
                        Spacer(minLength: 0)
                        if marks.goals[pid] != nil { Image(systemName: "soccerball").font(.system(size: 10, weight: .bold)) }
                        if marks.assists[pid] != nil { Image(systemName: "shoe.fill").font(.system(size: 10, weight: .bold)) }
                        if came { Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.brand) }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(Pressable())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
