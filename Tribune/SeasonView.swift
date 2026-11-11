import SwiftUI

// MARK: - Saisons

extension Competition {
    /// Compétitions disputées en un seul été (une « saison » = une année).
    var isTournament: Bool { ["fifa.world", "uefa.euro", "conmebol.america", "caf.nations"].contains(id) }

    /// Saison en cours : 2026 = 2026/27 (à partir de juillet).
    static var currentSeason: Int {
        let c = Calendar.current.dateComponents([.year, .month], from: .now)
        return (c.month ?? 1) >= 7 ? (c.year ?? 2026) : (c.year ?? 2026) - 1
    }

    var seasons: [Int] {
        switch id {
        case "fifa.world": return [2026, 2022, 2018, 2014, 2010]
        case "uefa.euro": return [2024, 2021, 2016, 2012]
        case "conmebol.america": return [2024, 2021, 2019, 2016, 2015, 2011]
        case "caf.nations": return [2025, 2023, 2021, 2019, 2017, 2015, 2013]
        default: return Array(stride(from: Competition.currentSeason, through: 2010, by: -1))
        }
    }

    func seasonLabel(_ y: Int) -> String {
        isTournament ? String(y) : "\(y)/\(String(format: "%02d", (y + 1) % 100))"
    }
}

actor SeasonCache {
    static let shared = SeasonCache()
    private var events: [String: [ESPNEvent]] = [:]

    func events(_ league: String, year: Int) async -> [ESPNEvent]? {
        let key = "\(league)|\(year)"
        if let e = events[key] { return e }
        guard let r = try? await ESPN.scoreboard(league, dates: String(year)) else { return nil }
        events[key] = r.events
        return r.events
    }
}

extension ESPN {
    /// Tous les matchs d'une saison (ESPN accepte une année civile entière).
    static func season(_ c: Competition, year: Int) async -> [Match] {
        if SportsDB.covers(c.id) { return await SportsDB.season(c.id, year: year) }
        var evs: [ESPNEvent] = []
        if c.isTournament {
            evs = await SeasonCache.shared.events(c.id, year: year) ?? []
        } else {
            async let a = SeasonCache.shared.events(c.id, year: year)
            async let b = SeasonCache.shared.events(c.id, year: year + 1)
            let (ea, eb) = await (a, b)
            let all = (ea ?? []) + (eb ?? [])
            let tagged = all.filter { $0.seasonYear == year }
            if !tagged.isEmpty {
                evs = tagged
            } else {
                // Sans indication de saison : de juillet à juin.
                let cal = Calendar.current
                let start = cal.date(from: DateComponents(year: year, month: 7, day: 1)) ?? .distantPast
                let end = cal.date(from: DateComponents(year: year + 1, month: 7, day: 1)) ?? .distantFuture
                evs = all.filter { e in parseESPNDate(e.date).map { $0 >= start && $0 < end } ?? false }
            }
        }
        var seen = Set<String>()
        return evs.compactMap { Match($0, league: c.id, leagueName: c.name) }.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Phase finale

struct Tie: Identifiable {
    let id: String
    let a: Side
    let b: Side
    let aggA: Int
    let aggB: Int
    let legs: [Match]
    let winnerID: String?
    let finished: Bool
    let penalties: String?
}

struct Round: Identifiable {
    let id: String
    let name: String
    let order: Int
    let ties: [Tie]
}

enum Knockout {
    static func roundInfo(_ slug: String?) -> (String, Int)? {
        guard let s = slug?.lowercased() else { return nil }
        if s.contains("group") || s.contains("league") || s.contains("regular") || s.contains("qualifying") && !s.contains("playoff") { return nil }
        if s.contains("3rd") || s.contains("third") { return ("Petite finale", 6) }
        if s.contains("semi") { return ("Demi-finales", 5) }
        if s.contains("quarter") { return ("Quarts de finale", 4) }
        if s.contains("16") { return ("Huitièmes de finale", 3) }
        if s.contains("32") { return ("Seizièmes de finale", 2) }
        if s.contains("playoff") || s.contains("play-off") { return ("Barrages", 1) }
        if s == "final" || s.hasSuffix("-final") || s.contains("final") { return ("Finale", 7) }
        return nil
    }

    static func rounds(_ ms: [Match]) -> [Round] {
        var byRound: [String: (String, Int, [Match])] = [:]
        for m in ms {
            guard let info = roundInfo(m.round) else { continue }
            byRound[info.0, default: (info.0, info.1, [])].2.append(m)
        }
        return byRound.values.map { entry -> Round in
            let name = entry.0, order = entry.1, matches = entry.2
            var groups: [String: [Match]] = [:]
            var keys: [String] = []
            for m in matches.sorted(by: { $0.date < $1.date }) {
                let k = [m.home.id, m.away.id].sorted().joined(separator: "-")
                if groups[k] == nil { keys.append(k) }
                groups[k, default: []].append(m)
            }
            let ties: [Tie] = keys.map { k in
                let legs = groups[k]!
                let first = legs[0]
                let a = first.home, b = first.away
                var ga = 0, gb = 0
                var pens: String? = nil
                for l in legs where l.hasScore {
                    let hs = Int(l.home.score ?? "") ?? 0, as_ = Int(l.away.score ?? "") ?? 0
                    if l.home.id == a.id { ga += hs; gb += as_ } else { ga += as_; gb += hs }
                    if let ph = l.home.shootout, let pa = l.away.shootout { pens = l.home.id == a.id ? "\(ph)-\(pa)" : "\(pa)-\(ph)" }
                }
                let finished = legs.allSatisfy { $0.state == .post }
                var winner: String? = nil
                if finished {
                    if let last = legs.last, last.home.winner || last.away.winner { winner = last.home.winner ? last.home.id : last.away.id }
                    else if ga != gb { winner = ga > gb ? a.id : b.id }
                }
                // Logos à jour depuis le dernier match (les couleurs peuvent manquer sur le premier).
                return Tie(id: k, a: a, b: b, aggA: ga, aggB: gb, legs: legs, winnerID: winner, finished: finished, penalties: pens)
            }
            return Round(id: name, name: name, order: order, ties: ties)
        }
        .sorted { $0.order > $1.order }
    }
}

struct KnockoutView: View {
    let rounds: [Round]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let final = rounds.first(where: { $0.order == 7 })?.ties.first, let w = final.winnerID {
                let champ = w == final.a.id ? final.a : final.b
                ChampionCard(side: champ)
            }
            ForEach(rounds) { r in
                SectionTitle(text: r.name)
                LazyVGrid(columns: r.ties.count == 1 ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(r.ties) { t in TieCard(tie: t, isFinal: r.order == 7).floatIn() }
                }
            }
        }
    }
}

struct ChampionCard: View {
    let side: Side
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.4), Color(red: 0.85, green: 0.6, blue: 0.15)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .yellow.opacity(0.5), radius: 16)
                Logo(url: side.logo, size: 26).offset(y: -8)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("CHAMPION").font(.caption.weight(.heavy)).foregroundStyle(.secondary).tracking(1.5)
                Text(side.name).font(.title2.weight(.bold))
            }
            Spacer()
        }
        .padding(18)
        .glassSurface(cornerRadius: 28, wash: [side.tint, Color(red: 0.9, green: 0.7, blue: 0.2)], washOpacity: 0.45)
    }
}

struct TieCard: View {
    let tie: Tie
    let isFinal: Bool

    var body: some View {
        let lead = tie.legs.last
        VStack(spacing: 8) {
            row(tie.a, goals: tie.aggA, won: tie.winnerID == tie.a.id, lost: tie.winnerID == tie.b.id)
            row(tie.b, goals: tie.aggB, won: tie.winnerID == tie.b.id, lost: tie.winnerID == tie.a.id)
            HStack(spacing: 4) {
                if tie.legs.count > 1 { Text("\(tie.legs.count) matchs").font(.caption2) }
                else if let l = lead, !l.hasScore { Text(l.date.formatted(.dateTime.day().month(.abbreviated).locale(fr))).font(.caption2) }
                if let p = tie.penalties { Text("· tab \(p)").font(.caption2.monospacedDigit()) }
                Spacer(minLength: 0)
                if isFinal { Text("FINALE").font(.system(size: 9, weight: .heavy)).foregroundStyle(.black).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.yellow.opacity(0.85))) }
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassSurface(cornerRadius: 20, wash: [tie.a.tint, tie.b.tint], washOpacity: 0.22)
        .overlay {
            if let l = lead {
                NavigationLink(value: Route.match(l)) { Color.clear }.buttonStyle(.plain)
            }
        }
    }

    private func row(_ s: Side, goals: Int, won: Bool, lost: Bool) -> some View {
        HStack(spacing: 8) {
            Logo(url: s.logo, size: 22)
            Text(s.abbr.isEmpty ? s.short : s.abbr)
                .font(.subheadline.weight(won ? .bold : .medium))
                .strikethrough(lost, color: .secondary)
                .foregroundStyle(lost ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if tie.legs.contains(where: \.hasScore) {
                Text("\(goals)").font(.headline.monospacedDigit()).foregroundStyle(lost ? Color.secondary : Color.primary)
            }
        }
    }
}

// MARK: - Meilleurs joueurs (buteurs, passeurs…)

struct Leader: Identifiable {
    let id = UUID()
    let name: String
    let teamID: String?
    let value: String
    var detail: String? = nil
    var teamLogo: URL? { teamID.flatMap { URL(string: "https://a.espncdn.com/i/teamlogos/soccer/500/\($0).png") } }
}

struct LeaderCategory: Identifiable {
    let id = UUID()
    let title: String
    let leaders: [Leader]
}

actor RefCache {
    static let shared = RefCache()
    private var names: [String: String] = [:]
    func name(_ ref: String) async -> String? {
        if let n = names[ref] { return n }
        let https = ref.replacingOccurrences(of: "http://", with: "https://")
        guard let d = await PlayerAPI.json(https) as? [String: Any] else { return nil }
        let n = (d["displayName"] as? String) ?? (d["shortName"] as? String) ?? (d["fullName"] as? String)
        names[ref] = n
        return n
    }
}

enum LeadersAPI {
    static func load(_ league: String, season: Int) async -> [LeaderCategory] {
        var root: [String: Any]? = nil
        for t in [1, 2, 3] {
            if let r = await PlayerAPI.json("https://sports.core.api.espn.com/v2/sports/soccer/leagues/\(league)/seasons/\(season)/types/\(t)/leaders?limit=10") as? [String: Any],
               let cats = r["categories"] as? [[String: Any]], !cats.isEmpty { root = r; break }
        }
        guard let cats = root?["categories"] as? [[String: Any]] else { return [] }
        var out: [LeaderCategory] = []
        for cat in cats.prefix(5) {
            let title = PlayerAPI.translate((cat["displayName"] as? String) ?? (cat["name"] as? String) ?? "")
            let raw = ((cat["leaders"] as? [[String: Any]]) ?? []).prefix(10)
            let leaders: [Leader] = await withTaskGroup(of: (Int, Leader?).self, returning: [Leader].self) { g in
                for (i, l) in raw.enumerated() {
                    g.addTask {
                        guard let ref = (l["athlete"] as? [String: Any])?["$ref"] as? String, let name = await RefCache.shared.name(ref) else { return (i, nil) }
                        let teamRef = (l["team"] as? [String: Any])?["$ref"] as? String
                        let teamID = teamRef.flatMap { r -> String? in
                            guard let range = r.range(of: "/teams/") else { return nil }
                            return String(r[range.upperBound...].prefix { $0.isNumber })
                        }
                        // « Matches: 35, Goals: 27 » → valeur 27, détail « 35 matchs »
                        let display = (l["displayValue"] as? String) ?? ""
                        var v = (l["value"] as? Double).map { String(Int($0)) } ?? display
                        var detail: String? = nil
                        let parts = display.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        if parts.count > 1 {
                            if let last = parts.last?.split(separator: ":").last { v = last.trimmingCharacters(in: .whitespaces) }
                            if let m = parts.first(where: { $0.lowercased().hasPrefix("match") })?.split(separator: ":").last {
                                detail = "\(m.trimmingCharacters(in: .whitespaces)) matchs"
                            }
                        }
                        return (i, Leader(name: name, teamID: teamID, value: v, detail: detail))
                    }
                }
                var res: [(Int, Leader)] = []
                for await (i, l) in g { if let l { res.append((i, l)) } }
                return res.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
            if !leaders.isEmpty { out.append(LeaderCategory(title: title.isEmpty ? "Classement" : title, leaders: leaders)) }
        }
        return out
    }
}

struct LeadersView: View {
    let categories: [LeaderCategory]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(categories) { cat in
                SectionTitle(text: cat.title)
                VStack(spacing: 0) {
                    ForEach(Array(cat.leaders.enumerated()), id: \.element.id) { i, l in
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(i == 0 ? tint : Color.secondary).frame(width: 22)
                            Logo(url: l.teamLogo, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(l.name).font(.body.weight(i == 0 ? .bold : .medium)).lineLimit(1)
                                if let d = l.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(l.value)
                                .font(.headline.monospacedDigit())
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background { if i == 0 { Capsule().fill(tint.opacity(0.35)) } }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        if i < cat.leaders.count - 1 { Divider().padding(.leading, 74).opacity(0.5) }
                    }
                }
                .padding(.vertical, 4)
                .glassSurface(cornerRadius: 24, wash: [tint], washOpacity: 0.12)
            }
        }
    }
}
