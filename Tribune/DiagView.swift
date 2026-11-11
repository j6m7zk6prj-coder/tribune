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

    func probe(_ label: String, _ u: String, keys: Bool = true) async {
        guard let url = URL(string: u), let r = try? await URLSession.shared.data(from: url) else { lines.append("\(label) → erreur réseau"); return }
        let code = (r.1 as? HTTPURLResponse)?.statusCode ?? 0
        var line = "\(label) → \(code), \(r.0.count) o"
        if let o = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any], keys { line += " clés=" + o.keys.sorted().joined(separator: ",") }
        line += " | " + String(decoding: r.0.prefix(260), as: UTF8.self)
        lines.append(line)
    }

    func run() async {
        let core = "https://site.api.espn.com/apis/v2/sports/soccer"
        let site = ESPN.site
        if let st = try? await ESPN.get("\(core)/uefa.champions/standings?season=2015") as StandingsResponse {
            lines.append("CL 2015 standings: \(st.groups.count) groupes, 1er=\(st.groups.first?.entries.first?.team?.displayName ?? "-")")
        } else { lines.append("CL 2015 standings: échec") }
        if let st = try? await ESPN.get("\(core)/eng.1/standings?season=2015") as StandingsResponse {
            lines.append("PL 2015 standings: \(st.groups.first?.entries.count ?? 0) équipes, 1er=\(st.groups.first?.entries.first?.team?.displayName ?? "-")")
        } else { lines.append("PL 2015 standings: échec") }
        await probe("SB dates=2016", "\(site)/uefa.champions/scoreboard?dates=2016")
        await probe("SB season=2015", "\(site)/uefa.champions/scoreboard?season=2015")
        if let sb = try? await ESPN.scoreboard("uefa.champions", dates: "20160528") {
            lines.append("finale 2016: \(sb.events.count) évt " + (sb.events.first.flatMap { Match($0, league: "uefa.champions") }.map { "\($0.home.short) \($0.home.score ?? "") - \($0.away.score ?? "") \($0.away.short)" } ?? ""))
        }
        // calendrier de la saison dans la réponse du tableau des scores
        if let u = URL(string: "\(site)/uefa.champions/scoreboard"), let r = try? await URLSession.shared.data(from: u),
           let o = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any],
           let lg = (o["leagues"] as? [[String: Any]])?.first {
            lines.append("league clés=" + lg.keys.sorted().joined(separator: ","))
            if let cal = lg["calendar"] as? [Any] { lines.append("calendar: \(cal.count) éléments, 1er=\(String(describing: cal.first).prefix(160))") }
            if let ev = (o["events"] as? [[String: Any]])?.first {
                lines.append("event clés=" + ev.keys.sorted().joined(separator: ","))
                lines.append("event.season=\(String(describing: ev["season"]).prefix(200))")
                if let c = (ev["competitions"] as? [[String: Any]])?.first { lines.append("comp clés=" + c.keys.sorted().joined(separator: ",") + " notes=\(String(describing: c["notes"]).prefix(150))") }
            }
        }
        await probe("leaders v3", "https://site.web.api.espn.com/apis/site/v3/sports/soccer/eng.1/leaders?season=2025")
        await probe("leaders core", "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/seasons/2025/types/1/leaders")
        await probe("statistics", "\(site)/eng.1/statistics?season=2025")
    }
}
