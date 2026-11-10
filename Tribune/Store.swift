import SwiftUI
import Observation

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

    var favorites: [TeamRef] { didSet { save(favorites, "favorites") } }
    var enabled: Set<String> { didSet { d.set(Array(enabled), forKey: "enabled") } }
    var appearance: Appearance { didSet { d.set(appearance.rawValue, forKey: "appearance") } }
    var leagueLogos: [String: String] { didSet { d.set(leagueLogos, forKey: "leagueLogos") } }

    init() {
        favorites = (d.data(forKey: "favorites")).flatMap { try? JSONDecoder().decode([TeamRef].self, from: $0) } ?? []
        enabled = Set(d.stringArray(forKey: "enabled") ?? Competition.all.filter(\.defaultOn).map(\.id))
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .dark
        leagueLogos = (d.dictionary(forKey: "leagueLogos") as? [String: String]) ?? [:]

        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-appearance"), i + 1 < args.count, let a = Appearance(rawValue: args[i + 1]) { appearance = a }
        if args.contains("-seed") && favorites.isEmpty {
            favorites = [
                TeamRef(id: "160", name: "Paris Saint-Germain", league: "fra.1", logo: nil),
                TeamRef(id: "86", name: "Real Madrid", league: "esp.1", logo: nil),
                TeamRef(id: "364", name: "Liverpool", league: "eng.1", logo: nil),
                TeamRef(id: "478", name: "France", league: "uefa.nations", logo: nil),
            ]
        }
    }

    private func save<T: Encodable>(_ v: T, _ k: String) { if let data = try? JSONEncoder().encode(v) { d.set(data, forKey: k) } }

    var enabledCompetitions: [Competition] { Competition.all.filter { enabled.contains($0.id) } }
    var favoriteIDs: Set<String> { Set(favorites.map(\.id)) }

    func isFavorite(_ id: String) -> Bool { favorites.contains { $0.id == id } }

    func toggle(_ t: TeamRef) {
        if let i = favorites.firstIndex(where: { $0.id == t.id }) { favorites.remove(at: i) } else { favorites.append(t) }
    }

    func setLogo(_ league: String, _ url: URL) {
        if leagueLogos[league] != url.absoluteString { leagueLogos[league] = url.absoluteString }
    }

    func logo(for league: String) -> URL? { leagueLogos[league].flatMap(URL.init(string:)) }
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
