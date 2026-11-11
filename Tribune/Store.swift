import SwiftUI
import Observation
import WidgetKit

enum Appearance: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var label: String { switch self { case .system: "Automatique"; case .dark: "Sombre"; case .light: "Clair" } }
    var scheme: ColorScheme? { switch self { case .system: nil; case .dark: .dark; case .light: .light } }
}

/// Réglages et équipes suivies, enregistrés sur l'iPhone.
@Observable @MainActor
final class AppStore {
    private let d = UserDefaults.standard

    var favorites: [TeamRef] { didSet { save(favorites, "favorites"); shareWithWidgets() } }
    var enabled: Set<String> { didSet { d.set(Array(enabled), forKey: "enabled") } }
    var appearance: Appearance { didSet { d.set(appearance.rawValue, forKey: "appearance") } }
    var leagueLogos: [String: String] { didSet { d.set(leagueLogos, forKey: "leagueLogos"); shareWithWidgets(reload: false) } }

    init() {
        let d = UserDefaults.standard
        favorites = (d.data(forKey: "favorites")).flatMap { try? JSONDecoder().decode([TeamRef].self, from: $0) } ?? []
        enabled = Set(d.stringArray(forKey: "enabled") ?? Competition.all.filter(\.defaultOn).map(\.id))
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .dark
        leagueLogos = (d.dictionary(forKey: "leagueLogos") as? [String: String]) ?? [:]
        // Nouvelle compétition : la Ligue 3 est affichée par défaut, une seule fois.
        if !d.bool(forKey: "added.fra.3") {
            d.set(true, forKey: "added.fra.3")
            if d.stringArray(forKey: "enabled") != nil { enabled.insert("fra.3"); d.set(Array(enabled), forKey: "enabled") }
        }

        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-appearance"), i + 1 < args.count, let a = Appearance(rawValue: args[i + 1]) { appearance = a }
        if args.contains("-seed") && favorites.isEmpty {
            favorites = [
                TeamRef(id: "160", name: "Paris Saint-Germain", league: "fra.1", logo: nil, color: "004170"),
                TeamRef(id: "86", name: "Real Madrid", league: "esp.1", logo: nil, color: "00529F"),
                TeamRef(id: "364", name: "Liverpool", league: "eng.1", logo: nil, color: "C8102E"),
                TeamRef(id: "478", name: "France", league: "uefa.nations", logo: nil, color: "1F3C88"),
            ]
            if let data = try? JSONEncoder().encode(favorites) { d.set(data, forKey: "favorites") }
        }
    }

    private func save<T: Encodable>(_ v: T, _ k: String) { if let data = try? JSONEncoder().encode(v) { d.set(data, forKey: k) } }

    /// Copie les équipes suivies et les logos dans l'espace partagé avec les widgets.
    func shareWithWidgets(reload: Bool = true) {
        guard let shared = UserDefaults(suiteName: LeagueBadges.group) else { return }
        if let data = try? JSONEncoder().encode(favorites) { shared.set(data, forKey: "favorites") }
        shared.set(leagueLogos, forKey: "leagueLogos")
        if reload { WidgetCenter.shared.reloadAllTimelines() }
    }

    func refreshBadges() async {
        let fresh = await LeagueBadges.refresh(leagueLogos)
        if !fresh.isEmpty { leagueLogos.merge(fresh) { _, new in new } }
    }

    var enabledCompetitions: [Competition] { Competition.all.filter { enabled.contains($0.id) } }
    var favoriteIDs: Set<String> { Set(favorites.map(\.id)) }

    func isFavorite(_ id: String) -> Bool { favorites.contains { $0.id == id } }

    func toggle(_ t: TeamRef) {
        if let i = favorites.firstIndex(where: { $0.id == t.id }) { favorites.remove(at: i) } else { favorites.append(t) }
    }

    func setLogos(_ league: String, _ l: ESPNLeague) {
        var copy = leagueLogos
        if let u = l.lightLogo { copy[league] = u.absoluteString }
        if let u = l.darkLogo { copy[league + "#dark"] = u.absoluteString }
        if copy != leagueLogos { leagueLogos = copy }
    }

    func logo(for league: String, dark: Bool = false) -> URL? {
        let s = leagueLogos[league + "#badge"] ?? (dark ? leagueLogos[league + "#dark"] : nil) ?? leagueLogos[league]
        return s.flatMap { URL(string: $0) }
    }
}

/// Paramètres de lancement utilisés pour les captures d'écran automatiques.
enum Launch {
    static let args = ProcessInfo.processInfo.arguments
    static func value(_ k: String) -> String? {
        guard let i = args.firstIndex(of: k), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static var open: String? { value("-open") }
    @MainActor static var consumed = Set<String>()
    @MainActor static func take(_ what: String) -> Bool {
        guard open == what, !consumed.contains(what) else { return false }
        consumed.insert(what); return true
    }
}
