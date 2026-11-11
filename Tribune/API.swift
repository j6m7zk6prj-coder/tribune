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
        var s = "\(site)/\(league)/scoreboard"
        if let dates { s += "?dates=\(dates)" }
        return try await get(s)
    }

    static func summary(_ league: String, event: String) async throws -> SummaryResponse {
        try await get("\(site)/\(league)/summary?event=\(event)")
    }

    static func standings(_ league: String, season: Int? = nil) async throws -> StandingsResponse {
        try await get("\(core)/\(league)/standings" + (season.map { "?season=\($0)" } ?? ""))
    }

    static func teams(_ league: String) async throws -> [ESPNTeam] {
        let r: TeamsResponse = try await get("\(site)/\(league)/teams")
        return r.teams
    }

    /// Matchs passés et à venir d'une équipe.
    static func schedule(_ league: String, team: String) async -> [ESPNEvent] {
        async let past: ScheduleResponse? = try? ESPN.get("\(site)/\(league)/teams/\(team)/schedule")
        async let next: ScheduleResponse? = try? ESPN.get("\(site)/\(league)/teams/\(team)/schedule?fixture=true")
        let all = ((await past)?.events ?? []) + ((await next)?.events ?? [])
        var seen = Set<String>()
        return all.filter { seen.insert($0.id).inserted }
    }

    /// Compétitions où une équipe peut jouer : son championnat, les coupes d'Europe et sa coupe nationale.
    static func competitions(for t: TeamRef) -> [String] {
        let nations = Competition.named(t.league)?.group == .nations
        if nations { return ["uefa.nations", "fifa.friendly", "fifa.worldq.uefa", "fifa.world", "uefa.euro", "uefa.euroq"] }
        let cups: [String: [String]] = [
            "fra": ["fra.coupe_de_france"], "eng": ["eng.fa", "eng.league_cup"], "esp": ["esp.copa_del_rey"],
            "ita": ["ita.coppa_italia"], "ger": ["ger.dfb_pokal"],
        ]
        let country = String(t.league.prefix { $0 != "." })
        var out = [t.league]
        if Competition.named(t.league)?.group != .europe { out += ["uefa.champions", "uefa.europa", "uefa.europa.conf"] }
        out += cups[country] ?? []
        return out
    }

    /// Matchs d'une équipe dans toutes ses compétitions.
    static func teamMatches(_ t: TeamRef, upcomingOnly: Bool = false) async -> [Match] {
        let leagues = competitions(for: t)
        var out: [Match] = []
        await withTaskGroup(of: [Match].self) { g in
            for l in leagues {
                g.addTask {
                    let evs: [ESPNEvent]
                    if upcomingOnly {
                        evs = ((try? await ESPN.get("\(site)/\(l)/teams/\(t.id)/schedule?fixture=true") as ScheduleResponse)?.events) ?? []
                    } else {
                        evs = await ESPN.schedule(l, team: t.id)
                    }
                    return evs.compactMap { Match($0, league: l) }.filter { $0.home.id == t.id || $0.away.id == t.id }
                }
            }
            for await part in g { out += part }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }.sorted { $0.date < $1.date }
    }

    /// Matchs d'une compétition sur une période (ESPN refuse les plages : une requête par jour).
    static func range(_ league: String, from: Date, to: Date) async -> (events: [ESPNEvent], league: ESPNLeague?) {
        let cal = Calendar.current
        var days: [String] = []
        var d = cal.startOfDay(for: from)
        while d <= to { days.append(espnDay(d)); d = cal.date(byAdding: .day, value: 1, to: d) ?? to.addingTimeInterval(1) }
        var events: [ESPNEvent] = []
        var lg: ESPNLeague? = nil
        await withTaskGroup(of: ScoreboardResponse?.self) { g in
            var it = days.makeIterator()
            for _ in 0..<6 { if let day = it.next() { g.addTask { await DayCache.shared.scoreboard(league, day: day) } } }
            for await r in g {
                if let day = it.next() { g.addTask { await DayCache.shared.scoreboard(league, day: day) } }
                if let r { events += r.events; if lg == nil { lg = r.leagues.first } }
            }
        }
        return (events, lg)
    }

    /// Tous les matchs d'un jour (heure locale), pour les compétitions choisies.
    static func matches(on day: Date, competitions: [Competition], onLogo: @escaping @MainActor (String, ESPNLeague) -> Void) async -> (matches: [Match], failed: Bool) {
        let cal = Calendar.current
        let prev = cal.date(byAdding: .day, value: -1, to: day) ?? day
        // ESPN découpe les journées à l'heure de New York : on prend la veille aussi, puis on filtre.
        let days = [espnDay(prev), espnDay(day)]
        let jobs = competitions.flatMap { c in days.map { (c, $0) } }
        var out: [Match] = []
        var failures = 0
        await withTaskGroup(of: (Competition, ScoreboardResponse?).self) { g in
            var it = jobs.makeIterator()
            // 6 requêtes à la fois au maximum.
            for _ in 0..<6 { if let job = it.next() { g.addTask { (job.0, await DayCache.shared.scoreboard(job.0.id, day: job.1)) } } }
            for await (c, r) in g {
                if let job = it.next() { g.addTask { (job.0, await DayCache.shared.scoreboard(job.0.id, day: job.1)) } }
                guard let r else { failures += 1; continue }
                if let l = r.leagues.first { await onLogo(c.id, l) }
                out += r.events.compactMap { Match($0, league: c.id) }.filter { cal.isDate($0.date, inSameDayAs: day) }
            }
        }
        var seen = Set<String>()
        out = out.filter { seen.insert($0.id).inserted }
        return (out, failures == jobs.count && !jobs.isEmpty)
    }
}

/// Garde les tableaux de scores quelques instants pour ne pas refaire les mêmes requêtes
/// quand on glisse d'un jour à l'autre.
actor DayCache {
    static let shared = DayCache()
    private var store: [String: (Date, ScoreboardResponse)] = [:]
    @MainActor static var lastError: String = ""

    func scoreboard(_ league: String, day: String) async -> ScoreboardResponse? {
        let key = league + "|" + day
        let isPast = day < espnDay(Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
        let ttl: TimeInterval = isPast ? 600 : 25
        if let hit = store[key], Date().timeIntervalSince(hit.0) < ttl { return hit.1 }
        for attempt in 0..<2 {
            do {
                let r = try await ESPN.scoreboard(league, dates: day)
                store[key] = (Date(), r)
                return r
            } catch {
                await MainActor.run { DayCache.lastError = "\(league) \(day) : \(error.localizedDescription)" }
                if attempt == 0 { try? await Task.sleep(for: .milliseconds(400)) }
            }
        }
        return store[key]?.1
    }
}
