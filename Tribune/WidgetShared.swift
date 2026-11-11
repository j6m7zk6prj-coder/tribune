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
                WMatch(match: m, homeImg: imgs[i]?.0, awayImg: imgs[i]?.1, leagueImg: imgs[i]?.2)
            }
        }
    }
}

// MARK: - Widget « Mes équipes » : prochain match de chaque équipe suivie

struct FollowedIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Mes équipes"
    static var description = IntentDescription("Laisse vide pour reprendre les équipes suivies dans Tribune.")
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
        switch f { case .systemSmall: 1; case .systemMedium: 3; default: 6 }
    }

    func load(teams: [TeamRef], limit: Int) async -> MatchesEntry {
        guard !teams.isEmpty else {
            return MatchesEntry(date: .now, matches: [], message: "Suis des équipes dans Tribune, ou choisis-les en modifiant le widget.")
        }
        let ids = Set(teams.map(\.id))
        var nexts: [Match] = []
        await withTaskGroup(of: Match?.self) { g in
            for t in teams.prefix(8) {
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
    if cal.isDateInToday(d) { return "Aujourd’hui" }
    if cal.isDateInTomorrow(d) { return "Demain" }
    return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(fr)).capitalizedFirst
}

struct MatchesWidgetView: View {
    let entry: MatchesEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { familyOverride ?? envFamily }

    var body: some View {
        let first = entry.matches.first
        let colors = first.map { teamColors($0.match) } ?? (Color.brand, Color(red: 0.1, green: 0.3, blue: 0.6))
        Group {
            if entry.matches.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "star.circle.fill").font(.title)
                    Text(entry.message ?? "Aucun match").font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if family == .systemSmall, let m = first {
                SmallMatch(m: m)
            } else {
                VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill").font(.caption2)
                        Text("Mes équipes").font(.caption.weight(.heavy))
                        Spacer()
                        if entry.matches.contains(where: { $0.match.state == .live }) {
                            HStack(spacing: 4) { Circle().fill(Color.green).frame(width: 6, height: 6); Text("En direct").font(.caption2.weight(.bold)) }
                        }
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    ForEach(entry.matches) { m in WideRow(m: m, large: family == .systemLarge, followed: entry.followed) }
                    Spacer(minLength: 0)
                }
            }
        }
        .fontDesign(.rounded)
        .widgetBackground(WidgetBackground(a: colors.0, b: colors.1), inApp: familyOverride != nil)
    }
}

struct WidgetBackground: View {
    let a: Color
    let b: Color
    var body: some View {
        ZStack {
            Color.black
            LinearGradient(colors: [a.opacity(0.95), b.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.18), .clear], center: .topLeading, startRadius: 0, endRadius: 220)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        }
    }
}

struct WLogo: View {
    let img: UIImage?
    var size: CGFloat
    var body: some View {
        Group {
            if let img { Image(uiImage: img).resizable().scaledToFit() }
            else { Circle().fill(.white.opacity(0.25)) }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

/// Logo de compétition sur une petite pastille blanche (lisible sur tous les fonds).
struct WLeague: View {
    let img: UIImage?
    var size: CGFloat = 16
    var body: some View {
        if let img {
            Image(uiImage: img).resizable().scaledToFit()
                .padding(size * 0.14)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(0.92)))
        }
    }
}

struct SmallMatch: View {
    let m: WMatch
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 5) {
                WLeague(img: m.leagueImg, size: 16)
                Text(m.match.leagueName).font(.caption2.weight(.bold)).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 10) {
                WLogo(img: m.homeImg, size: 40)
                WLogo(img: m.awayImg, size: 40)
            }
            if m.match.hasScore {
                Text("\(m.match.home.score ?? "0") – \(m.match.away.score ?? "0")")
                    .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
            } else {
                Text(m.match.kickoff).font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
            }
            Text(m.match.state == .live ? "En direct · \(m.match.shortStatus)" : shortDay(m.match.date))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(m.match.state == .live ? Color.green : .white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WideRow: View {
    let m: WMatch
    let large: Bool
    var followed: Set<String> = []

    var body: some View {
        let colors = teamColors(m.match)
        HStack(spacing: 8) {
            WLogo(img: m.homeImg, size: large ? 24 : 20)
            Text(m.match.home.short)
                .font(.subheadline.weight(followed.contains(m.match.home.id) ? .heavy : .medium)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            center.frame(width: 76)
            Text(m.match.away.short)
                .font(.subheadline.weight(followed.contains(m.match.away.id) ? .heavy : .medium)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
            WLogo(img: m.awayImg, size: large ? 24 : 20)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, large ? 8 : 5)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [colors.0.opacity(0.55), colors.1.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08)))
        )
    }

    @ViewBuilder private var center: some View {
        VStack(spacing: 1) {
            if m.match.hasScore {
                Text("\(m.match.home.score ?? "0") – \(m.match.away.score ?? "0")").font(.subheadline.weight(.heavy).monospacedDigit())
                Text(m.match.shortStatus).font(.system(size: 9, weight: .bold)).foregroundStyle(m.match.state == .live ? Color.green : .white.opacity(0.7))
            } else {
                Text(m.match.kickoff).font(.subheadline.weight(.bold).monospacedDigit())
                HStack(spacing: 3) {
                    WLeague(img: m.leagueImg, size: 11)
                    Text(shortDay(m.match.date)).font(.system(size: 9, weight: .bold)).lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.8))
            }
        }
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
        .widgetBackground(WidgetBackground(a: entry.tint, b: entry.tint.opacity(0.55)), inApp: familyOverride != nil)
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
                        MatchesWidgetView(entry: MatchesEntry(date: m.date, matches: Array(m.matches.prefix(1))), familyOverride: .systemSmall)
                            .frame(width: 170, height: 170)
                        if let t = team {
                            TeamWidgetView(entry: t, familyOverride: .systemSmall).frame(width: 170, height: 170)
                        }
                    }
                    MatchesWidgetView(entry: MatchesEntry(date: m.date, matches: Array(m.matches.prefix(3))), familyOverride: .systemMedium)
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
            async let m = MatchesProvider().load(teams: WidgetData.followed(), limit: 6)
            async let t = TeamProvider().load(TeamProvider.fallback)
            let (mm, tt) = await (m, t)
            withAnimation(.smooth) { matches = mm; team = tt }
        }
    }
}
