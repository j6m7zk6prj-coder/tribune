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
        let urls: [String] = []
        _ = today
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
        // Points d'accès joueur
        if let sb = try? await ESPN.scoreboard("eng.1", dates: y), let ev = sb.events.first,
           let sum = try? await ESPN.summary("eng.1", event: ev.id),
           let p = sum.rosters.first?.players.first(where: { $0.starter && $0.athlete?.id != nil }), let pid = p.athlete?.id {
            lines.append("joueur \(p.athlete?.displayName ?? "") id=\(pid) stats match=\(p.stats.map { "\($0.name)=\($0.displayValue ?? "")" }.joined(separator: ","))")
            for u in ["\(PlayerAPI.base)/eng.1/athletes/\(pid)", "\(PlayerAPI.base)/eng.1/athletes/\(pid)/stats"] {
                if let r = try? await URLSession.shared.data(from: URL(string: u)!) {
                    let code = (r.1 as? HTTPURLResponse)?.statusCode ?? 0
                    lines.append(String(u.dropFirst(PlayerAPI.base.count)) + " → \(code) " + String(decoding: r.0.prefix(500), as: UTF8.self))
                }
            }
            let b = await PlayerAPI.bio(league: "eng.1", id: pid)
            lines.append("bio: âge=\(b?.age ?? "-") nat=\(b?.nationality ?? "-") taille=\(b?.height ?? "-") poste=\(b?.position ?? "-")")
            let g = await PlayerAPI.season(league: "eng.1", id: pid)
            lines.append("saison: \(g.count) groupes " + g.prefix(2).map { "\($0.title): " + $0.items.prefix(6).map { "\($0.0)=\($0.1)" }.joined(separator: ",") }.joined(separator: " | "))
        }
        let r = await ESPN.matches(on: Calendar.current.date(byAdding: .day, value: -2, to: Calendar.current.startOfDay(for: .now))!, competitions: Competition.all.filter(\.defaultOn)) { _, _ in }
        lines.append("matches(J-2) : \(r.matches.count) matchs, échec=\(r.failed)")
        lines.append("dernière erreur : \(DayCache.lastError)")
    }
}
