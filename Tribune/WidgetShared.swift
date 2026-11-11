import WidgetKit
import SwiftUI
import AppIntents

// Vues et données des widgets, partagées entre l'app (aperçu) et l'extension.

extension View {
    @ViewBuilder func widgetBackground<B: View>(_ b: B, inApp: Bool) -> some View {
        if inApp {
            self.padding(16).background(b).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            self.containerBackground(for: .widget) { b }
        }
    }
}

// MARK: - Données communes

struct WMatch: Identifiable {
    let match: Match
    let homeImg: UIImage?
    let awayImg: UIImage?
    var leagueImg: UIImage? = nil
    var leagueLight: Bool = true
    var id: String { match.id }
}

enum WidgetData {
    static func image(_ url: URL?, size: CGFloat = 90) async -> UIImage? {
        guard let url, let r = try? await URLSession.shared.data(from: url), let img = UIImage(data: r.0) else { return nil }
        return img.preparingThumbnail(of: CGSize(width: size, height: size)) ?? img
    }

    static var shared: UserDefaults { UserDefaults(suiteName: LeagueBadges.group) ?? .standard }

    /// Équipes suivies dans l'app (espace partagé), sinon celles de l'app elle-même (aperçu).
    static func followed() -> [TeamRef] {
        for d in [shared, UserDefaults.standard] {
            if let data = d.data(forKey: "favorites"), let f = try? JSONDecoder().decode([TeamRef].self, from: data), !f.isEmpty { return f }
        }
        return []
    }

    static func leagueLogoURL(_ slug: String) async -> URL? {
        for d in [shared, UserDefaults.standard] {
            if let logos = d.dictionary(forKey: "leagueLogos") as? [String: String],
               let s = logos[slug + "#badge"] ?? logos[slug], let u = URL(string: s) { return u }
        }
        if let id = LeagueBadges.ids[slug] { return await LeagueBadges.lookup(id)?.badge }
        return nil
    }

    static func leagueImage(_ slug: String) async -> UIImage? {
        await image(await leagueLogoURL(slug), size: 60)
    }

    static func withImages(_ ms: [Match]) async -> [WMatch] {
        await withTaskGroup(of: (Int, UIImage?, UIImage?, UIImage?).self, returning: [WMatch].self) { g in
            for (i, m) in ms.enumerated() {
                g.addTask {
                    async let h = WidgetData.image(m.home.logo)
                    async let a = WidgetData.image(m.away.logo)
                    async let l = WidgetData.leagueImage(m.league)
                    return (i, await h, await a, await l)
                }
            }
            var imgs: [Int: (UIImage?, UIImage?, UIImage?)] = [:]
            for await (i, h, a, l) in g { imgs[i] = (h, a, l) }
            return ms.enumerated().map { (i, m) -> WMatch in
                let li = imgs[i]?.2
                return WMatch(match: m, homeImg: imgs[i]?.0, awayImg: imgs[i]?.1, leagueImg: li, leagueLight: li.map { BadgeLoader.isLight($0) } ?? true)
            }
        }
    }
}

// MARK: - Widget « Mes équipes » : prochain match de chaque équipe suivie

struct FollowedIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Mes équipes"
    static var description = IntentDescription("Jusqu’à 5 équipes. Laisse vide pour reprendre les équipes suivies dans Tribune.")
    @Parameter(title: "Équipes") var teams: [TeamEntity]?
}

struct MatchesEntry: TimelineEntry {
    let date: Date
    let matches: [WMatch]
    var followed: Set<String> = []
    var message: String? = nil
}

struct MatchesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MatchesEntry { MatchesEntry(date: .now, matches: []) }

    func snapshot(for configuration: FollowedIntent, in context: Context) async -> MatchesEntry {
        await load(teams: teams(configuration), limit: limit(context.family))
    }

    func timeline(for configuration: FollowedIntent, in context: Context) async -> Timeline<MatchesEntry> {
        let e = await load(teams: teams(configuration), limit: limit(context.family))
        let live = e.matches.contains { $0.match.state == .live }
        let soon = e.matches.contains { $0.match.date.timeIntervalSinceNow < 3 * 3600 }
        return Timeline(entries: [e], policy: .after(.now.addingTimeInterval(live ? 300 : soon ? 900 : 3600)))
    }

    func teams(_ c: FollowedIntent) -> [TeamRef] {
        let picked = (c.teams ?? []).map { TeamRef(id: $0.teamID, name: $0.name, league: $0.league, logo: nil, color: $0.color) }
        return picked.isEmpty ? WidgetData.followed() : picked
    }

    func limit(_ f: WidgetFamily) -> Int {
        switch f { case .systemSmall: 1; case .systemMedium: 2; default: 5 }
    }

    func load(teams: [TeamRef], limit: Int) async -> MatchesEntry {
        guard !teams.isEmpty else {
            return MatchesEntry(date: .now, matches: [], message: "Suis des équipes dans Tribune, ou choisis-les en modifiant le widget.")
        }
        let ids = Set(teams.map(\.id))
        var nexts: [Match] = []
        await withTaskGroup(of: Match?.self) { g in
            for t in teams.prefix(5) {
                g.addTask {
                    let ms = await ESPN.teamMatches(t, upcomingOnly: true)
                    return ms.first { $0.state == .live } ?? ms.first { $0.state == .pre && $0.date > .now.addingTimeInterval(-3 * 3600) }
                }
            }
            for await m in g { if let m { nexts.append(m) } }
        }
        var seen = Set<String>()
        let ordered = nexts.filter { seen.insert($0.id).inserted }
            .sorted { ($0.state == .live ? 0 : 1, $0.date) < ($1.state == .live ? 0 : 1, $1.date) }
        let picked = Array(ordered.prefix(limit))
        return MatchesEntry(date: .now, matches: await WidgetData.withImages(picked), followed: ids,
                            message: picked.isEmpty ? "Aucun match prévu pour tes équipes." : nil)
    }
}

struct MatchesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TribuneFollowed", intent: FollowedIntent.self, provider: MatchesProvider()) { entry in
            MatchesWidgetView(entry: entry)
        }
        .configurationDisplayName("Mes équipes")
        .description("Le prochain match de chacune de tes équipes suivies.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

func shortDay(_ d: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(d) { return "" }
    if cal.isDateInTomorrow(d) { return "Demain" }
    if let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: d)).day, days < 7 {
        return d.formatted(.dateTime.weekday(.abbreviated).locale(fr))
    }
    return d.formatted(.dateTime.day().month(.abbreviated).locale(fr))
}

/// Heure du match, précédée du jour s'il n'est pas aujourd'hui : « ven. 21:00 ».
func whenText(_ m: Match) -> String {
    let d = shortDay(m.date)
    return d.isEmpty ? m.kickoff : "\(d) \(m.kickoff)"
}

struct MatchesWidgetView: View {
    let entry: MatchesEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { familyOverride ?? envFamily }

    var body: some View {
        let palette: [Color] = entry.matches.prefix(2).flatMap { m -> [Color] in let c = teamColors(m.match); return [c.0, c.1] }
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            WidgetHeader(compact: family == .systemSmall, live: entry.matches.contains { $0.match.state == .live })
            if entry.matches.isEmpty {
                Spacer(minLength: 0)
                Text(entry.message ?? "Aucun match").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else if family == .systemSmall, let m = entry.matches.first {
                MatchTile(m: m, followed: entry.followed)
            } else if family == .systemMedium {
                HStack(spacing: 8) {
                    ForEach(entry.matches.prefix(2)) { m in MatchTile(m: m, followed: entry.followed) }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entry.matches.prefix(5).enumerated()), id: \.element.id) { i, m in
                        if i > 0 { Rectangle().fill(.white.opacity(0.09)).frame(height: 0.5).padding(.horizontal, 14) }
                        FollowRow(m: m, followed: entry.followed)
                    }
                }
                .glassPanel()
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.caption2.weight(.semibold))
                    Text(entry.date, style: .time).font(.caption2.weight(.semibold).monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity)
            }
        }
        .fontDesign(.rounded)
        .widgetBackground(WidgetGlassBackground(colors: palette), inApp: familyOverride != nil)
    }
}

/// « ★ Suivis » et la marque Tribune.
struct WidgetHeader: View {
    var compact = false
    var live = false
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "star.fill").font(.system(size: compact ? 12 : 15, weight: .bold))
            Text("Suivis").font(.system(size: compact ? 14 : 18, weight: .heavy, design: .rounded))
            if live {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("LIVE").font(.system(size: 9, weight: .heavy)).foregroundStyle(.green)
            }
            Spacer()
            TribuneMark(size: compact ? 18 : 24)
        }
        .foregroundStyle(.white)
    }
}

/// Petite marque de l'app : les trois gradins et le ballon.
struct TribuneMark: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.95))
            HStack(alignment: .bottom, spacing: size * 0.06) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: size * 0.05)
                        .fill(Color(red: 0.05, green: 0.6, blue: 0.33))
                        .frame(width: size * 0.15, height: size * (0.16 + 0.13 * Double(i)))
                }
            }
            .offset(y: size * 0.08)
        }
        .frame(width: size, height: size)
    }
}

/// Panneau en verre : voile clair, liseré lumineux.
extension View {
    func glassPanel(radius: CGFloat = 22) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
    }
}

/// Fond sombre avec halos aux couleurs des équipes, façon Liquid Glass.
struct WidgetGlassBackground: View {
    let colors: [Color]
    var body: some View {
        let cs = colors.isEmpty ? [Color.brand, Color(red: 0.2, green: 0.3, blue: 0.7)] : colors
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.09)
            GeometryReader { g in
                ZStack {
                    Circle().fill(cs[0]).frame(width: g.size.width * 0.9).position(x: g.size.width * 0.1, y: g.size.height * 0.05)
                    Circle().fill(cs[min(1, cs.count - 1)]).frame(width: g.size.width * 0.8).position(x: g.size.width * 0.95, y: g.size.height * 0.55)
                    if cs.count > 2 {
                        Circle().fill(cs[2]).frame(width: g.size.width * 0.7).position(x: g.size.width * 0.2, y: g.size.height * 1.0)
                    }
                }
                .opacity(0.38)
                .blur(radius: 50)
            }
            LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
        }
    }
}

struct WLogo: View {
    let img: UIImage?
    var size: CGFloat
    var body: some View {
        Group {
            if let img { Image(uiImage: img).resizable().scaledToFit() }
            else { Circle().fill(.white.opacity(0.18)) }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}

/// Logo de compétition : tel quel s'il est clair, sur une pastille blanche s'il est foncé.
struct WLeague: View {
    let img: UIImage?
    var light: Bool = true
    var size: CGFloat = 22
    var body: some View {
        if let img {
            Image(uiImage: img).resizable().scaledToFit()
                .padding(light ? 0 : size * 0.16)
                .frame(width: size, height: size)
                .background { if !light { Circle().fill(.white.opacity(0.92)) } }
        }
    }
}

/// Une équipe : logo et abréviation.
struct TeamStack: View {
    let side: Side
    let img: UIImage?
    var size: CGFloat = 34
    var bold = false
    var body: some View {
        VStack(spacing: 5) {
            WLogo(img: img, size: size)
            Text(side.abbr.isEmpty ? String(side.short.prefix(3)).uppercased() : side.abbr)
                .font(.system(size: size * 0.42, weight: bold ? .heavy : .bold, design: .rounded))
                .foregroundStyle(.white.opacity(bold ? 1 : 0.92))
                .lineLimit(1)
        }
    }
}

/// Centre d'un match : logo de compétition puis heure (ou score en direct).
struct MatchCenter: View {
    let m: WMatch
    var compact = false
    var body: some View {
        VStack(spacing: compact ? 4 : 7) {
            WLeague(img: m.leagueImg, light: m.leagueLight, size: compact ? 18 : 24)
            if m.match.hasScore {
                Text("\(m.match.home.score ?? "0") - \(m.match.away.score ?? "0")")
                    .font(.system(size: compact ? 17 : 21, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text(m.match.state == .live ? m.match.shortStatus : "Fin")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(m.match.state == .live ? Color.green : .white.opacity(0.55))
            } else {
                Text(whenText(m.match))
                    .font(.system(size: compact ? 13 : 17, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

/// Ligne du grand widget, comme le modèle : équipe — compétition + heure — équipe.
struct FollowRow: View {
    let m: WMatch
    let followed: Set<String>
    var body: some View {
        HStack(spacing: 0) {
            TeamStack(side: m.match.home, img: m.homeImg, size: 30, bold: followed.contains(m.match.home.id))
                .frame(width: 70)
            Spacer(minLength: 0)
            MatchCenter(m: m)
            Spacer(minLength: 0)
            TeamStack(side: m.match.away, img: m.awayImg, size: 30, bold: followed.contains(m.match.away.id))
                .frame(width: 70)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 9)
        .background {
            if m.match.state == .live {
                LinearGradient(colors: [Color.green.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
            }
        }
    }
}

/// Carte d'un match pour les petits et moyens formats.
struct MatchTile: View {
    let m: WMatch
    let followed: Set<String>
    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                TeamStack(side: m.match.home, img: m.homeImg, size: 28, bold: followed.contains(m.match.home.id))
                Spacer(minLength: 2)
                TeamStack(side: m.match.away, img: m.awayImg, size: 28, bold: followed.contains(m.match.away.id))
            }
            MatchCenter(m: m, compact: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPanel(radius: 18)
    }
}

// MARK: - Widget « Mon équipe » (équipe choisie dans les réglages du widget)

struct TeamEntity: AppEntity {
    /// L'identifiant contient tout ce qu'il faut : ligue|id|nom|couleur.
    let id: String
    var league: String { part(0) }
    var teamID: String { part(1) }
    var name: String { part(2) }
    var color: String? { let c = part(3); return c.isEmpty ? nil : c }
    private func part(_ i: Int) -> String {
        let p = id.split(separator: "|", omittingEmptySubsequences: false)
        return i < p.count ? String(p[i]) : ""
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Équipe"
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = TeamQuery()

    static func make(_ t: ESPNTeam, league: String) -> TeamEntity? {
        guard let id = t.id, let n = t.displayName else { return nil }
        return TeamEntity(id: "\(league)|\(id)|\(n.replacingOccurrences(of: "|", with: " "))|\(usableHex(t.color, t.alternateColor) ?? "")")
    }
}

struct TeamQuery: EntityStringQuery {
    static let leagues = ["fra.1", "eng.1", "esp.1", "ita.1", "ger.1"]

    func entities(for identifiers: [TeamEntity.ID]) async throws -> [TeamEntity] {
        identifiers.map { TeamEntity(id: $0) }
    }

    func suggestedEntities() async throws -> [TeamEntity] {
        await withTaskGroup(of: [TeamEntity].self, returning: [TeamEntity].self) { g in
            for l in Self.leagues {
                g.addTask { ((try? await ESPN.teams(l)) ?? []).compactMap { TeamEntity.make($0, league: l) } }
            }
            var all: [TeamEntity] = []
            for await part in g { all += part }
            return all.sorted { $0.name < $1.name }
        }
    }

    func entities(matching string: String) async throws -> [TeamEntity] {
        try await suggestedEntities().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}

struct TeamIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Mon équipe"
    static var description = IntentDescription("Choisis l’équipe à suivre.")
    @Parameter(title: "Équipe") var team: TeamEntity?
}

struct TeamEntry: TimelineEntry {
    let date: Date
    let teamName: String
    let tint: Color
    let logo: UIImage?
    let next: WMatch?
    let last: WMatch?
    let teamID: String
}

struct TeamProvider: AppIntentTimelineProvider {
    static let fallback = TeamEntity(id: "fra.1|160|Paris Saint-Germain|004170")

    func placeholder(in context: Context) -> TeamEntry {
        TeamEntry(date: .now, teamName: "Paris Saint-Germain", tint: Color(red: 0, green: 0.25, blue: 0.44), logo: nil, next: nil, last: nil, teamID: "160")
    }

    func snapshot(for configuration: TeamIntent, in context: Context) async -> TeamEntry {
        await load(configuration.team ?? Self.fallback)
    }

    func timeline(for configuration: TeamIntent, in context: Context) async -> Timeline<TeamEntry> {
        let e = await load(configuration.team ?? Self.fallback)
        let live = e.next?.match.state == .live
        return Timeline(entries: [e], policy: .after(.now.addingTimeInterval(live ? 300 : 3600)))
    }

    func load(_ t: TeamEntity) async -> TeamEntry {
        let ms = await ESPN.teamMatches(TeamRef(id: t.teamID, name: t.name, league: t.league, logo: nil, color: t.color))
        let next = ms.first { $0.state == .live } ?? ms.filter { $0.state == .pre && $0.date > .now }.min { $0.date < $1.date }
        let last = ms.filter { $0.state == .post }.max { $0.date < $1.date }
        let picked = [next, last].compactMap { $0 }
        let withImgs = await WidgetData.withImages(picked)
        let logo = await WidgetData.image(URL(string: "https://a.espncdn.com/i/teamlogos/soccer/500/\(t.teamID).png"))
        var tint = teamColor(hex: t.color, alt: nil, id: t.teamID)
        if t.color == nil, let s = ms.flatMap({ [$0.home, $0.away] }).first(where: { $0.id == t.teamID && usableHex($0.color, $0.altColor) != nil }) { tint = s.tint }
        return TeamEntry(date: .now, teamName: t.name, tint: tint, logo: logo,
                         next: next.flatMap { n in withImgs.first { $0.id == n.id } },
                         last: last.flatMap { l in withImgs.first { $0.id == l.id } },
                         teamID: t.teamID)
    }
}

struct TeamWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TribuneTeam", intent: TeamIntent.self, provider: TeamProvider()) { entry in
            TeamWidgetView(entry: entry)
        }
        .configurationDisplayName("Mon équipe")
        .description("Le prochain match et le dernier résultat de ton équipe.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TeamWidgetView: View {
    let entry: TeamEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { familyOverride ?? envFamily }

    var body: some View {
        Group {
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        WLogo(img: entry.logo, size: 40)
                        Spacer()
                        if entry.next?.match.state == .live { Circle().fill(Color.green).frame(width: 8, height: 8) }
                    }
                    Spacer(minLength: 0)
                    if let n = entry.next { nextBlock(n, compact: true) }
                    else { Text(entry.teamName).font(.headline) }
                }
            } else {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        WLogo(img: entry.logo, size: 46)
                        Spacer(minLength: 0)
                        Text(entry.teamName).font(.headline).lineLimit(2)
                        if let l = entry.last { lastLine(l) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let n = entry.next {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(n.match.state == .live ? "EN DIRECT" : "PROCHAIN MATCH").font(.caption2.weight(.heavy)).opacity(0.75)
                            HStack(spacing: 8) { WLogo(img: n.homeImg, size: 30); WLogo(img: n.awayImg, size: 30) }
                            nextBlock(n, compact: false)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.14)))
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .fontDesign(.rounded)
        .widgetBackground(WidgetGlassBackground(colors: [entry.tint, entry.tint.opacity(0.7), entry.tint]), inApp: familyOverride != nil)
    }

    private func opponent(_ m: Match) -> String { m.home.id == entry.teamID ? m.away.short : m.home.short }

    @ViewBuilder private func nextBlock(_ n: WMatch, compact: Bool) -> some View {
        let m = n.match
        VStack(alignment: .leading, spacing: 2) {
            Text("contre \(opponent(m))").font(.subheadline.weight(.bold)).lineLimit(1)
            if m.state == .live {
                Text("\(m.home.score ?? "0") – \(m.away.score ?? "0") · \(m.shortStatus)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Color.green)
            } else {
                Text(m.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(fr)).capitalizedFirst + " · " + m.kickoff)
                    .font(.caption.weight(.semibold)).opacity(0.85)
            }
            if !compact { Text(m.leagueName).font(.caption2).opacity(0.7).lineLimit(1) }
        }
    }

    private func lastLine(_ l: WMatch) -> some View {
        let m = l.match
        let home = m.home.id == entry.teamID
        let won = home ? m.home.winner : m.away.winner
        let lost = home ? m.away.winner : m.home.winner
        return HStack(spacing: 6) {
            Text(won ? "V" : lost ? "D" : "N")
                .font(.caption2.weight(.heavy))
                .frame(width: 18, height: 18)
                .background(Circle().fill(won ? Color.green : lost ? Color.red : Color.gray))
            Text("\(m.home.score ?? "0")–\(m.away.score ?? "0") \(opponent(m))").font(.caption.weight(.semibold)).lineLimit(1)
        }
    }
}

// MARK: - Aperçu des widgets dans l'app

struct WidgetPreviewView: View {
    @State private var matches: MatchesEntry?
    @State private var team: TeamEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Appuie longuement sur l’écran d’accueil, touche « Modifier » puis « Ajouter un widget » et cherche Tribune. Pour « Mon équipe », touche le widget en mode édition pour choisir ton équipe.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let m = matches {
                    HStack(alignment: .top, spacing: 14) {
                        MatchesWidgetView(entry: MatchesEntry(date: m.date, matches: Array(m.matches.prefix(1)), followed: m.followed), familyOverride: .systemSmall)
                            .frame(width: 170, height: 170)
                        if let t = team {
                            TeamWidgetView(entry: t, familyOverride: .systemSmall).frame(width: 170, height: 170)
                        }
                    }
                    MatchesWidgetView(entry: MatchesEntry(date: m.date, matches: Array(m.matches.prefix(2)), followed: m.followed), familyOverride: .systemMedium)
                        .frame(height: 170)
                    if let t = team { TeamWidgetView(entry: t, familyOverride: .systemMedium).frame(height: 170) }
                    MatchesWidgetView(entry: m, familyOverride: .systemLarge).frame(height: 380)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
                }
            }
            .padding(16)
        }
        .background { AmbientBackground(colors: [.brand, Color(red: 0.2, green: 0.3, blue: 0.7)], intensity: 0.7) }
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let m = MatchesProvider().load(teams: WidgetData.followed(), limit: 5)
            async let t = TeamProvider().load(TeamProvider.fallback)
            let (mm, tt) = await (m, t)
            withAnimation(.smooth) { matches = mm; team = tt }
        }
    }
}
