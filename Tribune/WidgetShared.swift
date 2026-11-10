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
    var id: String { match.id }
}

enum WidgetData {
    static let competitions: [Competition] = Competition.all.filter { [CompGroup.top, .europe, .nations].contains($0.group) }

    static func image(_ url: URL?) async -> UIImage? {
        guard let url, let r = try? await URLSession.shared.data(from: url), let img = UIImage(data: r.0) else { return nil }
        return img.preparingThumbnail(of: CGSize(width: 90, height: 90)) ?? img
    }

    static func withImages(_ ms: [Match]) async -> [WMatch] {
        await withTaskGroup(of: (Int, UIImage?, UIImage?).self, returning: [WMatch].self) { g in
            for (i, m) in ms.enumerated() {
                g.addTask {
                    async let h = WidgetData.image(m.home.logo)
                    async let a = WidgetData.image(m.away.logo)
                    return (i, await h, await a)
                }
            }
            var imgs: [Int: (UIImage?, UIImage?)] = [:]
            for await (i, h, a) in g { imgs[i] = (h, a) }
            return ms.enumerated().map { (i, m) -> WMatch in WMatch(match: m, homeImg: imgs[i]?.0, awayImg: imgs[i]?.1) }
        }
    }

    /// Matchs à mettre en avant : en direct, puis à venir, puis terminés récemment.
    static func featured(_ ms: [Match]) -> [Match] {
        let live = ms.filter { $0.state == .live }
        let next = ms.filter { $0.state == .pre }.sorted { $0.date < $1.date }
        let done = ms.filter { $0.state == .post }.sorted { $0.date > $1.date }
        return live + next + done
    }
}

// MARK: - Widget « Matchs »

struct MatchesEntry: TimelineEntry {
    let date: Date
    let matches: [WMatch]
}

struct MatchesProvider: TimelineProvider {
    func placeholder(in context: Context) -> MatchesEntry { MatchesEntry(date: .now, matches: []) }

    func getSnapshot(in context: Context, completion: @escaping (MatchesEntry) -> Void) {
        Task { completion(await load(limit: limit(context.family))) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MatchesEntry>) -> Void) {
        Task {
            let e = await load(limit: limit(context.family))
            let live = e.matches.contains { $0.match.state == .live }
            completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(live ? 300 : 1800))))
        }
    }

    func limit(_ f: WidgetFamily) -> Int {
        switch f { case .systemSmall: 1; case .systemMedium: 3; default: 6 }
    }

    func load(limit: Int) async -> MatchesEntry {
        var r = await ESPN.matches(on: Calendar.current.startOfDay(for: .now), competitions: WidgetData.competitions) { _, _ in }
        if r.matches.isEmpty, let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) {
            r = await ESPN.matches(on: tomorrow, competitions: WidgetData.competitions) { _, _ in }
        }
        let picked = Array(WidgetData.featured(r.matches).prefix(limit))
        return MatchesEntry(date: .now, matches: await WidgetData.withImages(picked))
    }
}

struct MatchesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TribuneMatches", provider: MatchesProvider()) { entry in
            MatchesWidgetView(entry: entry)
        }
        .configurationDisplayName("Matchs")
        .description("Les matchs en direct et à venir des grandes compétitions.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
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
                VStack(spacing: 6) {
                    Image(systemName: "soccerball").font(.title2)
                    Text("Aucun match aujourd’hui").font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
            } else if family == .systemSmall, let m = first {
                SmallMatch(m: m)
            } else {
                VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 6) {
                    HStack {
                        Text("Tribune").font(.caption.weight(.heavy))
                        Spacer()
                        if entry.matches.contains(where: { $0.match.state == .live }) {
                            HStack(spacing: 4) { Circle().fill(Color.green).frame(width: 6, height: 6); Text("En direct").font(.caption2.weight(.bold)) }
                        }
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    ForEach(entry.matches) { m in WideRow(m: m, large: family == .systemLarge) }
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

struct SmallMatch: View {
    let m: WMatch
    var body: some View {
        VStack(spacing: 8) {
            Text(m.match.leagueName).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            HStack(spacing: 10) {
                WLogo(img: m.homeImg, size: 42)
                WLogo(img: m.awayImg, size: 42)
            }
            if m.match.hasScore {
                Text("\(m.match.home.score ?? "0") – \(m.match.away.score ?? "0")")
                    .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
            } else {
                Text(m.match.kickoff).font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
            }
            Text(m.match.state == .live ? "En direct · \(m.match.shortStatus)" : m.match.state == .post ? "Terminé" : "\(m.match.home.abbr) – \(m.match.away.abbr)")
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
    var body: some View {
        let colors = teamColors(m.match)
        HStack(spacing: 8) {
            WLogo(img: m.homeImg, size: large ? 24 : 20)
            Text(m.match.home.short).font(.subheadline.weight(.semibold)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            center.frame(width: 62)
            Text(m.match.away.short).font(.subheadline.weight(.semibold)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
            WLogo(img: m.awayImg, size: large ? 24 : 20)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, large ? 9 : 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [colors.0.opacity(0.55), colors.1.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08)))
        )
    }

    @ViewBuilder private var center: some View {
        VStack(spacing: 0) {
            if m.match.hasScore {
                Text("\(m.match.home.score ?? "0") – \(m.match.away.score ?? "0")").font(.subheadline.weight(.heavy).monospacedDigit())
                Text(m.match.shortStatus).font(.system(size: 9, weight: .bold)).foregroundStyle(m.match.state == .live ? Color.green : .white.opacity(0.7))
            } else {
                Text(m.match.kickoff).font(.subheadline.weight(.bold).monospacedDigit())
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
        let evs = await ESPN.schedule(t.league, team: t.teamID)
        let ms = evs.compactMap { Match($0, league: t.league) }
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
            async let m = MatchesProvider().load(limit: 6)
            async let t = TeamProvider().load(TeamProvider.fallback)
            let (mm, tt) = await (m, t)
            withAnimation(.smooth) { matches = mm; team = tt }
        }
    }
}
