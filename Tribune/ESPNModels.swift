import Foundation

// MARK: - Décodage tolérant
// L'API d'ESPN n'est pas documentée : chaque champ est optionnel et les types
// incertains sont décodés de façon souple pour qu'un champ inattendu ne casse rien.

struct Skip: Decodable { init(from decoder: Decoder) throws {} }

/// Tableau qui ignore les éléments impossibles à décoder au lieu d'échouer.
struct Lossy<T: Decodable>: Decodable {
    var items: [T]
    init(items: [T] = []) { self.items = items }
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [T] = []
        while !c.isAtEnd {
            if let v = try? c.decode(T.self) { out.append(v) } else { _ = try? c.decode(Skip.self) }
        }
        items = out
    }
}

extension KeyedDecodingContainer {
    func str(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) {
            return d == d.rounded() ? String(Int(d)) : String(d)
        }
        return nil
    }
    func bool(_ key: Key) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s == "true" || s == "1" }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        return nil
    }
    func dbl(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
    func obj<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
    func list<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        ((try? decodeIfPresent(Lossy<T>.self, forKey: key)) ?? nil)?.items ?? []
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

typealias KC = KeyedDecodingContainer<AnyKey>
extension KeyedDecodingContainer where K == AnyKey {
    subscript(_ s: String) -> AnyKey { AnyKey(s) }
}

// MARK: - Objets de base

struct ESPNLogo: Decodable {
    let href: String?
    let rel: [String]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self); href = c.str(c["href"])
        rel = ((try? c.decodeIfPresent([String].self, forKey: c["rel"])) ?? nil) ?? []
    }
}

struct ESPNLeague: Decodable {
    let id: String?
    let name: String?
    let abbreviation: String?
    let slug: String?
    let logos: [ESPNLogo]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        id = c.str(c["id"]); name = c.str(c["name"]); abbreviation = c.str(c["abbreviation"])
        slug = c.str(c["slug"]); logos = c.list(ESPNLogo.self, c["logos"])
    }
    var lightLogo: URL? { (logos.first { !$0.rel.contains("dark") } ?? logos.first)?.href.flatMap { URL(string: $0) } }
    var darkLogo: URL? { logos.first { $0.rel.contains("dark") }?.href.flatMap { URL(string: $0) } }
}

struct ESPNTeam: Decodable {
    let id: String?
    let displayName: String?
    let shortDisplayName: String?
    let name: String?
    let abbreviation: String?
    let logo: String?
    let logos: [ESPNLogo]
    let color: String?
    let alternateColor: String?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        id = c.str(c["id"]); displayName = c.str(c["displayName"]); shortDisplayName = c.str(c["shortDisplayName"])
        name = c.str(c["name"]); abbreviation = c.str(c["abbreviation"]); logo = c.str(c["logo"])
        logos = c.list(ESPNLogo.self, c["logos"]); color = c.str(c["color"]); alternateColor = c.str(c["alternateColor"])
    }

    var logoURL: URL? {
        if let l = logo, let u = URL(string: l) { return u }
        if let l = logos.first?.href, let u = URL(string: l) { return u }
        if let id { return URL(string: "https://a.espncdn.com/i/teamlogos/soccer/500/\(id).png") }
        return nil
    }
}

struct ESPNStatusType: Decodable {
    let name: String?
    let state: String?
    let completed: Bool?
    let description: String?
    let shortDetail: String?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        name = c.str(c["name"]); state = c.str(c["state"]); completed = c.bool(c["completed"])
        description = c.str(c["description"]); shortDetail = c.str(c["shortDetail"])
    }
}

struct ESPNStatus: Decodable {
    let displayClock: String?
    let period: Int?
    let type: ESPNStatusType?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        displayClock = c.str(c["displayClock"])
        period = c.str(c["period"]).flatMap { Int($0) }
        type = c.obj(ESPNStatusType.self, c["type"])
    }
}

struct ESPNCompetitor: Decodable {
    let id: String?
    let homeAway: String?
    let score: String?
    let shootout: String?
    let winner: Bool?
    let team: ESPNTeam?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        id = c.str(c["id"]); homeAway = c.str(c["homeAway"]); winner = c.bool(c["winner"])
        team = c.obj(ESPNTeam.self, c["team"])
        // Le score est une chaîne sur le tableau des scores, un objet sur le calendrier d'une équipe.
        if let s = c.str(c["score"]) {
            score = s
        } else if let o = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["score"]) {
            score = o.str(o["displayValue"]) ?? o.str(o["value"])
        } else { score = nil }
        if let s = c.str(c["shootoutScore"]) { shootout = s } else { shootout = nil }
    }
}

struct ESPNVenue: Decodable {
    let fullName: String?
    let city: String?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        fullName = c.str(c["fullName"])
        if let a = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["address"]) { city = a.str(a["city"]) } else { city = nil }
    }
}

struct ESPNCompetition: Decodable {
    let date: String?
    let competitors: [ESPNCompetitor]
    let status: ESPNStatus?
    let venue: ESPNVenue?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        date = c.str(c["date"]); competitors = c.list(ESPNCompetitor.self, c["competitors"])
        status = c.obj(ESPNStatus.self, c["status"]); venue = c.obj(ESPNVenue.self, c["venue"])
    }
}

struct ESPNEvent: Decodable {
    let id: String
    let date: String?
    let status: ESPNStatus?
    let competitions: [ESPNCompetition]
    let league: ESPNLeague?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        guard let id = c.str(c["id"]) else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "id")) }
        self.id = id
        date = c.str(c["date"]); status = c.obj(ESPNStatus.self, c["status"])
        competitions = c.list(ESPNCompetition.self, c["competitions"])
        league = c.obj(ESPNLeague.self, c["league"])
    }
}

struct ScoreboardResponse: Decodable {
    let events: [ESPNEvent]
    let leagues: [ESPNLeague]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        events = c.list(ESPNEvent.self, c["events"]); leagues = c.list(ESPNLeague.self, c["leagues"])
    }
}

struct ScheduleResponse: Decodable {
    let events: [ESPNEvent]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        events = c.list(ESPNEvent.self, c["events"])
    }
}

// MARK: - Fiche de match (summary)

struct ESPNAthlete: Decodable {
    let id: String?
    let displayName: String?
    let shortName: String?
    let lastName: String?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        id = c.str(c["id"]); displayName = c.str(c["displayName"]); shortName = c.str(c["shortName"]); lastName = c.str(c["lastName"])
    }
}

struct KeyEvent: Decodable, Identifiable {
    let id: String
    let typeText: String
    let typeCode: String
    let text: String?
    let period: Int?
    let clockValue: Double?
    let clockDisplay: String?
    let teamID: String?
    let scoringPlay: Bool
    let athletes: [ESPNAthlete]

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        id = c.str(c["id"]) ?? UUID().uuidString
        if let t = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["type"]) {
            typeText = t.str(t["text"]) ?? ""; typeCode = t.str(t["type"]) ?? ""
        } else { typeText = ""; typeCode = "" }
        text = c.str(c["text"])
        if let p = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["period"]) { period = p.str(p["number"]).flatMap { Int($0) } } else { period = nil }
        if let k = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["clock"]) {
            clockValue = k.dbl(k["value"]); clockDisplay = k.str(k["displayValue"])
        } else { clockValue = nil; clockDisplay = nil }
        if let t = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["team"]) { teamID = t.str(t["id"]) } else { teamID = nil }
        scoringPlay = c.bool(c["scoringPlay"]) ?? false
        struct P: Decodable { let athlete: ESPNAthlete? }
        athletes = c.list(P.self, c["participants"]).compactMap { $0.athlete }
    }

    var kind: EventKind {
        let t = (typeCode + " " + typeText).lowercased()
        if scoringPlay || t.contains("goal") { return t.contains("own") ? .ownGoal : (t.contains("penalty") ? .penaltyGoal : .goal) }
        if t.contains("yellow") && t.contains("red") { return .secondYellow }
        if t.contains("red") { return .red }
        if t.contains("yellow") { return .yellow }
        if t.contains("substitution") { return .sub }
        if t.contains("halftime") || t.contains("half time") { return .halftime }
        if t.contains("penalty") && (t.contains("miss") || t.contains("saved")) { return .penaltyMissed }
        if t.contains("var") { return .var }
        return .other
    }
}

enum EventKind { case goal, penaltyGoal, ownGoal, penaltyMissed, yellow, secondYellow, red, sub, halftime, `var`, other
    var isGoal: Bool { self == .goal || self == .penaltyGoal || self == .ownGoal }
}

struct RosterPlayer: Decodable, Identifiable {
    let id: String
    let starter: Bool
    let jersey: String?
    let athlete: ESPNAthlete?
    let position: String?
    let formationPlace: Int?
    let subbedIn: Bool
    let subbedOut: Bool
    let positionName: String?
    let stats: [PlayerStat]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        stats = c.list(PlayerStat.self, c["stats"])
        if let p = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["position"]) { positionName = p.str(p["displayName"]) ?? p.str(p["name"]) } else { positionName = nil }
        starter = c.bool(c["starter"]) ?? false
        jersey = c.str(c["jersey"])
        athlete = c.obj(ESPNAthlete.self, c["athlete"])
        id = athlete?.id ?? UUID().uuidString
        if let p = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["position"]) { position = p.str(p["abbreviation"]) } else { position = nil }
        formationPlace = c.str(c["formationPlace"]).flatMap { Int($0) }
        subbedIn = c.bool(c["subbedIn"]) ?? ((try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["subbedIn"])) != nil)
        subbedOut = c.bool(c["subbedOut"]) ?? ((try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["subbedOut"])) != nil)
    }
    var name: String {
        if let l = athlete?.lastName, !l.isEmpty { return l }
        return athlete?.displayName?.split(separator: " ").last.map(String.init) ?? "—"
    }
}

struct PlayerStat: Decodable {
    let name: String
    let displayValue: String?
    let value: Double?
    let label: String?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        guard let n = c.str(c["name"]) else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "name")) }
        name = n; displayValue = c.str(c["displayValue"]); value = c.dbl(c["value"])
        label = c.str(c["shortDisplayName"]) ?? c.str(c["displayName"]) ?? c.str(c["abbreviation"])
    }
}

struct Roster: Decodable {
    let homeAway: String?
    let formation: String?
    let team: ESPNTeam?
    let players: [RosterPlayer]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        homeAway = c.str(c["homeAway"]); formation = c.str(c["formation"])
        team = c.obj(ESPNTeam.self, c["team"]); players = c.list(RosterPlayer.self, c["roster"])
    }
}

struct BoxStat: Decodable {
    let name: String
    let displayValue: String?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        guard let n = c.str(c["name"]) else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "name")) }
        name = n; displayValue = c.str(c["displayValue"])
    }
}

struct BoxTeam: Decodable {
    let team: ESPNTeam?
    let homeAway: String?
    let statistics: [BoxStat]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        team = c.obj(ESPNTeam.self, c["team"]); homeAway = c.str(c["homeAway"])
        statistics = c.list(BoxStat.self, c["statistics"])
    }
}

struct SummaryResponse: Decodable {
    let event: ESPNEvent?
    let leagueName: String?
    let keyEvents: [KeyEvent]
    let rosters: [Roster]
    let boxTeams: [BoxTeam]
    let venue: ESPNVenue?
    let attendance: Int?

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        event = c.obj(ESPNEvent.self, c["header"])
        if let h = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["header"]),
           let l = try? h.nestedContainer(keyedBy: AnyKey.self, forKey: h["league"]) { leagueName = l.str(l["name"]) } else { leagueName = nil }
        keyEvents = c.list(KeyEvent.self, c["keyEvents"])
        rosters = c.list(Roster.self, c["rosters"])
        if let b = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["boxscore"]) { boxTeams = b.list(BoxTeam.self, b["teams"]) } else { boxTeams = [] }
        if let g = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["gameInfo"]) {
            venue = g.obj(ESPNVenue.self, g["venue"]); attendance = g.str(g["attendance"]).flatMap { Int($0) }
        } else { venue = nil; attendance = nil }
    }
}

// MARK: - Classements

struct StandingStat: Decodable {
    let name: String?
    let value: Double?
    let displayValue: String?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        name = c.str(c["name"]); value = c.dbl(c["value"]); displayValue = c.str(c["displayValue"])
    }
}

struct StandingEntry: Decodable {
    let team: ESPNTeam?
    let stats: [StandingStat]
    let noteColor: String?
    let noteText: String?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        team = c.obj(ESPNTeam.self, c["team"]); stats = c.list(StandingStat.self, c["stats"])
        if let n = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["note"]) {
            noteColor = n.str(n["color"]); noteText = n.str(n["description"])
        } else { noteColor = nil; noteText = nil }
    }
    func stat(_ n: String) -> Double? { stats.first { $0.name == n }?.value }
}

struct StandingsGroupDTO: Decodable {
    let name: String?
    let entries: [StandingEntry]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        name = c.str(c["name"])
        if let s = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: c["standings"]) { entries = s.list(StandingEntry.self, s["entries"]) } else { entries = [] }
    }
}

struct StandingsResponse: Decodable {
    let groups: [StandingsGroupDTO]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        let kids = c.list(StandingsGroupDTO.self, c["children"])
        if !kids.isEmpty { groups = kids }
        else if let me = try? StandingsGroupDTO(from: d), !me.entries.isEmpty { groups = [me] }
        else { groups = [] }
    }
}

// MARK: - Équipes d'une compétition

struct TeamsResponse: Decodable {
    let teams: [ESPNTeam]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        struct Sport: Decodable { let leagues: [L]? }
        struct L: Decodable { let teams: Lossy<W>? }
        struct W: Decodable { let team: ESPNTeam? }
        let sports = (try? c.decodeIfPresent([Sport].self, forKey: c["sports"])) ?? nil
        teams = sports?.first?.leagues?.first?.teams?.items.compactMap { $0.team } ?? []
    }
}
