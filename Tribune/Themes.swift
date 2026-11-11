import SwiftUI

/// Ambiance visuelle propre à certaines compétitions.
enum CompetitionTheme {
    case champions, europa, conference

    init?(_ league: String) {
        switch league {
        case "uefa.champions": self = .champions
        case "uefa.europa": self = .europa
        case "uefa.europa.conf": self = .conference
        default: return nil
        }
    }

    var base: [Color] {
        switch self {
        case .champions: return [Color(hex: "0C1858")!, Color(hex: "070E38")!, Color(hex: "02051A")!]
        case .europa: return [Color(hex: "3A1A02")!, Color(hex: "1C0C01")!, Color(hex: "080400")!]
        case .conference: return [Color(hex: "073A21")!, Color(hex: "031B10")!, Color(hex: "010A06")!]
        }
    }

    var streaks: [Color] {
        switch self {
        case .champions: return [Color(hex: "00E5FF")!, Color(hex: "7B5CFF")!, Color(hex: "FF3EA5")!, Color(hex: "FF9F1C")!, Color(hex: "3D7BFF")!]
        case .europa: return [Color(hex: "FF8A00")!, Color(hex: "FFB547")!, Color(hex: "FF5E1A")!, Color(hex: "FFD08A")!]
        case .conference: return [Color(hex: "00E676")!, Color(hex: "B6FF3B")!, Color(hex: "00C2A8")!, Color(hex: "7CFFB2")!]
        }
    }

    var accent: Color {
        switch self {
        case .champions: return Color(red: 0.28, green: 0.72, blue: 1.0)
        case .europa: return Color(hex: "F28C18")!
        case .conference: return Color(hex: "22C96E")!
        }
    }

    var stars: Bool { self == .champions }

    /// Logo clair : on le pose sur une pastille sombre plutôt que blanche.
    var lightLogo: Bool { true }
}

/// Fond animé : dégradé profond, traînées de lumière sur le côté, étoiles pour la Ligue des champions.
struct ThemedBackground: View {
    let theme: CompetitionTheme
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(colors: theme.base, startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [theme.streaks[0].opacity(0.28), .clear], center: .init(x: 0.5, y: 0.12), startRadius: 0, endRadius: 360)
            LightStreaks(colors: theme.streaks)
                .opacity(appeared ? 1 : 0)
            if theme.stars {
                StarField()
                    .opacity(appeared ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear { withAnimation(.easeOut(duration: 1.2)) { appeared = true } }
    }
}

/// Champ d'étoiles qui scintillent et dérivent lentement.
struct StarField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Star { let x, y, size, phase, speed: Double; let shaped: Bool; let tint: Int }

    private static let stars: [Star] = {
        var seed: UInt64 = 0x5EED
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) % 10_000) / 10_000
        }
        return (0..<90).map { i in
            Star(x: rnd(), y: rnd(), size: 0.8 + rnd() * 2.2, phase: rnd() * 6.28, speed: 0.6 + rnd() * 1.8,
                 shaped: i % 7 == 0, tint: Int(rnd() * 4))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for s in Self.stars {
                    let y = (s.y - t * 0.004 * s.speed).truncatingRemainder(dividingBy: 1)
                    let yy = (y < 0 ? y + 1 : y) * size.height
                    let xx = s.x * size.width + sin(t * 0.2 + s.phase) * 4
                    let twinkle = 0.3 + 0.7 * (0.5 + 0.5 * sin(t * s.speed + s.phase))
                    let colors: [Color] = [.white, .white, Color(red: 0.6, green: 0.85, blue: 1), Color(red: 0.85, green: 0.75, blue: 1)]
                    let c = colors[s.tint].opacity(twinkle)
                    if s.shaped {
                        let r = s.size * 3.2
                        ctx.drawLayer { l in
                            l.addFilter(.blur(radius: 1.2))
                            l.fill(starPath(center: CGPoint(x: xx, y: yy), radius: r), with: .color(c))
                        }
                        ctx.fill(starPath(center: CGPoint(x: xx, y: yy), radius: r * 0.7), with: .color(.white.opacity(twinkle)))
                    } else {
                        ctx.fill(Path(ellipseIn: CGRect(x: xx - s.size / 2, y: yy - s.size / 2, width: s.size, height: s.size)), with: .color(c))
                    }
                }
            }
        }
    }

    /// Étoile à 5 branches.
    private func starPath(center: CGPoint, radius: Double) -> Path {
        var p = Path()
        for i in 0..<10 {
            let r = i % 2 == 0 ? radius : radius * 0.42
            let a = Double(i) * .pi / 5 - .pi / 2
            let pt = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Rubans de lumière colorés qui glissent le long du bord droit.
struct LightStreaks: View {
    let colors: [Color]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width, h = size.height
                for (i, c) in colors.enumerated() {
                    let p = Double(i)
                    let length = h * (0.55 + 0.1 * p.truncatingRemainder(dividingBy: 3))
                    let thick = 2.5 + (i % 2 == 0 ? 2 : 0)
                    let slide = (t * (40 + p * 9)).truncatingRemainder(dividingBy: h + length) - length
                    let x = w * 0.80 + p * 14 + sin(t * 0.35 + p) * 10
                    let rect = CGRect(x: -thick / 2, y: 0, width: thick, height: length)
                    var layer = ctx
                    layer.translateBy(x: x, y: slide)
                    layer.rotate(by: .degrees(18))
                    let shading = GraphicsContext.Shading.linearGradient(
                        Gradient(colors: [c.opacity(0), c, c.opacity(0)]),
                        startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: length))
                    layer.drawLayer { glow in
                        glow.addFilter(.blur(radius: 14))
                        glow.fill(Path(roundedRect: rect.insetBy(dx: -6, dy: 0), cornerRadius: 8), with: shading)
                    }
                    layer.fill(Path(roundedRect: rect, cornerRadius: thick / 2), with: shading)
                }
            }
            .blendMode(.screen)
        }
    }
}
