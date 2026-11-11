import Foundation
import SwiftUI
import UIKit

/// Logos de compétition à jour, depuis TheSportsDB (base libre et collaborative).
enum LeagueBadges {
    static let group = "group.com.tepsko.tribune"

    /// Identifiants TheSportsDB des compétitions.
    static let ids: [String: String] = [
        "fra.1": "4334", "eng.1": "4328", "esp.1": "4335", "ita.1": "4332", "ger.1": "4331",
        "uefa.champions": "4480", "uefa.europa": "4481", "uefa.europa.conf": "5071",
        "fifa.world": "4429", "uefa.euro": "4502", "uefa.nations": "4490",
        "conmebol.america": "4499", "caf.nations": "4496",
        "fra.coupe_de_france": "4484", "eng.fa": "4482", "eng.league_cup": "4570",
        "esp.copa_del_rey": "4483", "ita.coppa_italia": "4506", "ger.dfb_pokal": "4485",
        "fra.2": "4401", "fra.3": "4637", "por.1": "4344", "ned.1": "4337", "bel.1": "4338",
        "tur.1": "4339", "ksa.1": "4668", "usa.1": "4346",
    ]

    static func lookup(_ id: String) async -> (name: String, badge: URL)? {
        for key in ["123", "3"] {
            guard let u = URL(string: "https://www.thesportsdb.com/api/v1/json/\(key)/lookupleague.php?id=\(id)"),
                  let r = try? await URLSession.shared.data(from: u),
                  let o = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any],
                  let l = (o["leagues"] as? [[String: Any]])?.first,
                  let b = l["strBadge"] as? String, !b.isEmpty, let url = URL(string: b) else { continue }
            return ((l["strLeague"] as? String) ?? "", url)
        }
        return nil
    }

    /// Récupère les logos manquants (une fois par semaine au plus), 3 requêtes à la fois.
    static func refresh(_ known: [String: String]) async -> [String: String] {
        let d = UserDefaults.standard
        let last = d.double(forKey: "badgesFetchedAt2")
        let stale = Date().timeIntervalSince1970 - last > 7 * 24 * 3600
        let todo = ids.filter { stale || known[$0.key + "#badge"] == nil }
        guard !todo.isEmpty else { return [:] }
        var out: [String: String] = [:]
        await withTaskGroup(of: (String, URL?).self) { g in
            var it = todo.makeIterator()
            for _ in 0..<3 { if let job = it.next() { g.addTask { (job.key, await LeagueBadges.lookup(job.value)?.badge) } } }
            for await (slug, url) in g {
                if let job = it.next() { g.addTask { (job.key, await LeagueBadges.lookup(job.value)?.badge) } }
                if let url { out[slug + "#badge"] = url.absoluteString }
            }
        }
        if !out.isEmpty { d.set(Date().timeIntervalSince1970, forKey: "badgesFetchedAt2") }
        return out
    }
}


/// Télécharge un logo et détecte s'il est clair (texte blanc…) pour choisir la pastille qui le fait ressortir.
actor BadgeLoader {
    static let shared = BadgeLoader()
    private var cache: [URL: (UIImage, Bool)] = [:]

    func load(_ url: URL) async -> (UIImage, Bool)? {
        if let c = cache[url] { return c }
        guard let r = try? await URLSession.shared.data(from: url), let img = UIImage(data: r.0) else { return nil }
        let small = img.preparingThumbnail(of: CGSize(width: 120, height: 120)) ?? img
        let res = (small, Self.isLight(small))
        cache[url] = res
        return res
    }

    /// Luminosité moyenne des pixels visibles.
    static func isLight(_ img: UIImage) -> Bool {
        guard let cg = img.cgImage else { return false }
        let n = 24
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        var sum = 0.0, count = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Double(px[i + 3]) / 255
            guard a > 0.4 else { continue }
            let r = Double(px[i]) / 255 / a, g = Double(px[i + 1]) / 255 / a, b = Double(px[i + 2]) / 255 / a
            sum += 0.299 * r + 0.587 * g + 0.114 * b
            count += 1
        }
        guard count > 0 else { return false }
        return sum / count > 0.72
    }
}

/// Logo de compétition sur une pastille : sombre si le logo est clair, blanche sinon.
struct LeagueBadge: View {
    @Environment(AppStore.self) private var store
    let league: String
    var size: CGFloat = 46
    var darkDisc: Color = Color(red: 0.06, green: 0.08, blue: 0.2)
    var glow: Color = .clear
    @State private var loaded: (UIImage, Bool)?

    var body: some View {
        let light = loaded?.1 ?? false
        ZStack {
            Circle()
                .fill(light ? AnyShapeStyle(LinearGradient(colors: [darkDisc, .black], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.94)))
                .overlay(Circle().strokeBorder(.white.opacity(light ? 0.25 : 0), lineWidth: 1))
                .shadow(color: glow.opacity(0.7), radius: size * 0.25)
            if let img = loaded?.0 {
                Image(uiImage: img).resizable().interpolation(.high).scaledToFit()
                    .padding(size * 0.17)
                    .transition(.opacity)
            } else {
                Image(systemName: "trophy.fill").font(.system(size: size * 0.38)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: store.logo(for: league)) {
            guard let u = store.logo(for: league), let r = await BadgeLoader.shared.load(u) else { return }
            withAnimation(.smooth(duration: 0.3)) { loaded = r }
        }
    }
}
