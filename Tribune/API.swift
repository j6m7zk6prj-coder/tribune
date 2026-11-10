import Foundation

/// Accès à l'API publique (non officielle) d'ESPN : gratuite et sans clé.
enum ESPN {
    static let site = "https://site.api.espn.com/apis/site/v2/sports/soccer"
    static let core = "https://site.api.espn.com/apis/v2/sports/soccer"

    static func get<T: Decodable>(_ s: String) async throws -> T {
        guard let url = URL(string: s) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func scoreboard(_ league: String, dates: String? = nil) async throws -> ScoreboardResponse {
        var s = "\(site)/\(league)/scoreboard?limit=300"
        if let dates { s += "&dates=\(dates)" }
        return try await get(s)
    }

    static func summary(_ league: String, event: String) async throws -> SummaryResponse {
        try await get("\(site)/\(league)/summary?event=\(event)")
    }

    static func standings(_ league: String) async throws -> StandingsResponse {
        try await get("\(core)/\(league)/standings")
    }

    static func teams(_ league: String) async throws -> [ESPNTeam] {
        let r: TeamsResponse = try await get("\(site)/\(league)/teams")
        return r.teams
    }

    /// Matchs passés et à venir d'une équipe.
    static func schedule(_ league: String, team: String) async -> [ESPNEvent] {
        async let past: ScheduleResponse? = try? get("\(site)/\(league)/teams/\(team)/schedule")
        async let next: ScheduleResponse? = try? get("\(site)/\(league)/teams/\(team)/schedule?fixture=true")
        let all = ((await past)?.events ?? []) + ((await next)?.events ?? [])
        var seen = Set<String>()
        return all.filter { seen.insert($0.id).inserted }
    }

    /// Tous les matchs d'un jour (heure locale), pour les compétitions choisies.
    static func matches(on day: Date, competitions: [Competition], onLogo: @escaping @MainActor (String, URL) -> Void) async -> (matches: [Match], failed: Bool) {
        let cal = Calendar.current
        let prev = cal.date(byAdding: .day, value: -1, to: day) ?? day
        // ESPN découpe les journées à l'heure de New York : on prend la veille aussi, puis on filtre.
        let range = "\(espnDay(prev))-\(espnDay(day))"
        var out: [Match] = []
        var failures = 0
        await withTaskGroup(of: (Competition, ScoreboardResponse?).self) { g in
            for c in competitions {
                g.addTask { (c, try? await scoreboard(c.id, dates: range)) }
            }
            for await (c, r) in g {
                guard let r else { failures += 1; continue }
                if let l = r.leagues.first?.logos.first?.href, let u = URL(string: l) { await onLogo(c.id, u) }
                out += r.events.compactMap { Match($0, league: c.id) }.filter { cal.isDate($0.date, inSameDayAs: day) }
            }
        }
        var seen = Set<String>()
        out = out.filter { seen.insert($0.id).inserted }
        return (out, failures == competitions.count && !competitions.isEmpty)
    }
}
