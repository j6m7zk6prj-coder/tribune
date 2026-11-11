import SwiftUI

struct StandingRow: Identifiable {
    let id: String
    let rank: Int
    let team: TeamRef
    let played: Int
    let diff: Int
    let points: Int
    let won: Int
    let drawn: Int
    let lost: Int
    let noteColor: Color?
    let noteText: String?
}

struct Note: Identifiable { let color: Color; let text: String; var id: String { text } }

struct StandingGroup: Identifiable {
    let id: Int
    let name: String?
    let rows: [StandingRow]
}

@MainActor
func loadStandings(_ league: String, season: Int? = nil) async -> [StandingGroup]? {
    if SportsDB.covers(league) { return await SportsDB.standings(league, year: season ?? Competition.currentSeason) }
    guard let r = try? await ESPN.standings(league, season: season) else { return nil }
    return r.groups.enumerated().map { gi, g -> StandingGroup in
        let rows = g.entries.enumerated().compactMap { i, e -> StandingRow? in
            guard let t = e.team, let id = t.id else { return nil }
            return StandingRow(
                id: id,
                rank: Int(e.stat("rank") ?? Double(i + 1)),
                team: TeamRef(id: id, name: t.shortDisplayName ?? t.displayName ?? "—", league: league, logo: t.logoURL?.absoluteString, color: usableHex(t.color, t.alternateColor)),
                played: Int(e.stat("gamesPlayed") ?? 0),
                diff: Int(e.stat("pointDifferential") ?? 0),
                points: Int(e.stat("points") ?? 0),
                won: Int(e.stat("wins") ?? 0), drawn: Int(e.stat("ties") ?? 0), lost: Int(e.stat("losses") ?? 0),
                noteColor: Color(hex: e.noteColor), noteText: e.noteText)
        }.sorted { $0.rank < $1.rank }
        return StandingGroup(id: gi, name: g.name, rows: rows)
    }.filter { !$0.rows.isEmpty }
}

/// Tableau de classement façon FotMob (#, équipe, J, +/-, Pts).
struct StandingsTable: View {
    let league: String
    var highlight: Set<String> = []
    var highlightColors: [String: Color] = [:]
    var compact = false
    var preloaded: [StandingGroup]? = nil

    @State private var groups: [StandingGroup]? = nil
    @State private var loading = true

    var body: some View {
        VStack(spacing: 16) {
            let gs = preloaded ?? groups ?? []
            ForEach(gs) { g in
                table(g, showName: gs.count > 1)
            }
            if !gs.isEmpty { legend(gs) }
        }
        .overlay {
            if preloaded == nil {
                if loading { ProgressView().padding(.vertical, 40) }
                else if (groups ?? []).isEmpty {
                    ContentUnavailableView("Pas de classement", systemImage: "list.number", description: Text("Cette compétition n’a pas de classement pour le moment."))
                        .padding(.vertical, 20)
                }
            }
        }
        .frame(minHeight: (preloaded == nil && (groups ?? []).isEmpty) ? 220 : 0)
        .task {
            guard preloaded == nil, groups == nil else { return }
            groups = await loadStandings(league)
            loading = false
        }
    }

    private func table(_ g: StandingGroup, showName: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(showName ? (g.name ?? "") : "#").frame(width: showName ? nil : 28, alignment: .leading)
                if showName { Spacer() } else { Text("Équipe").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 34) }
                Text("J").frame(width: 30)
                Text("+/-").frame(width: 40)
                Text("Pts").frame(width: 36)
            }
            .font(.caption.weight(showName ? .semibold : .regular))
            .foregroundStyle(showName ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            ForEach(g.rows) { r in
                NavigationLink(value: Route.team(r.team)) {
                    row(r)
                }
                .buttonStyle(Pressable())
            }
        }
        .padding(.bottom, 6)
        .glassSurface(cornerRadius: 26)
    }

    private func row(_ r: StandingRow) -> some View {
        let hi = highlight.contains(r.id)
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(r.noteColor.map(vivid) ?? .clear).frame(width: 4, height: 22)
                Text("\(r.rank)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: 28, alignment: .leading)
            Logo(url: r.team.logoURL, size: 20).padding(.trailing, 10)
            Text(r.team.name).font(.subheadline.weight(hi ? .semibold : .regular)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(r.played)").frame(width: 30)
            Text(r.diff > 0 ? "+\(r.diff)" : "\(r.diff)").frame(width: 40)
            Text("\(r.points)").fontWeight(.semibold).frame(width: 36)
        }
        .font(.subheadline.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            if hi {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [(highlightColors[r.id] ?? Color.brand).opacity(0.55), (highlightColors[r.id] ?? Color.brand).opacity(0.08)], startPoint: .leading, endPoint: .trailing))
                    .padding(.horizontal, 4)
            }
        }
        .contentShape(Rectangle())
    }

    private func legend(_ gs: [StandingGroup]) -> some View {
        var seen = Set<String>()
        let notes: [Note] = gs.flatMap(\.rows).compactMap { r -> Note? in
            guard let c = r.noteColor, let t = r.noteText, seen.insert(t).inserted else { return nil }
            return Note(color: c, text: t)
        }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(notes) { n in
                HStack(spacing: 8) {
                    Circle().fill(vivid(n.color)).frame(width: 9, height: 9)
                    Text(n.text).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// Couleur de zone franche et saturée (qualification, relégation…), sans dégradé.
func vivid(_ c: Color) -> Color {
    var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(c).getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
    if sat < 0.15 { return Color(white: 0.75) }
    switch h {
    case ..<0.05, 0.92...: return Color(red: 1.0, green: 0.18, blue: 0.22)          // rouge
    case 0.05..<0.13: return Color(red: 1.0, green: 0.55, blue: 0.0)                 // orange
    case 0.13..<0.2: return Color(red: 1.0, green: 0.84, blue: 0.0)                  // jaune
    case 0.2..<0.47: return Color(red: 0.1, green: 0.9, blue: 0.35)                  // vert
    case 0.47..<0.72: return Color(red: 0.15, green: 0.55, blue: 1.0)                // bleu
    default: return Color(hue: Double(h), saturation: 0.85, brightness: 0.95)
    }
}
