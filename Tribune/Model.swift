import Foundation
import SwiftUI

let fr = Locale(identifier: "fr_FR")

// MARK: - Compétitions

enum CompGroup: String, CaseIterable, Identifiable {
    case top = "Grands championnats"
    case europe = "Coupes d’Europe"
    case nations = "Sélections"
    case cups = "Coupes nationales"
    case others = "Autres championnats"
    var id: String { rawValue }
}

struct Competition: Identifiable, Hashable {
    let id: String          // identifiant ESPN, ex. « fra.1 »
    let name: String
    let area: String
    let group: CompGroup
    var defaultOn: Bool { group != .others }

    static let all: [Competition] = [
        .init(id: "fra.1", name: "Ligue 1", area: "France", group: .top),
        .init(id: "eng.1", name: "Premier League", area: "Angleterre", group: .top),
        .init(id: "esp.1", name: "LaLiga", area: "Espagne", group: .top),
        .init(id: "ita.1", name: "Serie A", area: "Italie", group: .top),
        .init(id: "ger.1", name: "Bundesliga", area: "Allemagne", group: .top),

        .init(id: "uefa.champions", name: "Ligue des champions", area: "Europe", group: .europe),
        .init(id: "uefa.europa", name: "Ligue Europa", area: "Europe", group: .europe),
        .init(id: "uefa.europa.conf", name: "Ligue Conférence", area: "Europe", group: .europe),

        .init(id: "fifa.world", name: "Coupe du monde", area: "Monde", group: .nations),
        .init(id: "uefa.euro", name: "Euro", area: "Europe", group: .nations),
        .init(id: "uefa.nations", name: "Ligue des nations", area: "Europe", group: .nations),
        .init(id: "fifa.worldq.uefa", name: "Qualifications CdM — Europe", area: "Europe", group: .nations),
        .init(id: "uefa.euroq", name: "Qualifications Euro", area: "Europe", group: .nations),
        .init(id: "fifa.friendly", name: "Matchs amicaux", area: "Monde", group: .nations),
        .init(id: "caf.nations", name: "Coupe d’Afrique des nations", area: "Afrique", group: .nations),
        .init(id: "conmebol.america", name: "Copa América", area: "Amérique du Sud", group: .nations),

        .init(id: "fra.coupe_de_france", name: "Coupe de France", area: "France", group: .cups),
        .init(id: "eng.fa", name: "FA Cup", area: "Angleterre", group: .cups),
        .init(id: "eng.league_cup", name: "Carabao Cup", area: "Angleterre", group: .cups),
        .init(id: "esp.copa_del_rey", name: "Copa del Rey", area: "Espagne", group: .cups),
        .init(id: "ita.coppa_italia", name: "Coppa Italia", area: "Italie", group: .cups),
        .init(id: "ger.dfb_pokal", name: "DFB-Pokal", area: "Allemagne", group: .cups),

        .init(id: "fra.2", name: "Ligue 2", area: "France", group: .others),
        .init(id: "por.1", name: "Liga Portugal", area: "Portugal", group: .others),
        .init(id: "ned.1", name: "Eredivisie", area: "Pays-Bas", group: .others),
        .init(id: "bel.1", name: "Pro League", area: "Belgique", group: .others),
        .init(id: "tur.1", name: "Süper Lig", area: "Turquie", group: .others),
        .init(id: "ksa.1", name: "Saudi Pro League", area: "Arabie saoudite", group: .others),
        .init(id: "usa.1", name: "MLS", area: "États-Unis", group: .others),
    ]

    static func named(_ slug: String) -> Competition? { all.first { $0.id == slug } }

    /// Couleur de chaque compétition (identité visuelle approximative).
    var tint: Color {
        let hex: String
        switch id {
        case "fra.1": hex = "1B3A8C"
        case "eng.1": hex = "6A2C91"
        case "esp.1": hex = "E8432F"
        case "ita.1": hex = "1C7FD6"
        case "ger.1": hex = "D3171E"
        case "uefa.champions": hex = "1E3FA8"
        case "uefa.europa": hex = "F07F12"
        case "uefa.europa.conf": hex = "17B26A"
        case "fifa.world": hex = "A3203F"
        case "uefa.euro": hex = "2B5BD6"
        case "uefa.nations": hex = "2E4DB8"
        case "fifa.worldq.uefa": hex = "6C3FC7"
        case "uefa.euroq": hex = "3A6FE0"
        case "fifa.friendly": hex = "4C9A8A"
        case "caf.nations": hex = "D99A1E"
        case "conmebol.america": hex = "C73B3B"
        case "fra.coupe_de_france": hex = "2856C9"
        case "eng.fa": hex = "C8102E"
        case "eng.league_cup": hex = "1FA36B"
        case "esp.copa_del_rey": hex = "B8232F"
        case "ita.coppa_italia": hex = "1F8A4C"
        case "ger.dfb_pokal": hex = "2F7D32"
        case "fra.2": hex = "E4572E"
        case "por.1": hex = "0F5E3C"
        case "ned.1": hex = "E35D1A"
        case "bel.1": hex = "C4302B"
        case "tur.1": hex = "D7262E"
        case "ksa.1": hex = "1B8A5A"
        case "usa.1": hex = "3557A6"
        default: return fallbackHue(id)
        }
        return Color(hex: hex) ?? .brand
    }
    var order: Int { Competition.all.firstIndex(of: self) ?? 999 }
}

// MARK: - Match

enum MatchState: Hashable { case pre, live, post, off }

struct Side: Hashable {
    let id: String
    let name: String
    let short: String
    let abbr: String
    let logo: URL?
    let score: String?
    let shootout: String?
    let winner: Bool
    var color: String?
    var altColor: String?

    init(_ c: ESPNCompetitor?) {
        let t = c?.team
        id = t?.id ?? c?.id ?? "?"
        name = t?.displayName ?? t?.name ?? "—"
        short = t?.shortDisplayName ?? t?.displayName ?? "—"
        abbr = t?.abbreviation ?? String(name.prefix(3)).uppercased()
        logo = t?.logoURL
        score = c?.score
        shootout = c?.shootout
        winner = c?.winner ?? false
        color = t?.color; altColor = t?.alternateColor
    }
}

struct Match: Identifiable, Hashable {
    let id: String
    let league: String
    let leagueName: String
    let date: Date
    let state: MatchState
    let statusName: String
    let clock: String
    var home: Side
    var away: Side
    let venue: String?

    init?(_ e: ESPNEvent, league: String, leagueName: String? = nil) {
        guard let comp = e.competitions.first else { return nil }
        id = e.id
        let slug = e.league?.slug ?? league
        self.league = slug
        self.leagueName = Competition.named(slug)?.name ?? leagueName ?? e.league?.name ?? ""
        date = parseESPNDate(comp.date ?? e.date) ?? .distantPast
        let st = comp.status ?? e.status
        let name = st?.type?.name ?? ""
        statusName = name
        clock = st?.displayClock ?? ""
        switch st?.type?.state {
        case "in": state = .live
        case "post": state = .post
        default:
            state = (name.contains("POSTPONED") || name.contains("CANCELED") || name.contains("SUSPENDED") || name.contains("ABANDONED")) ? .off : .pre
        }
        home = Side(comp.competitors.first { $0.homeAway == "home" } ?? comp.competitors.first)
        away = Side(comp.competitors.first { $0.homeAway == "away" } ?? comp.competitors.last)
        if let v = comp.venue?.fullName { venue = [v, comp.venue?.city].compactMap { $0 }.joined(separator: ", ") } else { venue = nil }
    }

    var kickoff: String { date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(fr)) }

    /// Petit statut à gauche de la ligne (minute, MT, Fin…).
    var shortStatus: String {
        switch state {
        case .live:
            if statusName.contains("HALFTIME") { return "MT" }
            if statusName.contains("SHOOTOUT") { return "TAB" }
            if statusName.contains("END_PERIOD") || statusName.contains("OVERTIME") && clock.isEmpty { return "Prol." }
            return clock.isEmpty ? "Live" : clock
        case .post:
            if statusName.contains("PEN") { return "TAB" }
            if statusName.contains("AET") || statusName.contains("EXTRA") { return "AP" }
            return "Fin"
        case .off:
            if statusName.contains("CANCELED") { return "Ann." }
            return "Rep."
        case .pre: return ""
        }
    }

    /// Statut en toutes lettres pour la fiche du match.
    var longStatus: String {
        switch state {
        case .live:
            if statusName.contains("HALFTIME") { return "Mi-temps" }
            if statusName.contains("SHOOTOUT") { return "Tirs au but" }
            return clock
        case .post:
            if statusName.contains("PEN") { return "Après tirs au but" }
            if statusName.contains("AET") || statusName.contains("EXTRA") { return "Après prolongation" }
            return "Terminé"
        case .off: return statusName.contains("CANCELED") ? "Annulé" : "Reporté"
        case .pre:
            let day = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(fr))
            return day.prefix(1).uppercased() + day.dropFirst()
        }
    }

    var hasScore: Bool { state == .live || state == .post }

    func involves(_ teamIDs: Set<String>) -> Bool { teamIDs.contains(home.id) || teamIDs.contains(away.id) }
}

private let isoFormatters: [DateFormatter] = ["yyyy-MM-dd'T'HH:mmX", "yyyy-MM-dd'T'HH:mm:ssX", "yyyy-MM-dd'T'HH:mm:ss.SSSX"].map {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = $0; return f
}

func parseESPNDate(_ s: String?) -> Date? {
    guard let s else { return nil }
    for f in isoFormatters { if let d = f.date(from: s) { return d } }
    return nil
}

func espnDay(_ d: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd"
    return f.string(from: d)
}

// MARK: - Équipe suivie

struct TeamRef: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let league: String
    let logo: String?
    var color: String? = nil
    var logoURL: URL? { logo.flatMap(URL.init(string:)) ?? URL(string: "https://a.espncdn.com/i/teamlogos/soccer/500/\(id).png") }

    init(id: String, name: String, league: String, logo: String?, color: String? = nil) {
        self.id = id; self.name = name; self.league = league; self.logo = logo; self.color = color
    }
    init(_ s: Side, league: String) {
        self.init(id: s.id, name: s.name, league: league, logo: s.logo?.absoluteString, color: usableHex(s.color, s.altColor))
    }
}

// MARK: - Couleurs

extension Color {
    /// Vert de l'app, adapté au thème clair et sombre.
    static let brand = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(red: 0.20, green: 0.84, blue: 0.50, alpha: 1) : UIColor(red: 0.0, green: 0.56, blue: 0.30, alpha: 1)
    })

    init?(hex: String?) {
        guard var h = hex?.trimmingCharacters(in: .whitespaces), !h.isEmpty else { return nil }
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

func hexRGB(_ hex: String?) -> (Double, Double, Double)? {
    guard var h = hex, !h.isEmpty else { return nil }
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
}
