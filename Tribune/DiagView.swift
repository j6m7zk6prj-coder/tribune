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
        // Ligue 3 : ESPN et TheSportsDB
        for slug in ["fra.3", "fra.national", "fra.nat", "fra.3.national"] {
            let ok = (try? await ESPN.scoreboard(slug)) != nil
            lines.append("ESPN \(slug): \(ok ? "OK" : "non")")
        }
        if let u = URL(string: "https://www.thesportsdb.com/api/v1/json/123/search_all_leagues.php?c=France&s=Soccer"),
           let r = try? await URLSession.shared.data(from: u),
           let o = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any],
           let arr = (o["countries"] as? [[String: Any]]) ?? (o["leagues"] as? [[String: Any]]) {
            lines.append("FR: " + arr.map { "\($0["idLeague"] ?? "")=\($0["strLeague"] ?? "")" }.joined(separator: " · "))
            if let nat = arr.first(where: { (($0["strLeague"] as? String) ?? "").localizedCaseInsensitiveContains("National") || (($0["strLeague"] as? String) ?? "").localizedCaseInsensitiveContains("Ligue 3") }),
               let id = nat["idLeague"] as? String {
                await probe("table \(id)", "https://www.thesportsdb.com/api/v1/json/123/lookuptable.php?l=\(id)&s=2026-2027", keys: true)
                await probe("next \(id)", "https://www.thesportsdb.com/api/v1/json/123/eventsnextleague.php?id=\(id)", keys: true)
                await probe("past \(id)", "https://www.thesportsdb.com/api/v1/json/123/eventspastleague.php?id=\(id)", keys: true)
                await probe("season \(id)", "https://www.thesportsdb.com/api/v1/json/123/eventsseason.php?id=\(id)&s=2026-2027", keys: true)
            }
        }
    }
}
