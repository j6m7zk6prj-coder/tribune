import SwiftUI

/// Informations en plus pour la fiche d'un match, lues de façon tolérante dans la réponse ESPN.
struct MatchExtras {
    struct Game: Identifiable {
        let id = UUID()
        let result: String?        // V / N / D (du point de vue de l'équipe)
        let score: String
        let opponent: String
        let opponentLogo: URL?
        let date: Date?
        let competition: String?
        let home: String?
        let away: String?
    }

    var formHome: [Game] = []
    var formAway: [Game] = []
    var h2h: [Game] = []
    var probHome: Double?
    var probDraw: Double?
    var probAway: Double?
    var referee: String?

    var isEmpty: Bool { formHome.isEmpty && formAway.isEmpty && h2h.isEmpty && probHome == nil && referee == nil }

    static func s(_ d: [String: Any]?, _ k: String) -> String? {
        guard let v = d?[k] else { return nil }
        if let s = v as? String, !s.isEmpty { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    static func game(_ e: [String: Any], h2hTeams: (String, String)? = nil) -> Game {
        let opp = e["opponent"] as? [String: Any]
        let oppLogo = s(opp, "logo") ?? ((opp?["logos"] as? [[String: Any]])?.first).flatMap { s($0, "href") }
        let res: String? = s(e, "gameResult").map { r in
            switch r.uppercased() { case "W": return "V"; case "L": return "D"; case "D", "T": return "N"; default: return r }
        }
        let score = s(e, "score") ?? [s(e, "homeTeamScore"), s(e, "awayTeamScore")].compactMap { $0 }.joined(separator: "-")
        let date = s(e, "gameDate").flatMap { parseESPNDate($0) ?? ISO8601DateFormatter().date(from: $0) }
        return Game(result: res, score: score, opponent: s(opp, "displayName") ?? s(opp, "shortDisplayName") ?? s(opp, "abbreviation") ?? "—",
                    opponentLogo: oppLogo.flatMap { URL(string: $0) }, date: date,
                    competition: s(e, "leagueName") ?? s(e, "leagueAbbreviation"),
                    home: s(e, "atVs"), away: nil)
    }

    static func load(_ match: Match) async -> MatchExtras {
        var x = MatchExtras()
        guard let root = await PlayerAPI.json("\(ESPN.site)/\(match.league)/summary?event=\(match.id)") as? [String: Any] else { return x }

        // Forme : boxscore.form[] { team.id, events[] }
        let formList = ((root["boxscore"] as? [String: Any])?["form"] as? [[String: Any]]) ?? (root["lastFiveGames"] as? [[String: Any]]) ?? []
        for f in formList {
            let tid = s(f["team"] as? [String: Any], "id")
            let games = ((f["events"] as? [[String: Any]]) ?? []).prefix(5).map { game($0) }
            if tid == match.home.id { x.formHome = Array(games) }
            else if tid == match.away.id { x.formAway = Array(games) }
        }

        // Face-à-face : headToHeadGames[] { team.id, events[] }, du point de vue de « team ».
        if let h = (root["headToHeadGames"] as? [[String: Any]])?.first {
            let tid = s(h["team"] as? [String: Any], "id")
            x.h2h = ((h["events"] as? [[String: Any]]) ?? []).prefix(6).map { e in
                var g = game(e)
                // On exprime le résultat du point de vue de l'équipe à domicile du match affiché.
                if tid != nil && tid != match.home.id, let r = g.result {
                    let flipped = r == "V" ? "D" : r == "D" ? "V" : r
                    g = Game(result: flipped, score: g.score, opponent: g.opponent, opponentLogo: g.opponentLogo, date: g.date, competition: g.competition, home: g.home, away: g.away)
                }
                return g
            }
        }

        // Probabilités : predictor { homeTeam.gameProjection, awayTeam.gameProjection, … }
        if let p = root["predictor"] as? [String: Any] {
            let h = Double(s(p["homeTeam"] as? [String: Any], "gameProjection") ?? "")
            let a = Double(s(p["awayTeam"] as? [String: Any], "gameProjection") ?? "")
            let d = Double(s(p["homeTeam"] as? [String: Any], "teamChanceTie") ?? s(p, "tieProjection") ?? "")
            if let h, let a, h + a > 0 {
                x.probHome = h; x.probAway = a
                x.probDraw = d ?? max(0, 100 - h - a)
            }
        }

        // Arbitre : gameInfo.officials[]
        if let offs = (root["gameInfo"] as? [String: Any])?["officials"] as? [[String: Any]] {
            let ref = offs.first { (s($0["position"] as? [String: Any], "name") ?? s($0["position"] as? [String: Any], "displayName") ?? "").lowercased().contains("referee") } ?? offs.first
            x.referee = s(ref, "displayName") ?? s(ref, "fullName")
        }
        return x
    }
}

// MARK: - Vues

struct ProbabilityCard: View {
    let x: MatchExtras
    let match: Match
    let colors: (Color, Color)
    @State private var shown = false

    var body: some View {
        if let h = x.probHome, let a = x.probAway {
            let d = x.probDraw ?? 0
            let total = max(h + a + d, 1)
            VStack(alignment: .leading, spacing: 12) {
                Text("Probabilités").font(.headline)
                GeometryReader { g in
                    HStack(spacing: 3) {
                        Capsule().fill(colors.0.gradient).frame(width: shown ? max(g.size.width * h / total - 3, 6) : g.size.width / 3)
                        Capsule().fill(Color.gray.opacity(0.55)).frame(width: shown ? max(g.size.width * d / total - 3, 6) : g.size.width / 3)
                        Capsule().fill(colors.1.gradient)
                    }
                }
                .frame(height: 12)
                HStack {
                    pct(match.home.short, h, colors.0, .leading)
                    Spacer()
                    pct("Nul", d, .gray, .center)
                    Spacer()
                    pct(match.away.short, a, colors.1, .trailing)
                }
            }
            .padding(16)
            .glassSurface(cornerRadius: 22)
            .onAppear { withAnimation(.smooth(duration: 0.9).delay(0.1)) { shown = true } }
        }
    }

    private func pct(_ label: String, _ v: Double, _ c: Color, _ al: HorizontalAlignment) -> some View {
        VStack(alignment: al, spacing: 2) {
            Text("\(Int(v.rounded())) %").font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(c == .gray ? Color.primary : c)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct FormCard: View {
    let match: Match
    let x: MatchExtras

    var body: some View {
        if !x.formHome.isEmpty || !x.formAway.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Forme récente").font(.headline)
                line(match.home, x.formHome)
                line(match.away, x.formAway)
            }
            .padding(16)
            .glassSurface(cornerRadius: 22)
        }
    }

    private func line(_ side: Side, _ games: [MatchExtras.Game]) -> some View {
        HStack(spacing: 10) {
            Logo(url: side.logo, size: 26)
            Text(side.short).font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                ForEach(Array(games.reversed())) { g in
                    VStack(spacing: 3) {
                        Text(g.result ?? "–")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(color(g.result).gradient))
                            .shadow(color: color(g.result).opacity(0.5), radius: 4)
                        Logo(url: g.opponentLogo, size: 14)
                    }
                }
            }
        }
    }

    private func color(_ r: String?) -> Color {
        switch r { case "V": return .brand; case "D": return Color(.systemRed); default: return Color(.systemGray) }
    }
}

struct HeadToHeadCard: View {
    let match: Match
    let x: MatchExtras

    var body: some View {
        if !x.h2h.isEmpty {
            let w = x.h2h.filter { $0.result == "V" }.count
            let l = x.h2h.filter { $0.result == "D" }.count
            let d = x.h2h.count - w - l
            VStack(alignment: .leading, spacing: 12) {
                Text("Face-à-face").font(.headline)
                HStack {
                    tally(match.home, w)
                    Spacer()
                    VStack(spacing: 2) {
                        Text("\(d)").font(.title2.weight(.bold).monospacedDigit())
                        Text("Nuls").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    tally(match.away, l)
                }
                Divider().opacity(0.5)
                ForEach(x.h2h) { g in
                    HStack(spacing: 8) {
                        Text(g.date.map { $0.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits).locale(fr)) } ?? "")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
                        Logo(url: g.opponentLogo, size: 18)
                        Text(g.opponent).font(.subheadline).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(g.score).font(.subheadline.weight(.bold).monospacedDigit())
                        if let r = g.result {
                            Text(r).font(.caption2.weight(.heavy)).foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(r == "V" ? Color.brand : r == "D" ? Color(.systemRed) : Color(.systemGray)))
                        }
                    }
                }
                Text("Résultats du point de vue de \(match.home.short).").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(16)
            .glassSurface(cornerRadius: 22)
        }
    }

    private func tally(_ s: Side, _ n: Int) -> some View {
        HStack(spacing: 8) {
            Logo(url: s.logo, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(n)").font(.title2.weight(.bold).monospacedDigit())
                Text("Victoires").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
