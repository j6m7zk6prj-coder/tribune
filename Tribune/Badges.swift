import Foundation

/// Logos de compétition à jour, depuis TheSportsDB (base libre et collaborative).
enum LeagueBadges {
    static let group = "group.com.tepsko.tribune"

    /// Identifiants TheSportsDB des compétitions.
    static let ids: [String: String] = [
        "fra.1": "4334", "eng.1": "4328", "esp.1": "4335", "ita.1": "4332", "ger.1": "4331",
        "uefa.champions": "4480", "uefa.europa": "4481", "uefa.europa.conf": "5071",
        "fifa.world": "4429", "uefa.euro": "4502", "uefa.nations": "4490",
        "conmebol.america": "4499", "caf.nations": "4496",
        "fra.coupe_de_france": "4484", "eng.fa": "4482", "eng.league_cup": "4570",
        "esp.copa_del_rey": "4483", "ita.coppa_italia": "4506", "ger.dfb_pokal": "4485",
        "fra.2": "4401", "fra.3": "4636", "por.1": "4344", "ned.1": "4337", "bel.1": "4338",
        "tur.1": "4339", "ksa.1": "4668", "usa.1": "4346",
    ]

    static func lookup(_ id: String) async -> (name: String, badge: URL)? {
        for key in ["123", "3"] {
            guard let u = URL(string: "https://www.thesportsdb.com/api/v1/json/\(key)/lookupleague.php?id=\(id)"),
                  let r = try? await URLSession.shared.data(from: u),
                  let o = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any],
                  let l = (o["leagues"] as? [[String: Any]])?.first,
                  let b = l["strBadge"] as? String, !b.isEmpty, let url = URL(string: b) else { continue }
            return ((l["strLeague"] as? String) ?? "", url)
        }
        return nil
    }

    /// Récupère les logos manquants (une fois par semaine au plus), 3 requêtes à la fois.
    static func refresh(_ known: [String: String]) async -> [String: String] {
        let d = UserDefaults.standard
        let last = d.double(forKey: "badgesFetchedAt")
        let stale = Date().timeIntervalSince1970 - last > 7 * 24 * 3600
        let todo = ids.filter { stale || known[$0.key + "#badge"] == nil }
        guard !todo.isEmpty else { return [:] }
        var out: [String: String] = [:]
        await withTaskGroup(of: (String, URL?).self) { g in
            var it = todo.makeIterator()
            for _ in 0..<3 { if let job = it.next() { g.addTask { (job.key, await lookup(job.value)?.badge) } } }
            for await (slug, url) in g {
                if let job = it.next() { g.addTask { (job.key, await lookup(job.value)?.badge) } }
                if let url { out[slug + "#badge"] = url.absoluteString }
            }
        }
        if !out.isEmpty { d.set(Date().timeIntervalSince1970, forKey: "badgesFetchedAt") }
        return out
    }
}
