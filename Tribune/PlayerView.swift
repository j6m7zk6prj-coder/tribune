import SwiftUI

// MARK: - Données d'un joueur (bio + saison), lues de façon générique

struct PlayerBio {
    var fullName: String?
    var age: String?
    var birth: String?
    var nationality: String?
    var height: String?
    var weight: String?
    var position: String?
    var jersey: String?
    var team: String?
    var headshot: URL?
    var flag: URL?
}

struct StatGroup: Identifiable {
    let id = UUID()
    let title: String
    let items: [(String, String)]
}

enum PlayerAPI {
    static let base = "https://site.web.api.espn.com/apis/common/v3/sports/soccer"

    static func json(_ s: String) async -> Any? {
        guard let u = URL(string: s) else { return nil }
        var req = URLRequest(url: u); req.timeoutInterval = 15
        guard let r = try? await URLSession.shared.data(for: req),
              (r.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: r.0)
    }

    static func bio(league: String, id: String) async -> PlayerBio? {
        let root = await json("\(base)/\(league)/athletes/\(id)") as? [String: Any]
        guard let a = (root?["athlete"] as? [String: Any]) ?? root else { return nil }
        func s(_ k: String) -> String? {
            if let v = a[k] as? String, !v.isEmpty { return v }
            if let v = a[k] as? Int { return String(v) }
            if let v = a[k] as? Double { return String(Int(v)) }
            return nil
        }
        func nested(_ k: String, _ sub: String) -> String? { (a[k] as? [String: Any])?[sub] as? String }
        var b = PlayerBio()
        b.fullName = s("fullName") ?? s("displayName")
        b.age = s("age")
        if let dob = s("dateOfBirth"), let d = parseESPNDate(dob) ?? ISO8601DateFormatter().date(from: dob) {
            b.birth = d.formatted(.dateTime.day().month(.wide).year().locale(fr))
        } else { b.birth = s("displayDOB") }
        b.nationality = s("citizenship") ?? nested("citizenshipCountry", "name") ?? nested("birthPlace", "country")
        b.height = s("displayHeight")
        b.weight = s("displayWeight")
        b.position = nested("position", "displayName")
        b.jersey = s("jersey") ?? s("displayJersey")
        b.team = nested("team", "displayName")
        b.headshot = nested("headshot", "href").flatMap { URL(string: $0) }
        b.flag = nested("flag", "href").flatMap { URL(string: $0) }
        return b
    }

    /// Cherche dans la réponse toutes les catégories « libellés + totaux ».
    static func season(league: String, id: String) async -> [StatGroup] {
        guard let root = await json("\(base)/\(league)/athletes/\(id)/stats") else { return [] }
        var groups: [StatGroup] = []
        func walk(_ x: Any) {
            if let d = x as? [String: Any] {
                let labels = (d["displayNames"] as? [String]) ?? (d["labels"] as? [String])
                var values = (d["totals"] as? [Any])?.map { "\($0)" }
                if values == nil, let st = d["statistics"] as? [[String: Any]], let last = st.last, let v = last["stats"] as? [Any] {
                    values = v.map { "\($0)" }
                }
                if let labels, let values, labels.count == values.count, !labels.isEmpty {
                    let title = (d["displayName"] as? String) ?? (d["name"] as? String) ?? "Saison"
                    groups.append(StatGroup(title: translate(title), items: zip(labels, values).map { (translate($0), $1) }))
                    return
                }
                for v in d.values { walk(v) }
            } else if let arr = x as? [Any] {
                for v in arr { walk(v) }
            }
        }
        walk(root)
        return groups
    }

    static let frLabels: [String: String] = [
        "appearances": "Matchs", "starts": "Titularisations", "goals": "Buts", "assists": "Passes décisives",
        "shots": "Tirs", "shots on target": "Tirs cadrés", "fouls committed": "Fautes commises",
        "fouls suffered": "Fautes subies", "yellow cards": "Cartons jaunes", "red cards": "Cartons rouges",
        "offsides": "Hors-jeu", "saves": "Arrêts", "goals conceded": "Buts encaissés", "shots faced": "Tirs subis",
        "own goals": "Contre son camp", "sub appearances": "Entrées en jeu", "substitute appearances": "Entrées en jeu",
        "minutes": "Minutes", "clean sheet": "Clean sheets", "clean sheets": "Clean sheets", "general": "Général",
        "offensive": "Attaque", "defensive": "Défense", "goalkeeping": "Gardien", "total shots": "Tirs",
        "penalty kick goals": "Penaltys marqués", "penalty kick shots": "Penaltys tirés", "accurate passes": "Passes réussies",
        "total passes": "Passes", "passing accuracy": "Précision des passes", "tackles": "Tacles", "interceptions": "Interceptions",
        "clearances": "Dégagements", "blocked shots": "Tirs contrés", "crosses": "Centres", "dribbles": "Dribbles",
    ]
    static func translate(_ s: String) -> String { frLabels[s.lowercased()] ?? s }
}

// MARK: - Fiche joueur

struct PlayerSheet: View {
    let player: RosterPlayer
    let side: Side
    let opponent: Side
    let tint: Color
    let match: Match
    let marks: PlayerMarks

    @State private var bio: PlayerBio?
    @State private var season: [StatGroup] = []
    @State private var loadingMore = true
    @Environment(\.dismiss) private var dismiss

    /// Statistiques du match, dans un ordre lisible.
    static let matchKeys: [(String, String, String)] = [
        ("totalGoals", "Buts", "soccerball"),
        ("goalAssists", "Passes décisives", "shoe.fill"),
        ("totalShots", "Tirs", "scope"),
        ("shotsOnTarget", "Tirs cadrés", "target"),
        ("foulsCommitted", "Fautes commises", "hand.raised"),
        ("foulsSuffered", "Fautes subies", "figure.fall"),
        ("offsides", "Hors-jeu", "flag"),
        ("yellowCards", "Cartons jaunes", "rectangle.portrait.fill"),
        ("redCards", "Cartons rouges", "rectangle.portrait.fill"),
        ("saves", "Arrêts", "hand.raised.fill"),
        ("goalsConceded", "Buts encaissés", "xmark.shield"),
        ("shotsFaced", "Tirs subis", "shield.lefthalf.filled"),
        ("ownGoals", "Contre son camp", "arrow.uturn.backward"),
    ]

    private var pid: String { player.athlete?.id ?? "" }

    private var matchStats: [(String, String, String)] {
        var out: [(String, String, String)] = []
        var used = Set<String>()
        for key in Self.matchKeys {
            if let st = player.stats.first(where: { $0.name == key.0 }) {
                let v = st.displayValue ?? st.value.map { String(Int($0)) } ?? "0"
                out.append((key.1, v, key.2)); used.insert(key.0)
            }
        }
        // Repli si ESPN ne donne pas de statistiques : celles qu'on déduit du déroulé.
        if out.isEmpty {
            out.append(("Buts", "\(marks.goals[pid] ?? 0)", "soccerball"))
            out.append(("Passes décisives", "\(marks.assists[pid] ?? 0)", "shoe.fill"))
        }
        for s in player.stats where !used.contains(s.name) && !["appearances", "subIns"].contains(s.name) {
            out.append((PlayerAPI.translate(s.label ?? s.name), s.displayValue ?? "–", "chart.bar"))
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    momentsRow
                    grid(title: "Ce match", items: matchStats.map { t -> (String, String, String?) in (t.0, t.1, t.2) }, highlightNonZero: true)
                    bioGrid
                    ForEach(season.prefix(3)) { g in
                        grid(title: g.title, items: g.items.prefix(12).map { t -> (String, String, String?) in (t.0, t.1, nil) }, highlightNonZero: false)
                    }
                    if loadingMore { ProgressView().padding(.vertical, 20) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background { AmbientBackground(colors: [tint, tint.opacity(0.75), tint], intensity: 1.2) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Fermer")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .task {
            guard !pid.isEmpty else { loadingMore = false; return }
            async let b = PlayerAPI.bio(league: match.league, id: pid)
            async let s = PlayerAPI.season(league: match.league, id: pid)
            let (bb, ss) = await (b, s)
            withAnimation(.smooth(duration: 0.4)) { bio = bb; season = ss; loadingMore = false }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                if let h = bio?.headshot {
                    AsyncImage(url: h) { img in img.resizable().scaledToFill() } placeholder: { jersey }
                        .frame(width: 104, height: 104)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
                } else {
                    jersey
                }
            }
            .shadow(color: tint.opacity(0.8), radius: 26)
            .padding(.top, 6)

            Text(player.athlete?.displayName ?? player.name)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Logo(url: side.logo, size: 20)
                Text([bio?.position ?? player.positionName, side.short].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text("contre").foregroundStyle(.secondary)
                Logo(url: opponent.logo, size: 16)
                Text(opponent.short)
                if match.hasScore {
                    Text("·").foregroundStyle(.secondary)
                    Text("\(match.home.score ?? "0") – \(match.away.score ?? "0")").monospacedDigit()
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassSurface(cornerRadius: 16)
        }
        .frame(maxWidth: .infinity)
    }

    private var jersey: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [tint, tint.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            Text(player.jersey ?? "").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(.white)
        }
        .frame(width: 104, height: 104)
        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
    }

    @ViewBuilder private var momentsRow: some View {
        let ms = marks.moments[pid] ?? []
        if !ms.isEmpty || player.starter {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if player.starter { chip("Titulaire", icon: "person.fill.checkmark", minute: nil) }
                    ForEach(Array(ms.enumerated()), id: \.offset) { _, m in
                        chip(m.0, icon: icon(for: m.0), minute: m.1)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    private func icon(for label: String) -> String {
        switch label {
        case let l where l.hasPrefix("But"): return "soccerball"
        case "Passe décisive": return "shoe.fill"
        case "Carton jaune", "Carton rouge": return "rectangle.portrait.fill"
        case "Entré en jeu": return "arrow.up"
        case "Remplacé": return "arrow.down"
        default: return "circle"
        }
    }

    private func chip(_ text: String, icon: String, minute: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(text == "Carton jaune" ? Color.yellow : text == "Carton rouge" ? Color.red : text == "Remplacé" ? Color.red : Color.primary)
            Text(text).font(.footnote.weight(.semibold))
            if let minute, !minute.isEmpty { Text(minute).font(.footnote.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 18, tint: text.hasPrefix("But") || text == "Passe décisive" ? tint : nil)
    }

    @ViewBuilder private var bioGrid: some View {
        if let b = bio {
            let raw: [(String, String?, String)] = [
                ("Âge", b.age.map { "\($0) ans" }, "birthday.cake"),
                ("Nationalité", b.nationality, "flag"),
                ("Taille", b.height, "ruler"),
                ("Poids", b.weight, "scalemass"),
                ("Numéro", b.jersey ?? player.jersey, "tshirt"),
                ("Naissance", b.birth, "calendar"),
            ]
            let items: [(String, String, String?)] = raw.compactMap { t -> (String, String, String?)? in
                guard let v = t.1 else { return nil }
                return (t.0, v, t.2)
            }
            if !items.isEmpty { grid(title: "Profil", items: items, highlightNonZero: false) }
        }
    }

    private func grid(title: String, items: [(String, String, String?)], highlightNonZero: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.bold)).padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    let active = highlightNonZero && it.1 != "0" && it.1 != "–"
                    VStack(alignment: .leading, spacing: 6) {
                        if let icon = it.2 {
                            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(active ? tint : Color.secondary)
                        }
                        Text(it.1)
                            .font(.system(size: it.1.count > 6 ? 15 : 24, weight: .bold, design: .rounded).monospacedDigit())
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                        Text(it.0).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                    .padding(12)
                    .glassSurface(cornerRadius: 20, wash: active ? [tint, tint.opacity(0.3)] : [], washOpacity: 0.35)
                }
            }
        }
    }
}
