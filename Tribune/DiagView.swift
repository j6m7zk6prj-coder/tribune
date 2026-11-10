import SwiftUI

/// Écran de diagnostic (lancé avec -diag) : teste les adresses de l'API depuis l'appareil.
struct DiagView: View {
    @State private var lines: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    Text(l).font(.system(size: 11, design: .monospaced))
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await run() }
    }

    func run() async {
        let today = espnDay(.now)
        let y = espnDay(Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now)
        let s = ESPN.site
        let urls = [
            "\(s)/fra.1/scoreboard",
            "\(s)/fra.1/scoreboard?dates=\(y)",
            "\(s)/fra.1/scoreboard?dates=\(y)-\(today)",
            "\(s)/fra.1/scoreboard?limit=300&dates=\(y)-\(today)",
            "\(s)/eng.1/scoreboard?dates=\(y)",
            "\(s)/uefa.nations/scoreboard?dates=\(today)",
            "\(s)/fifa.friendly/scoreboard?dates=\(today)",
        ]
        for u in urls {
            var line = String(u.dropFirst(s.count))
            do {
                let (data, resp) = try await URLSession.shared.data(from: URL(string: u)!)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                line += " → \(code), \(data.count) o"
                do {
                    let r = try JSONDecoder().decode(ScoreboardResponse.self, from: data)
                    let ms = r.events.compactMap { Match($0, league: "fra.1") }
                    line += ", \(r.events.count) évts, \(ms.count) matchs"
                    if let m = ms.first { line += " [\(m.home.short)-\(m.away.short) \(m.date)]" }
                } catch { line += ", décodage : \(error)" }
                if code != 200 { line += " " + String(decoding: data.prefix(200), as: UTF8.self) }
            } catch { line += " → erreur : \(error.localizedDescription)" }
            lines.append(line)
        }
        let r = await ESPN.matches(on: Calendar.current.date(byAdding: .day, value: -2, to: Calendar.current.startOfDay(for: .now))!, competitions: Competition.all.filter(\.defaultOn)) { _, _ in }
        lines.append("matches(J-2) : \(r.matches.count) matchs, échec=\(r.failed)")
        lines.append("dernière erreur : \(DayCache.lastError)")
    }
}
