import SwiftUI

/// Animation d'ouverture : les gradins montent, le ballon tombe, le nom apparaît, puis fondu vers l'app.
struct SplashView: View {
    @Binding var done: Bool
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let hold = Launch.args.contains("-splashhold")

    var body: some View {
        ZStack {
            AmbientBackground(colors: [.brand, Color(red: 0.05, green: 0.45, blue: 0.45), Color(red: 0.2, green: 0.2, blue: 0.6)], intensity: 1.1)
            VStack(spacing: 26) {
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(LinearGradient(colors: [Color.brand, Color.brand.opacity(0.55 + 0.15 * Double(i))], startPoint: .top, endPoint: .bottom))
                                .frame(width: 48, height: step >= 1 ? CGFloat(52 + i * 44) : 4)
                                .shadow(color: Color.brand.opacity(0.6), radius: step >= 1 ? 14 : 0)
                                .animation(.spring(response: 0.55, dampingFraction: 0.62).delay(Double(i) * 0.1), value: step)
                        }
                    }
                    Circle()
                        .fill(.white)
                        .frame(width: 40, height: 40)
                        .shadow(color: .white.opacity(0.6), radius: 12)
                        .offset(x: -58, y: step >= 2 ? -96 : -420)
                        .opacity(step >= 2 ? 1 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.5), value: step)
                }
                .frame(height: 170, alignment: .bottom)

                Text("Tribune")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(step >= 3 ? 1 : 0)
                    .offset(y: step >= 3 ? 0 : 14)
                    .blur(radius: step >= 3 ? 0 : 6)
                    .animation(.smooth(duration: 0.5), value: step)
            }
            .scaleEffect(step >= 4 ? 1.18 : 1)
        }
        .opacity(step >= 4 ? 0 : 1)
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.impact(weight: .light), trigger: step == 2)
        .task {
            if reduceMotion {
                step = 3
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.easeOut(duration: 0.3)) { step = 4 }
                try? await Task.sleep(for: .milliseconds(300))
                done = true
                return
            }
            try? await Task.sleep(for: .milliseconds(120)); step = 1
            try? await Task.sleep(for: .milliseconds(420)); step = 2
            try? await Task.sleep(for: .milliseconds(420)); step = 3
            if hold { return }
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.easeIn(duration: 0.45)) { step = 4 }
            try? await Task.sleep(for: .milliseconds(450))
            done = true
        }
    }
}
