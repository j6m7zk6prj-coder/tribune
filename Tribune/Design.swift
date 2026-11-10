import SwiftUI

// MARK: - Couleurs des équipes

/// Une couleur d'équipe exploitable : ni blanc pur ni noir pur.
func usableRGB(_ hex: String?) -> (Double, Double, Double)? {
    guard let c = hexRGB(hex) else { return nil }
    let lum = 0.299 * c.0 + 0.587 * c.1 + 0.114 * c.2
    return (lum > 0.88 || lum < 0.07) ? nil : c
}

func usableHex(_ a: String?, _ b: String?) -> String? {
    if usableRGB(a) != nil { return a }
    if usableRGB(b) != nil { return b }
    return nil
}

/// Couleur stable dérivée de l'identifiant quand ESPN n'en fournit pas.
func fallbackHue(_ id: String) -> Color {
    let sum = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    return Color(hue: Double(sum % 360) / 360, saturation: 0.62, brightness: 0.82)
}

func teamColor(hex: String?, alt: String?, id: String) -> Color {
    if let c = usableRGB(hex) ?? usableRGB(alt) { return Color(red: c.0, green: c.1, blue: c.2) }
    return fallbackHue(id)
}

extension Side { var tint: Color { teamColor(hex: color, alt: altColor, id: id) } }
extension TeamRef { var tint: Color { teamColor(hex: color, alt: nil, id: id) } }

/// Couleurs des deux équipes d'un match, en évitant deux teintes trop proches.
func teamColors(_ m: Match) -> (Color, Color) {
    func hue(_ c: (Double, Double, Double)) -> Double {
        var hh: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
        UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1).getHue(&hh, saturation: &s, brightness: &b, alpha: &al)
        return Double(hh)
    }
    func tooClose(_ x: (Double, Double, Double), _ y: (Double, Double, Double)) -> Bool {
        let dh = abs(hue(x) - hue(y)), dist = abs(x.0 - y.0) + abs(x.1 - y.1) + abs(x.2 - y.2)
        return min(dh, 1 - dh) < 0.09 || dist < 0.45
    }
    let home = m.home.tint
    guard let h = usableRGB(m.home.color) ?? usableRGB(m.home.altColor) else { return (home, m.away.tint) }
    if let a = usableRGB(m.away.color), !tooClose(h, a) { return (home, Color(red: a.0, green: a.1, blue: a.2)) }
    if let a = usableRGB(m.away.altColor), !tooClose(h, a) { return (home, Color(red: a.0, green: a.1, blue: a.2)) }
    if usableRGB(m.away.color) == nil && usableRGB(m.away.altColor) == nil { return (home, m.away.tint) }
    return (home, Color(red: 0.55, green: 0.57, blue: 0.62))
}

// MARK: - Fond vivant

/// Fond organique : quelques halos de couleur flous qui dérivent lentement.
struct AmbientBackground: View {
    var colors: [Color]
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let cs = colors.isEmpty ? [Color.brand] : colors
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack {
                    ForEach(0..<max(cs.count, 3), id: \.self) { i in
                        let p = Double(i)
                        let c = cs[i % cs.count]
                        Circle()
                            .fill(c)
                            .frame(width: w * 1.05, height: w * 1.05)
                            .position(
                                x: w * (i % 2 == 0 ? 0.18 : 0.86) + sin(t * 0.11 + p * 2.1) * w * 0.16,
                                y: h * (0.04 + 0.2 * p) + cos(t * 0.09 + p * 1.3) * h * 0.05
                            )
                            .opacity((scheme == .dark ? 0.55 : 0.32) * intensity * (i == 2 ? 0.7 : 1))
                    }
                }
                .blur(radius: 90)
                .animation(.easeInOut(duration: 1.4), value: colors)
            }
        }
        .background(scheme == .dark ? Color.black : Color(.systemGroupedBackground))
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Verre liquide teinté

@available(iOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var g = Glass.regular
    if let tint { g = g.tint(tint.opacity(0.28)) }
    if interactive { g = g.interactive() }
    return g
}

extension View {
    /// Surface en Liquid Glass (iOS 26) ou matériau translucide, avec un voile de couleurs.
    @ViewBuilder func glassSurface(cornerRadius: CGFloat = 24, tint: Color? = nil, wash: [Color] = [], washOpacity: Double = 0.30, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let washed = self
            .background {
                if !wash.isEmpty {
                    shape.fill(LinearGradient(colors: wash.map { $0.opacity(washOpacity) } + [wash.last!.opacity(washOpacity * 0.35)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 0.6))
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            washed.glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            washed.background(shape.fill(.ultraThinMaterial)).background(shape.fill((tint ?? .clear).opacity(0.2)))
        }
        #else
        washed.background(shape.fill(.ultraThinMaterial)).background(shape.fill((tint ?? .clear).opacity(0.2)))
        #endif
    }

    /// Entrée douce des éléments pendant le défilement.
    func floatIn() -> some View {
        scrollTransition(.animated(.smooth(duration: 0.35))) { c, phase in
            c.opacity(phase.isIdentity ? 1 : 0.35)
                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                .offset(y: phase.value * 10)
        }
    }
}

/// Léger enfoncement au toucher.
struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - Petits éléments animés

/// Point « en direct » qui pulse.
struct LiveDot: View {
    var size: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle().fill(Color.brand).frame(width: size, height: size)
            .background {
                if !reduceMotion {
                    Circle().fill(Color.brand)
                        .phaseAnimator([false, true]) { c, on in
                            c.scaleEffect(on ? 2.6 : 1).opacity(on ? 0 : 0.7)
                        } animation: { on in on ? .easeOut(duration: 1.3) : .linear(duration: 0.01) }
                }
            }
    }
}

/// Logo qui flotte doucement, avec un halo de la couleur de l'équipe.
struct FloatingLogo: View {
    let url: URL?
    let tint: Color
    var size: CGFloat = 72
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    var body: some View {
        Logo(url: url, size: size)
            .shadow(color: tint.opacity(0.75), radius: size * 0.32)
            .offset(y: up ? -size * 0.04 : size * 0.04)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true).delay(delay)) { up = true }
            }
    }
}

/// Sélecteur d'onglets en verre, avec une pastille teintée qui glisse.
struct GlassTabs<T: Hashable>: View {
    let tabs: [T]
    @Binding var selection: T
    var tint: Color = .brand
    let title: (T) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { t in
                Button {
                    withAnimation(.smooth(duration: 0.35)) { selection = t }
                } label: {
                    Text(title(t))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == t ? Color.white : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selection == t {
                                Capsule()
                                    .fill(LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                                    .shadow(color: tint.opacity(0.45), radius: 8, y: 2)
                                    .matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassSurface(cornerRadius: 24)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Titre de section discret.
struct SectionTitle: View {
    let text: String
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(.footnote.weight(.bold)).foregroundStyle(Color.brand) }
            Text(text).font(.title3.weight(.bold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
    }
}
