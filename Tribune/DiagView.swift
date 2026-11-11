import SwiftUI

/// Écran de diagnostic (lancé avec -diag) : teste les adresses de l'API depuis l'appareil.
struct DiagView: View {
    @State private var lines: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    Text(l).font(.system(size: 8.5, design: .monospaced))
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
        line += " | " + String(decoding: r.0.prefix(170), as: UTF8.self)
        lines.append(line)
    }

    func run() async {
        // Logos TheSportsDB : vérifie que chaque identifiant correspond à la bonne compétition.
        var res: [String] = []
        for (slug, id) in LeagueBadges.ids.sorted(by: { $0.key < $1.key }) {
            let r = await LeagueBadges.lookup(id)
            res.append("\(slug)=\(id):\(r?.name ?? "∅")")
        }
        lines.append(res.joined(separator: " · "))
        await probe("FR leagues", "https://www.thesportsdb.com/api/v1/json/123/search_all_leagues.php?c=France&s=Soccer", keys: false)
        if let sb = try? await ESPN.scoreboard("fra.3") {
            lines.append("ESPN fra.3: \(sb.events.count) évts, ligue=\(sb.leagues.first?.name ?? "∅")")
        } else { lines.append("ESPN fra.3: échec") }
        let psg = TeamRef(id: "160", name: "PSG", league: "fra.1", logo: nil)
        let ms = await ESPN.teamMatches(psg, upcomingOnly: true)
        lines.append("PSG à venir: " + ms.prefix(5).map { "\($0.leagueName) \($0.home.abbr)-\($0.away.abbr) \($0.date.formatted(.dateTime.day().month()))" }.joined(separator: " | "))
    }
}
