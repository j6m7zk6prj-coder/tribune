import Foundation
import SwiftUI

/// Compétitions absentes d'ESPN (Ligue 3), lues sur TheSportsDB.
enum SportsDB {
    static let leagues: [String: String] = ["fra.3": "4637"]
    static func covers(_ slug: String) -> Bool { leagues[slug] != nil }

    static func json(_ path: String) async -> [String: Any]? {
        for key in ["123", "3"] {
            guard let u = URL(string: "https://www.thesportsdb.com/api/v1/json/\(key)/\(path)"),
                  let r = try? await URLSession.shared.data(from: u),
                  (r.1 as? HTTPURLResponse)?.statusCode == 200,
                  let o = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any] else { continue }
            return o
        }
        return nil
    }

    static func seasonName(_ y: Int) -> String { "\(y)-\(y + 1)" }

    private static let utc: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static func str(_ d: [String: Any], _ k: String) -> String? {
        if let s = d[k] as? String, !s.isEmpty { return s }
        if let n = d[k] as? Int { return String(n) }
        return nil
    }

    static func badge(_ s: String?) -> URL? { s.flatMap { URL(string: $0 + "/small") } }

    static func match(_ e: [String: Any], slug: String, name: String) -> Match? {
        guard let id = str(e, "idEvent") else { return nil }
        let date = str(e, "strTimestamp").flatMap { utc.date(from: String($0.prefix(19))) }
            ?? str(e, "dateEvent").flatMap { utc.date(from: $0 + "T" + (str(e, "strTime") ?? "00:00:00").prefix(8)) }
            ?? .distantPast
        let hs = str(e, "intHomeScore"), aws = str(e, "intAwayScore")
        let status = (str(e, "strStatus") ?? "").uppercased()
        let state: MatchState
        if ["1H", "2H", "HT", "ET", "LIVE", "P", "BT"].contains(status) { state = .live }
        else if status.contains("POSTP") || status.contains("CANC") { state = .off }
        else if hs != nil && aws != nil && (status.contains("FINISH") || status == "FT" || status == "AET" || status == "PEN" || date < .now.addingTimeInterval(-3 * 3600)) { state = .post }
        else { state = .pre }
        let h = Int(hs ?? ""), a = Int(aws ?? "")
        let home = Side(id: "sdb" + (str(e, "idHomeTeam") ?? "h"), name: str(e, "strHomeTeam") ?? "—", logo: badge(str(e, "strHomeTeamBadge")),
                        score: hs, winner: state == .post && (h ?? 0) > (a ?? 0))
        let away = Side(id: "sdb" + (str(e, "idAwayTeam") ?? "a"), name: str(e, "strAwayTeam") ?? "—", logo: badge(str(e, "strAwayTeamBadge")),
                        score: aws, winner: state == .post && (a ?? 0) > (h ?? 0))
        return Match(id: "sdb" + id, league: slug, leagueName: name, date: date, state: state,
                     statusName: state == .post ? "STATUS_FULL_TIME" : state == .live && status == "HT" ? "STATUS_HALFTIME" : "",
                     clock: str(e, "strProgress").map { $0 + "'" } ?? "", home: home, away: away, venue: str(e, "strVenue"), round: nil)
    }

    actor Cache {
        static let shared = Cache()
        private var store: [String: (Date, [Match])] = [:]
        func get(_ k: String) -> [Match]? {
            guard let v = store[k], Date().timeIntervalSince(v.0) < 600 else { return nil }
            return v.1
        }
        func set(_ k: String, _ m: [Match]) { store[k] = (Date(), m) }
    }

    /// Matchs d'une saison (+ derniers et prochains, que l'offre gratuite renvoie à part).
    static func season(_ slug: String, year: Int) async -> [Match] {
        guard let id = leagues[slug] else { return [] }
        let key = "\(slug)|\(year)"
        if let c = await Cache.shared.get(key) { return c }
        let name = Competition.named(slug)?.name ?? slug
        async let s = json("eventsseason.php?id=\(id)&s=\(seasonName(year))")
        async let n = json("eventsnextleague.php?id=\(id)")
        async let p = json("eventspastleague.php?id=\(id)")
        let (ss, nn, pp) = await (s, n, p)
        var all: [[String: Any]] = []
        for o in [ss, nn, pp] { all += (o?["events"] as? [[String: Any]]) ?? [] }
        var seen = Set<String>()
        let ms = all.compactMap { match($0, slug: slug, name: name) }.filter { seen.insert($0.id).inserted }.sorted { $0.date < $1.date }
        await Cache.shared.set(key, ms)
        return ms
    }

    static func matches(on day: Date, slug: String) async -> [Match] {
        let y = Calendar.current.component(.month, from: day) >= 7 ? Calendar.current.component(.year, from: day) : Calendar.current.component(.year, from: day) - 1
        return await season(slug, year: y).filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    static func standings(_ slug: String, year: Int) async -> [StandingGroup]? {
        guard let id = leagues[slug], let o = await json("lookuptable.php?l=\(id)&s=\(seasonName(year))"),
              let rows = o["table"] as? [[String: Any]], !rows.isEmpty else { return nil }
        let out: [StandingRow] = rows.enumerated().compactMap { i, r -> StandingRow? in
            guard let tid = str(r, "idTeam") else { return nil }
            func n(_ k: String) -> Int { Int(str(r, k) ?? "") ?? 0 }
            let desc = str(r, "strDescription")
            let color: Color? = desc.map { d in
                let l = d.lowercased()
                return l.contains("promotion") ? Color.green : l.contains("relegation") ? Color.red : Color.blue
            }
            return StandingRow(id: "sdb" + tid, rank: Int(str(r, "intRank") ?? "") ?? i + 1,
                               team: TeamRef(id: "sdb" + tid, name: str(r, "strTeam") ?? "—", league: slug, logo: str(r, "strBadge")),
                               played: n("intPlayed"), diff: n("intGoalDifference"), points: n("intPoints"),
                               won: n("intWin"), drawn: n("intDraw"), lost: n("intLoss"),
                               noteColor: color, noteText: desc)
        }
        return [StandingGroup(id: 0, name: nil, rows: out.sorted { $0.rank < $1.rank })]
    }
}
