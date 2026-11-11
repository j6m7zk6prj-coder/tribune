import SwiftUI
import AVFoundation

// MARK: - Données d'un but à rejouer

struct GoalReplay: Identifiable, Equatable {
    let id: String
    let side: Side            // club qui gagne le but (même sur un CSC)
    let isHome: Bool
    let home: Side
    let away: Side
    let before: (Int, Int)
    let after: (Int, Int)
    let scorer: String
    let minute: String
    let ownGoal: Bool
    let penalty: Bool

    static func == (a: GoalReplay, b: GoalReplay) -> Bool { a.id == b.id }

    /// Construit le but à partir du déroulé : score avant/après compté dans l'ordre.
    static func make(_ e: KeyEvent, match: Match, events: [KeyEvent]) -> GoalReplay? {
        var h = 0, a = 0
        for g in events where g.kind.isGoal {
            let before = (h, a)
            if g.teamID == match.home.id { h += 1 } else if g.teamID == match.away.id { a += 1 }
            if g.id == e.id {
                let isHome = g.teamID == match.home.id
                let name = g.athletes.first.map { $0.displayName ?? $0.shortName ?? "" } ?? ""
                return GoalReplay(id: g.id, side: isHome ? match.home : match.away, isHome: isHome, home: match.home, away: match.away,
                                  before: before, after: (h, a), scorer: name, minute: g.clockDisplay ?? "",
                                  ownGoal: g.kind == .ownGoal, penalty: g.kind == .penaltyGoal)
            }
        }
        return nil
    }
}

/// Les animations ne concernent que la Premier League pour l'instant.
func goalAnimationsEnabled(_ league: String) -> Bool { league == "eng.1" }

// MARK: - Style de chaque club

enum GoalMotif { case cannon, claws, cherries, bees, gull, eagle, tower, cottage, rose, flames, ship, trident, magpie, tree, cats, hammers, moon, crown, bolt, cockerel, fox, horse, halo, generic }
enum GoalWipe { case solid, stripes, diagonal, hex, split }
enum GoalLetters { case drop, slam, rise, spin, stretch }

struct ClubGoalStyle {
    let primary: Color
    let secondary: Color
    let text: Color
    let motif: GoalMotif
    let wipe: GoalWipe
    let letters: GoalLetters

    private static func c(_ h: String) -> Color { Color(hex: h) ?? .gray }

    static func forTeam(_ s: Side) -> ClubGoalStyle {
        let n = (s.name + " " + s.short).lowercased()
        func has(_ k: String) -> Bool { n.contains(k) }
        if has("arsenal") { return .init(primary: c("EF0107"), secondary: c("FFFFFF"), text: .white, motif: .cannon, wipe: .solid, letters: .slam) }
        if has("aston villa") { return .init(primary: c("670E36"), secondary: c("95BFE5"), text: .white, motif: .claws, wipe: .diagonal, letters: .drop) }
        if has("bournemouth") { return .init(primary: c("DA291C"), secondary: c("111111"), text: .white, motif: .cherries, wipe: .stripes, letters: .rise) }
        if has("brentford") { return .init(primary: c("E30613"), secondary: c("FBB800"), text: .white, motif: .bees, wipe: .hex, letters: .spin) }
        if has("brighton") { return .init(primary: c("0057B8"), secondary: c("FFFFFF"), text: .white, motif: .gull, wipe: .stripes, letters: .stretch) }
        if has("burnley") { return .init(primary: c("6C1D45"), secondary: c("99D6EA"), text: .white, motif: .bolt, wipe: .split, letters: .rise) }
        if has("chelsea") { return .init(primary: c("034694"), secondary: c("DBA111"), text: .white, motif: .crown, wipe: .solid, letters: .stretch) }
        if has("crystal palace") { return .init(primary: c("1B458F"), secondary: c("C4122E"), text: .white, motif: .eagle, wipe: .split, letters: .drop) }
        if has("everton") { return .init(primary: c("003399"), secondary: c("FFFFFF"), text: .white, motif: .tower, wipe: .diagonal, letters: .rise) }
        if has("fulham") { return .init(primary: c("161616"), secondary: c("FFFFFF"), text: .white, motif: .cottage, wipe: .stripes, letters: .slam) }
        if has("leeds") { return .init(primary: c("1D428A"), secondary: c("FFCD00"), text: .white, motif: .rose, wipe: .split, letters: .spin) }
        if has("liverpool") { return .init(primary: c("C8102E"), secondary: c("00B2A9"), text: .white, motif: .flames, wipe: .solid, letters: .rise) }
        if has("manchester city") || has("man city") { return .init(primary: c("6CABDD"), secondary: c("1C2C5B"), text: c("0B1A3C"), motif: .ship, wipe: .diagonal, letters: .stretch) }
        if has("manchester united") || has("man utd") || has("man united") { return .init(primary: c("DA291C"), secondary: c("FBE122"), text: .white, motif: .trident, wipe: .solid, letters: .slam) }
        if has("newcastle") { return .init(primary: c("241F20"), secondary: c("FFFFFF"), text: .white, motif: .magpie, wipe: .stripes, letters: .drop) }
        if has("nottingham") || has("forest") { return .init(primary: c("DD0000"), secondary: c("FFFFFF"), text: .white, motif: .tree, wipe: .split, letters: .rise) }
        if has("sunderland") { return .init(primary: c("EB172B"), secondary: c("211E1E"), text: .white, motif: .cats, wipe: .stripes, letters: .spin) }
        if has("tottenham") || has("spurs") { return .init(primary: c("132257"), secondary: c("FFFFFF"), text: .white, motif: .cockerel, wipe: .diagonal, letters: .stretch) }
        if has("west ham") { return .init(primary: c("7A263A"), secondary: c("1BB1E7"), text: .white, motif: .hammers, wipe: .split, letters: .slam) }
        if has("wolverhampton") || has("wolves") { return .init(primary: c("FDB913"), secondary: c("231F20"), text: c("1A1A1A"), motif: .moon, wipe: .solid, letters: .drop) }
        if has("leicester") { return .init(primary: c("003090"), secondary: c("FDBE11"), text: .white, motif: .fox, wipe: .diagonal, letters: .rise) }
        if has("southampton") { return .init(primary: c("D71920"), secondary: c("FFFFFF"), text: .white, motif: .halo, wipe: .stripes, letters: .stretch) }
        if has("ipswich") { return .init(primary: c("3A64A3"), secondary: c("FFFFFF"), text: .white, motif: .horse, wipe: .split, letters: .drop) }
        let t = s.tint
        return .init(primary: t, secondary: .white, text: .white, motif: .generic, wipe: .solid, letters: .drop)
    }
}

// MARK: - Courbes d'animation

/// Angle à partir d'un CGFloat (évite les conversions ambiguës).
func deg(_ x: CGFloat) -> Angle { Angle.degrees(Double(x)) }

enum Ease {
    static func seg(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { max(0, min(1, (t - a) / (b - a))) }
    static func outCubic(_ x: CGFloat) -> CGFloat { 1 - pow(1 - x, 3) }
    static func inOutCubic(_ x: CGFloat) -> CGFloat { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    static func outBack(_ x: CGFloat, _ s: CGFloat = 1.7) -> CGFloat { let c3 = s + 1; return 1 + c3 * pow(x - 1, 3) + s * pow(x - 1, 2) }
    static func outBounce(_ x: CGFloat) -> CGFloat {
        let n1 = 7.5625, d1 = 2.75
        if x < 1 / d1 { return n1 * x * x }
        if x < 2 / d1 { let y = x - 1.5 / d1; return n1 * y * y + 0.75 }
        if x < 2.5 / d1 { let y = x - 2.25 / d1; return n1 * y * y + 0.9375 }
        let y = x - 2.625 / d1; return n1 * y * y + 0.984375
    }
}

// MARK: - Son et vibrations

@MainActor
final class GoalSound {
    static let shared = GoalSound()
    private var player: AVAudioPlayer?

    func play() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let url = Bundle.main.url(forResource: "goal_crowd", withExtension: "m4a") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.8
        player?.play()
    }

    func stop() { player?.setVolume(0, fadeDuration: 0.3) }
}

// MARK: - Animation plein écran

struct GoalOverlay: View {
    let replay: GoalReplay
    let onDone: () -> Void

    @State private var start = Date()
    @State private var closing: Date? = nil
    private let total: CGFloat = 3.4

    var body: some View {
        let style = ClubGoalStyle.forTeam(replay.side)
        TimelineView(.animation) { tl in
            let raw = CGFloat(Launch.value("-goalhold").flatMap { Double($0) } ?? tl.date.timeIntervalSince(start))
            let t = min(raw, total)
            // Fermeture anticipée : fondu rapide.
            let out = closing.map { Ease.seg(CGFloat(tl.date.timeIntervalSince($0)), 0, 0.28) } ?? Ease.seg(t, 2.95, 3.35)
            let inA = Ease.outCubic(Ease.seg(t, 0, 0.3))
            let alpha = inA * (1 - out)

            ZStack {
                Color.black.opacity(0.62 * alpha)
                RadialGradient(colors: [style.primary.opacity(0.55 * alpha), .clear], center: .center, startRadius: 10, endRadius: 420)
                    .scaleEffect(0.8 + 0.25 * Ease.outCubic(Ease.seg(t, 0.3, 1.2)))

                VStack(spacing: 26) {
                    MotifStage(style: style, p: Ease.seg(t, 0.55, 1.95), t: t)
                        .frame(width: 340, height: 160)
                    ScoreBar(replay: replay, style: style, t: t)
                        .frame(width: 340, height: 78)
                        .scaleEffect(x: Ease.outBack(Ease.seg(t, 0, 0.32)), y: 1)
                    InfoLine(replay: replay, style: style)
                        .opacity(Ease.seg(t, 2.35, 2.7))
                        .offset(y: 14 * (1 - Ease.outCubic(Ease.seg(t, 2.35, 2.75))))
                }
                .opacity(1 - out)
                .scaleEffect(1 + 0.06 * out)
            }
            .ignoresSafeArea()
            .onChange(of: raw >= total + 0.05) { _, ended in if ended && Launch.value("-goalhold") == nil { onDone() } }
        }
        .contentShape(Rectangle())
        .onTapGesture { close() }
        .task {
            start = Date()
            GoalSound.shared.play()
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            let notify = UINotificationFeedbackGenerator()
            impact.prepare()
            try? await Task.sleep(for: .milliseconds(320)); impact.impactOccurred(intensity: 0.6)
            try? await Task.sleep(for: .milliseconds(430)); impact.impactOccurred(intensity: 1)
            try? await Task.sleep(for: .milliseconds(1500)); notify.notificationOccurred(.success)
        }
        .accessibilityElement()
        .accessibilityLabel("But de \(replay.side.short), \(replay.scorer), \(replay.minute)")
    }

    private func close() {
        guard closing == nil else { return }
        closing = Date()
        GoalSound.shared.stop()
        Task { try? await Task.sleep(for: .milliseconds(300)); onDone() }
    }
}

/// Bandeau type télévision : abréviations, score, puis volet du club et « GOAL ».
struct ScoreBar: View {
    let replay: GoalReplay
    let style: ClubGoalStyle
    let t: CGFloat

    var body: some View {
        let wipeIn = Ease.inOutCubic(Ease.seg(t, 0.3, 0.66))
        let wipeOut = Ease.inOutCubic(Ease.seg(t, 1.95, 2.3))
        let flip = Ease.seg(t, 2.15, 2.55)
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                // Fond du bandeau
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))

                HStack(spacing: 0) {
                    TeamChip(side: replay.home, highlight: replay.isHome && t > 2.2, color: replay.isHome ? style.primary : Color(white: 0.25))
                    Spacer()
                    HStack(spacing: 12) {
                        FlipDigit(old: replay.before.0, new: replay.after.0, p: replay.isHome ? flip : 0)
                        Text("-").foregroundStyle(.white.opacity(0.5))
                        FlipDigit(old: replay.before.1, new: replay.after.1, p: replay.isHome ? 0 : flip)
                    }
                    .font(.system(size: 38, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    Spacer()
                    TeamChip(side: replay.away, highlight: !replay.isHome && t > 2.2, color: replay.isHome ? Color(white: 0.25) : style.primary)
                }
                .padding(.horizontal, 10)

                // Volet du club
                WipeLayer(style: style, t: t, w: w, h: h)
                    .mask(Parallelogram(from: wipeOut, to: wipeIn, skew: 22))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: style.primary.opacity(0.6 * wipeIn * (1 - wipeOut)), radius: 24)
            .overlay(alignment: .leading) {
                // Logo qui jaillit
                let lp = Ease.seg(t, 0.45, 0.85)
                let lo = 1 - Ease.seg(t, 1.9, 2.15)
                Logo(url: replay.side.logo, size: 70)
                    .shadow(color: .black.opacity(0.4), radius: 6)
                    .scaleEffect(Ease.outBack(lp, 2.4) * (0.85 + 0.15 * lo))
                    .rotationEffect(deg(-25 * (1 - Ease.outCubic(lp))))
                    .opacity(lp > 0 ? lo : 0)
                    .offset(x: -14)
            }
        }
    }
}

struct TeamChip: View {
    let side: Side
    let highlight: Bool
    let color: Color
    var body: some View {
        Text(side.abbr.isEmpty ? String(side.short.prefix(3)).uppercased() : side.abbr)
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 66, height: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.gradient))
            .scaleEffect(highlight ? 1.06 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: highlight)
    }
}

/// Chiffre qui bascule de l'ancien au nouveau score.
struct FlipDigit: View {
    let old: Int
    let new: Int
    let p: CGFloat
    var body: some View {
        ZStack {
            Text("\(old)")
                .rotation3DEffect(deg(-90 * Ease.seg(p, 0, 0.5)), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.6)
                .opacity(p < 0.5 ? 1 : 0)
            Text("\(new)")
                .rotation3DEffect(deg(90 * (1 - Ease.outBack(Ease.seg(p, 0.5, 1), 1.2))), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.6)
                .opacity(p >= 0.5 ? 1 : 0)
                .scaleEffect(1 + 0.25 * sin(.pi * Ease.seg(p, 0.5, 1)))
        }
        .frame(minWidth: 30)
    }
}

/// Forme du volet : bande inclinée entre deux positions (0…1).
struct Parallelogram: Shape {
    var from: CGFloat
    var to: CGFloat
    let skew: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(from, to) }
        set { from = newValue.first; to = newValue.second }
    }
    func path(in r: CGRect) -> Path {
        let span = r.width + skew
        let x0 = -skew + span * from, x1 = -skew + span * to
        var p = Path()
        p.move(to: CGPoint(x: x0 + skew, y: 0))
        p.addLine(to: CGPoint(x: x1 + skew, y: 0))
        p.addLine(to: CGPoint(x: x1, y: r.height))
        p.addLine(to: CGPoint(x: x0, y: r.height))
        p.closeSubpath()
        return p
    }
}

/// Contenu du volet : motif de fond, « GOAL » lettre par lettre, reflet.
struct WipeLayer: View {
    let style: ClubGoalStyle
    let t: CGFloat
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        ZStack {
            WipePattern(style: style)
            HStack(spacing: 2) {
                ForEach(Array("GOAL".enumerated()), id: \.offset) { i, ch in
                    letter(String(ch), q: Ease.seg(t, 0.72 + CGFloat(i) * 0.085, 1.07 + CGFloat(i) * 0.085))
                }
            }
            .padding(.leading, 56)
            // Reflet lumineux
            let s = Ease.inOutCubic(Ease.seg(t, 1.3, 1.8))
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 70)
                .rotationEffect(deg(18))
                .offset(x: -w / 2 - 60 + (w + 120) * s)
                .opacity(s > 0 && s < 1 ? 1 : 0)
                .blendMode(.plusLighter)
        }
        .frame(width: w, height: h)
    }

    @ViewBuilder private func letter(_ s: String, q: CGFloat) -> some View {
        let base = Text(s)
            .font(.system(size: 44, weight: .black, design: .rounded).italic())
            .foregroundStyle(style.text)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
        switch style.letters {
        case .drop:
            base.offset(y: -46 * (1 - Ease.outBack(q))).opacity(q > 0 ? 1 : 0)
        case .slam:
            base.scaleEffect(2.8 - 1.8 * Ease.outCubic(q)).opacity(Ease.seg(q, 0, 0.35))
        case .rise:
            base.offset(y: 36 * (1 - Ease.outCubic(q))).blur(radius: 6 * (1 - q)).opacity(q)
        case .spin:
            base.rotation3DEffect(deg(100 * (1 - Ease.outBack(q))), axis: (x: 0, y: 1, z: 0)).opacity(q > 0 ? 1 : 0)
        case .stretch:
            base.scaleEffect(x: max(0.01, Ease.outBack(q, 2.2)), y: 1 + 0.4 * (1 - q)).opacity(q > 0 ? 1 : 0)
        }
    }
}

struct WipePattern: View {
    let style: ClubGoalStyle
    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size)
            ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [style.primary, style.primary.opacity(0.85)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let accent = style.secondary.opacity(0.28)
            switch style.wipe {
            case .solid: break
            case .stripes:
                var x: CGFloat = 0
                while x < size.width { ctx.fill(Path(CGRect(x: x, y: 0, width: 14, height: size.height)), with: .color(accent)); x += 28 }
            case .diagonal:
                var x: CGFloat = -size.height
                while x < size.width {
                    var p = Path(); p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    p.addLine(to: CGPoint(x: x + size.height + 10, y: 0)); p.addLine(to: CGPoint(x: x + 10, y: size.height)); p.closeSubpath()
                    ctx.fill(p, with: .color(accent)); x += 26
                }
            case .hex:
                let s: CGFloat = 12
                var row = 0
                var y: CGFloat = 0
                while y < size.height + s {
                    var x: CGFloat = row % 2 == 0 ? 0 : s * 0.87
                    while x < size.width + s {
                        var p = Path()
                        for k in 0..<6 {
                            let a = CGFloat(k) * .pi / 3 + .pi / 6
                            let pt = CGPoint(x: x + cos(a) * s * 0.9, y: y + sin(a) * s * 0.9)
                            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                        p.closeSubpath()
                        ctx.stroke(p, with: .color(style.secondary.opacity(0.4)), lineWidth: 1.2)
                        x += s * 1.74
                    }
                    y += s * 1.5; row += 1
                }
            case .split:
                ctx.fill(Path(CGRect(x: 0, y: size.height * 0.72, width: size.width, height: size.height * 0.28)), with: .color(style.secondary.opacity(0.85)))
            }
        }
    }
}

/// Buteur, minute, mention CSC ou penalty.
struct InfoLine: View {
    let replay: GoalReplay
    let style: ClubGoalStyle
    var body: some View {
        VStack(spacing: 6) {
            Text(replay.scorer.isEmpty ? replay.side.name : replay.scorer)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                Text(replay.minute).monospacedDigit()
                if replay.ownGoal { Text("· CSC") }
                if replay.penalty { Text("· Penalty") }
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(style.primary.opacity(0.55)))
        }
    }
}

// MARK: - Motifs des clubs

struct MotifStage: View {
    let style: ClubGoalStyle
    let p: CGFloat     // 0…1 sur la durée du motif
    let t: CGFloat

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack { motif(w: w, h: h) }
                .frame(width: w, height: h)
                .opacity(1 - Ease.seg(p, 0.88, 1))
        }
    }

    private var pri: Color { style.primary }
    private var sec: Color { style.secondary }

    private func sym(_ name: String, _ size: CGFloat, _ color: Color) -> some View {
        Image(systemName: name).font(.system(size: size, weight: .bold)).foregroundStyle(color)
            .shadow(color: color.opacity(0.6), radius: 10)
    }

    @ViewBuilder private func motif(w: CGFloat, h: CGFloat) -> some View {
        switch style.motif {
        case .cannon: m_cannon(w: w, h: h)
        case .claws: m_claws(w: w, h: h)
        case .cherries: m_cherries(w: w, h: h)
        case .bees: m_bees(w: w, h: h)
        case .gull: m_gull(w: w, h: h)
        case .eagle: m_eagle(w: w, h: h)
        case .tower: m_tower(w: w, h: h)
        case .cottage: m_cottage(w: w, h: h)
        case .rose: m_rose(w: w, h: h)
        case .flames: m_flames(w: w, h: h)
        case .ship: m_ship(w: w, h: h)
        case .trident: m_trident(w: w, h: h)
        case .magpie: m_magpie(w: w, h: h)
        case .tree: m_tree(w: w, h: h)
        case .cats: m_cats(w: w, h: h)
        case .hammers: m_hammers(w: w, h: h)
        case .moon: m_moon(w: w, h: h)
        case .crown: m_crown(w: w, h: h)
        case .bolt: m_bolt(w: w, h: h)
        case .cockerel: m_cockerel(w: w, h: h)
        case .fox: m_fox(w: w, h: h)
        case .horse: m_horse(w: w, h: h)
        case .halo: m_halo(w: w, h: h)
        case .generic: m_generic(w: w, h: h)
        }
    }

    @ViewBuilder private func m_cannon(w: CGFloat, h: CGFloat) -> some View {
        // Le canon recule en tirant, le boulet traverse l'écran, fumée et éclair.
        let fire = Ease.seg(p, 0.12, 0.2)
        let recoil = sin(.pi * Ease.seg(p, 0.12, 0.35)) * 10
        let ball = Ease.outCubic(Ease.seg(p, 0.15, 0.6))
        ZStack {
            CannonShape().fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.45)], startPoint: .top, endPoint: .bottom))
                .frame(width: 120, height: 70)
                .rotationEffect(deg(-14))
                .position(x: w * 0.2 - recoil, y: h * 0.62)
                .scaleEffect(Ease.outBack(Ease.seg(p, 0, 0.12)))
            Circle().fill(Color(white: 0.15)).frame(width: 22, height: 22)
                .position(x: w * 0.3 + (w * 0.85) * ball, y: h * 0.48 - 70 * sin(.pi * ball) * 0.6)
                .opacity(ball > 0 && ball < 1 ? 1 : 0)
            ForEach(0..<4, id: \.self) { i in
                let sp = Ease.seg(p, 0.16 + CGFloat(i) * 0.04, 0.6 + CGFloat(i) * 0.05)
                Circle().fill(Color.white.opacity(0.55 * (1 - sp)))
                    .frame(width: 20 + 50 * sp, height: 20 + 50 * sp)
                    .blur(radius: 6)
                    .position(x: w * 0.32 + CGFloat(i) * 12 + 30 * sp, y: h * 0.45 - CGFloat(i) * 6 - 20 * sp)
            }
            Image(systemName: "sparkle").font(.system(size: 54, weight: .black)).foregroundStyle(.yellow)
                .position(x: w * 0.33, y: h * 0.47)
                .scaleEffect(fire > 0 && fire < 1 ? 1 + fire : 0.01)
                .opacity(1 - fire)
        }
    }

    @ViewBuilder private func m_claws(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let q = Ease.outCubic(Ease.seg(p, CGFloat(i) * 0.08, 0.3 + CGFloat(i) * 0.08))
                Capsule().fill(LinearGradient(colors: [sec, pri, .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 10, height: 150 * q)
                    .rotationEffect(deg(28))
                    .position(x: w * 0.38 + CGFloat(i) * 36, y: h * 0.5)
                    .shadow(color: sec, radius: 8)
            }
        }
    }

    @ViewBuilder private func m_cherries(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                let q = Ease.outBounce(Ease.seg(p, CGFloat(i) * 0.1, 0.5 + CGFloat(i) * 0.1))
                VStack(spacing: -4) {
                    Capsule().fill(Color.green).frame(width: 4, height: 34).rotationEffect(deg(i == 0 ? 20 : -20))
                    Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.35, blue: 0.35), Color(red: 0.7, green: 0, blue: 0.05)], center: .topLeading, startRadius: 2, endRadius: 40))
                        .frame(width: 52, height: 52)
                }
                .position(x: w * 0.42 + CGFloat(i) * 60, y: -40 + (h * 0.62 + 40) * q)
            }
        }
    }

    @ViewBuilder private func m_bees(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let a: CGFloat = t * 3.2 + CGFloat(i) * 1.26
                let r: CGFloat = 70 * Ease.outCubic(Ease.seg(p, 0, 0.3))
                let px: CGFloat = w / 2 + cos(a) * r * 1.6
                let py: CGFloat = h / 2 + sin(a * 2) * r * 0.45
                let rot: CGFloat = cos(a) * 25
                BeeView().frame(width: 34, height: 26)
                    .rotationEffect(deg(rot))
                    .position(x: px, y: py)
            }
        }
    }

    @ViewBuilder private func m_gull(w: CGFloat, h: CGFloat) -> some View {
        let q = Ease.inOutCubic(Ease.seg(p, 0, 0.8))
        ZStack {
            ForEach(0..<4, id: \.self) { k in
                let qq = max(0, q - CGFloat(k) * 0.05)
                sym("bird.fill", 64, .white)
                    .opacity(k == 0 ? 1 : 0.25 / CGFloat(k))
                    .scaleEffect(x: -1, y: 1 + 0.15 * sin(t * 18))
                    .position(x: -40 + (w + 80) * qq, y: h * 0.55 - sin(.pi * qq) * 50)
            }
        }
    }

    @ViewBuilder private func m_eagle(w: CGFloat, h: CGFloat) -> some View {
        let q = Ease.outBack(Ease.seg(p, 0, 0.45))
        sym("bird.fill", 110, sec)
            .scaleEffect(x: -q, y: q * (1 + 0.12 * sin(t * 14)))
            .position(x: w / 2, y: h * 0.95 - h * 0.45 * q)
    }

    @ViewBuilder private func m_tower(w: CGFloat, h: CGFloat) -> some View {
        let q = Ease.outCubic(Ease.seg(p, 0, 0.45))
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Capsule().fill(sec.opacity(0.25)).frame(width: 4, height: 220)
                    .rotationEffect(deg(CGFloat(i) * 22.5 + t * 20))
            }
            .opacity(q)
            TowerShape().fill(LinearGradient(colors: [.white, sec.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                .frame(width: 70, height: 120)
                .offset(y: 140 * (1 - q))
        }
        .position(x: w / 2, y: h / 2)
        .clipped()
    }

    @ViewBuilder private func m_cottage(w: CGFloat, h: CGFloat) -> some View {
        let q = Ease.outBack(Ease.seg(p, 0, 0.35))
        ZStack {
            sym("house.fill", 96, .white).scaleEffect(q)
            HStack(spacing: 14) {
                ForEach(0..<2, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(Color.yellow.opacity(Ease.seg(p, 0.3 + CGFloat(i) * 0.08, 0.45 + CGFloat(i) * 0.08)))
                        .frame(width: 14, height: 14)
                }
            }
            .offset(y: 16)
        }
        .position(x: w / 2, y: h / 2)
    }

    @ViewBuilder private func m_rose(w: CGFloat, h: CGFloat) -> some View {
        let q = Ease.outBack(Ease.seg(p, 0, 0.45))
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Ellipse().fill(LinearGradient(colors: [.white, sec], startPoint: .top, endPoint: .bottom))
                    .frame(width: 44, height: 64)
                    .offset(y: -30)
                    .rotationEffect(deg(CGFloat(i) * 72))
            }
            Circle().fill(sec).frame(width: 30, height: 30)
        }
        .scaleEffect(q)
        .rotationEffect(deg(120 * Ease.outCubic(p)))
        .position(x: w / 2, y: h / 2)
    }

    @ViewBuilder private func m_flames(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                let q = Ease.outCubic(Ease.seg(p, CGFloat(i) * 0.04, 0.35 + CGFloat(i) * 0.04))
                Image(systemName: "flame.fill")
                    .font(.system(size: 54 + CGFloat(i % 3) * 14))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange, pri], startPoint: .top, endPoint: .bottom))
                    .scaleEffect(x: 1, y: q * (1 + 0.12 * sin(t * 16 + CGFloat(i))), anchor: .bottom)
                    .position(x: w * 0.12 + CGFloat(i) * w * 0.13, y: h * 0.62)
            }
        }
    }

    @ViewBuilder private func m_ship(w: CGFloat, h: CGFloat) -> some View {
        let q = Ease.outCubic(Ease.seg(p, 0, 0.55))
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                WaveShape(phase: t * 3 + CGFloat(i)).stroke(sec.opacity(0.5 - CGFloat(i) * 0.12), lineWidth: 3)
                    .frame(height: 30).offset(y: 40 + CGFloat(i) * 10)
            }
            sym("sailboat.fill", 84, .white)
                .rotationEffect(deg(sin(t * 4) * 6))
                .offset(x: -w * 0.6 * (1 - q), y: -4)
        }
        .position(x: w / 2, y: h / 2)
    }

    @ViewBuilder private func m_trident(w: CGFloat, h: CGFloat) -> some View {
        let q = Ease.outBack(Ease.seg(p, 0, 0.4))
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Image(systemName: "flame.fill").font(.system(size: 60))
                    .foregroundStyle(LinearGradient(colors: [sec, pri], startPoint: .top, endPoint: .bottom))
                    .scaleEffect(y: 1 + 0.15 * sin(t * 15 + CGFloat(i)), anchor: .bottom)
                    .offset(x: i == 0 ? -80 : 80, y: 20)
                    .opacity(Ease.seg(p, 0.2, 0.4))
            }
            TridentShape().fill(LinearGradient(colors: [sec, Color(red: 0.8, green: 0.6, blue: 0.1)], startPoint: .top, endPoint: .bottom))
                .frame(width: 70, height: 140)
                .offset(y: 150 * (1 - q))
                .shadow(color: sec, radius: 12)
        }
        .position(x: w / 2, y: h / 2)
    }

    @ViewBuilder private func m_magpie(w: CGFloat, h: CGFloat) -> some View {
        let q = Ease.inOutCubic(Ease.seg(p, 0, 0.7))
        ZStack {
            HStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { i in Rectangle().fill(i % 2 == 0 ? Color.white.opacity(0.18) : Color.black.opacity(0.2)) }
            }
            .opacity(Ease.seg(p, 0, 0.2) * (1 - Ease.seg(p, 0.7, 0.9)))
            sym("bird.fill", 70, .white)
                .overlay(Image(systemName: "bird.fill").font(.system(size: 70, weight: .bold)).foregroundStyle(.black).mask(Rectangle().frame(width: 70, height: 36).offset(y: 18)))
                .position(x: w + 40 - (w + 80) * q, y: h * 0.45 + sin(.pi * 2 * q) * 20)
        }
    }

    @ViewBuilder private func m_tree(w: CGFloat, h: CGFloat) -> some View {
        let q = Ease.outBack(Ease.seg(p, 0, 0.45), 1.3)
        ZStack {
            sym("tree.fill", 110, .white).scaleEffect(q, anchor: .bottom)
            ForEach(0..<10, id: \.self) { i in
                let lp = Ease.seg(p, 0.3 + CGFloat(i) * 0.03, 0.9)
                Circle().fill(Color.green.opacity(0.8 * (1 - lp))).frame(width: 8, height: 8)
                    .offset(x: CGFloat(i - 5) * 14 + CGFloat(sin(CGFloat(i) * 1.7)) * 20 * lp, y: -40 + 90 * lp)
            }
        }
        .position(x: w / 2, y: h * 0.55)
    }

    @ViewBuilder private func m_cats(w: CGFloat, h: CGFloat) -> some View {
        let q = Ease.outCubic(Ease.seg(p, 0, 0.45))
        ZStack {
            sym("cat.fill", 90, .white)
            HStack(spacing: 14) {
                ForEach(0..<2, id: \.self) { _ in Capsule().fill(Color.yellow).frame(width: 7, height: 10).shadow(color: .yellow, radius: 6) }
            }
            .offset(x: 6, y: -14)
            .opacity(Ease.seg(p, 0.35, 0.5))
        }
        .position(x: -60 + (w / 2 + 60) * q, y: h * 0.55 - sin(.pi * q) * 60)
    }

    @ViewBuilder private func m_hammers(w: CGFloat, h: CGFloat) -> some View {
        let strike = Ease.outBack(Ease.seg(p, 0, 0.3), 2.5)
        let spark = Ease.seg(p, 0.28, 0.7)
        ZStack {
            sym("hammer.fill", 80, .white).rotationEffect(deg(-70 + 50 * strike)).offset(x: -34)
            sym("hammer.fill", 80, sec).scaleEffect(x: -1, y: 1).rotationEffect(deg(70 - 50 * strike)).offset(x: 34)
            ForEach(0..<12, id: \.self) { i in
                let a = CGFloat(i) / 12 * 2 * .pi
                Circle().fill(Color.yellow).frame(width: 6, height: 6)
                    .offset(x: cos(a) * 90 * spark, y: -30 + sin(a) * 60 * spark)
                    .opacity(spark > 0 ? 1 - spark : 0)
            }
        }
        .position(x: w / 2, y: h / 2)
    }

    @ViewBuilder private func m_moon(w: CGFloat, h: CGFloat) -> some View {
        let q = Ease.outCubic(Ease.seg(p, 0, 0.45))
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let rp = Ease.seg(p, 0.3 + CGFloat(i) * 0.12, 0.8 + CGFloat(i) * 0.08)
                Circle().stroke(pri.opacity(1 - rp), lineWidth: 3).frame(width: 80 + 160 * rp, height: 80 + 160 * rp)
            }
            sym("moon.fill", 90, pri).offset(y: 120 * (1 - q))
        }
        .position(x: w / 2, y: h / 2)
    }

    @ViewBuilder private func m_crown(w: CGFloat, h: CGFloat) -> some View {
        let q = Ease.outBounce(Ease.seg(p, 0, 0.5))
        ZStack {
            sym("crown.fill", 92, sec).offset(y: -140 + 140 * q)
            ForEach(0..<6, id: \.self) { i in
                Image(systemName: "sparkle").font(.system(size: 18)).foregroundStyle(.white)
                    .offset(x: cos(CGFloat(i)) * 90, y: sin(CGFloat(i) * 1.3) * 50)
                    .scaleEffect(Ease.seg(p, 0.45, 0.6) * (0.7 + 0.3 * sin(t * 10 + CGFloat(i))))
            }
        }
        .position(x: w / 2, y: h / 2)
    }

    @ViewBuilder private func m_bolt(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                let q = Ease.seg(p, 0.05 + CGFloat(i) * 0.22, 0.2 + CGFloat(i) * 0.22)
                sym("bolt.fill", 100, i == 0 ? .yellow : sec)
                    .scaleEffect(q > 0 ? 1 : 0.01)
                    .opacity(q > 0 ? 1 - Ease.seg(p, 0.6 + CGFloat(i) * 0.1, 0.85) : 0)
                    .offset(x: i == 0 ? -50 : 50)
            }
            Color.white.opacity(0.35 * (1 - Ease.seg(p, 0.05, 0.16)) * (p > 0.05 ? 1 : 0)).blendMode(.plusLighter)
        }
        .position(x: w / 2, y: h / 2)
    }

    @ViewBuilder private func m_cockerel(w: CGFloat, h: CGFloat) -> some View {
        let bounce = Ease.outBounce(Ease.seg(p, 0, 0.5))
        VStack(spacing: -6) {
            sym("bird.fill", 64, .white).scaleEffect(x: -1, y: 1)
            Circle().fill(.white).frame(width: 40, height: 40).overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 2))
        }
        .position(x: w / 2, y: -60 + (h * 0.55 + 60) * bounce)
    }

    @ViewBuilder private func m_fox(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let q = Ease.seg(p, CGFloat(i) * 0.09, 0.15 + CGFloat(i) * 0.09)
                sym("pawprint.fill", 34, i % 2 == 0 ? sec : .white)
                    .rotationEffect(deg(90))
                    .scaleEffect(Ease.outBack(q))
                    .position(x: w * 0.15 + CGFloat(i) * w * 0.17, y: h * 0.5 + (i % 2 == 0 ? -18 : 18))
            }
        }
    }

    @ViewBuilder private func m_horse(w: CGFloat, h: CGFloat) -> some View {
        let q = Ease.inOutCubic(Ease.seg(p, 0, 0.75))
        sym("figure.equestrian.sports", 88, .white)
            .offset(y: -abs(sin(t * 9)) * 10)
            .position(x: -60 + (w + 120) * q, y: h * 0.55)
    }

    @ViewBuilder private func m_halo(w: CGFloat, h: CGFloat) -> some View {
        let q = Ease.outBack(Ease.seg(p, 0, 0.4))
        ZStack {
            Ellipse().stroke(LinearGradient(colors: [.yellow, .white], startPoint: .leading, endPoint: .trailing), lineWidth: 8)
                .frame(width: 150 * q, height: 40 * q)
                .rotation3DEffect(deg(t * 90), axis: (x: 0, y: 1, z: 0))
                .shadow(color: .yellow, radius: 14)
            sym("sparkles", 50, .white).offset(y: 50).opacity(Ease.seg(p, 0.3, 0.45))
        }
        .position(x: w / 2, y: h / 2)
    }

    @ViewBuilder private func m_generic(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            ForEach(0..<14, id: \.self) { i in
                let a = CGFloat(i) / 14 * 2 * .pi
                let q = Ease.outCubic(Ease.seg(p, 0, 0.6))
                Image(systemName: "sparkle").font(.system(size: 16)).foregroundStyle(i % 2 == 0 ? pri : sec)
                    .offset(x: cos(a) * 120 * q, y: sin(a) * 60 * q)
                    .opacity(1 - Ease.seg(p, 0.5, 0.9))
            }
        }
        .position(x: w / 2, y: h / 2)
    }
}

// MARK: - Formes dessinées

struct CannonShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: r.minX + r.width * 0.15, y: r.minY + r.height * 0.18, width: r.width * 0.85, height: r.height * 0.36), cornerSize: CGSize(width: 10, height: 10))
        p.addRoundedRect(in: CGRect(x: r.maxX - 10, y: r.minY + r.height * 0.12, width: 10, height: r.height * 0.48), cornerSize: CGSize(width: 3, height: 3))
        p.addEllipse(in: CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.42, width: r.height * 0.56, height: r.height * 0.56))
        return p
    }
}

struct TowerShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.addRect(CGRect(x: r.minX + w * 0.15, y: r.minY + h * 0.22, width: w * 0.7, height: h * 0.78))
        for i in 0..<4 { p.addRect(CGRect(x: r.minX + w * 0.15 + CGFloat(i) * w * 0.19, y: r.minY + h * 0.12, width: w * 0.12, height: h * 0.12)) }
        p.addRect(CGRect(x: r.minX + w * 0.47, y: r.minY, width: w * 0.06, height: h * 0.14))
        return p
    }
}

struct TridentShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height, cx = r.midX
        p.addRect(CGRect(x: cx - 4, y: r.minY + h * 0.25, width: 8, height: h * 0.75))
        p.addRect(CGRect(x: r.minX + w * 0.1, y: r.minY + h * 0.3, width: w * 0.8, height: 8))
        for x in [r.minX + w * 0.1, cx - 4, r.maxX - w * 0.1 - 8] {
            p.addRect(CGRect(x: x, y: r.minY + h * 0.08, width: 8, height: h * 0.24))
            var tip = Path()
            tip.move(to: CGPoint(x: x - 4, y: r.minY + h * 0.09)); tip.addLine(to: CGPoint(x: x + 4, y: r.minY)); tip.addLine(to: CGPoint(x: x + 12, y: r.minY + h * 0.09)); tip.closeSubpath()
            p.addPath(tip)
        }
        return p
    }
}

struct WaveShape: Shape {
    var phase: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        var x = r.minX
        while x <= r.maxX {
            p.addLine(to: CGPoint(x: x, y: r.midY + sin(CGFloat(x) / 22 + phase) * r.height * 0.35))
            x += 4
        }
        return p
    }
}

struct BeeView: View {
    var body: some View {
        ZStack {
            Ellipse().fill(Color(red: 1, green: 0.8, blue: 0.1))
            HStack(spacing: 5) { ForEach(0..<2, id: \.self) { _ in Rectangle().fill(.black).frame(width: 4) } }
            Ellipse().fill(.white.opacity(0.8)).frame(width: 14, height: 10).offset(x: -2, y: -12)
        }
    }
}

// MARK: - Petite explosion du ballon (terrain)

struct BallBurst: View {
    let color: Color
    let trigger: Int
    @State private var start: Date? = nil

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { tl in
            let p: CGFloat = start.map { Ease.seg(CGFloat(tl.date.timeIntervalSince($0)), 0, 0.7) } ?? 1
            ZStack {
                ForEach(0..<16, id: \.self) { i in
                    let a = CGFloat(i) / 16 * 2 * .pi
                    Circle().fill(i % 3 == 0 ? Color.white : color)
                        .frame(width: i % 2 == 0 ? 6 : 4, height: i % 2 == 0 ? 6 : 4)
                        .offset(x: cos(a) * 46 * Ease.outCubic(p), y: sin(a) * 46 * Ease.outCubic(p))
                        .opacity(p < 1 ? 1 - p : 0)
                }
                Circle().stroke(color, lineWidth: 3).frame(width: 10 + 70 * p, height: 10 + 70 * p).opacity(p < 1 ? 1 - p : 0)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in start = Date() }
    }
}
