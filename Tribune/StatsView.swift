import SwiftUI

struct StatsView: View {
    let match: Match
    let teams: [BoxTeam]

    /// Statistiques affichées, dans l'ordre de FotMob.
    static let wanted: [StatDef] = [
        .init(key: "totalShots", label: "Tirs"),
        .init(key: "shotsOnTarget", label: "Tirs cadrés"),
        .init(key: "blockedShots", label: "Tirs contrés"),
        .init(key: "totalPasses", label: "Passes"),
        .init(key: "accuratePasses", label: "Passes réussies"),
        .init(key: "passPct", label: "Précision des passes"),
        .init(key: "wonCorners", label: "Corners"),
        .init(key: "offsides", label: "Hors-jeu"),
        .init(key: "foulsCommitted", label: "Fautes"),
        .init(key: "yellowCards", label: "Cartons jaunes"),
        .init(key: "redCards", label: "Cartons rouges"),
        .init(key: "totalTackles", label: "Tacles"),
        .init(key: "interceptions", label: "Interceptions"),
        .init(key: "totalClearance", label: "Dégagements"),
        .init(key: "saves", label: "Arrêts"),
        .init(key: "totalCrosses", label: "Centres"),
        .init(key: "totalLongBalls", label: "Longs ballons"),
    ]

    private var home: BoxTeam? { teams.first { $0.homeAway == "home" || $0.team?.id == match.home.id } ?? teams.first }
    private var away: BoxTeam? { teams.first { $0.homeAway == "away" || $0.team?.id == match.away.id } ?? teams.last }

    var body: some View {
        let colors = teamColors(match)
        VStack(spacing: 0) {
            HStack {
                Logo(url: match.home.logo, size: 24)
                Spacer()
                Text("Statistiques").font(.subheadline.weight(.semibold))
                Spacer()
                Logo(url: match.away.logo, size: 24)
            }
            .padding(14)

            if let h = value(home, "possessionPct"), let a = value(away, "possessionPct") {
                PossessionBar(home: h, away: a, homeColor: colors.0, awayColor: colors.1)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            ForEach(Self.wanted) { def in
                let key = def.key, label = def.label
                if let hs = display(home, key), let aws = display(away, key) {
                    StatRow(label: label, home: hs, away: aws,
                            homeValue: value(home, key) ?? 0, awayValue: value(away, key) ?? 0,
                            lowerIsBetter: ["foulsCommitted", "yellowCards", "redCards", "offsides"].contains(key),
                            homeColor: colors.0, awayColor: colors.1)
                }
            }
            .padding(.bottom, 6)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    func raw(_ t: BoxTeam?, _ k: String) -> String? { t?.statistics.first { $0.name == k }?.displayValue }

    func value(_ t: BoxTeam?, _ k: String) -> Double? {
        guard let s = raw(t, k) else { return nil }
        guard var v = Double(s.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) else { return nil }
        if k.hasSuffix("Pct") && v <= 1 { v *= 100 }
        return v
    }

    func display(_ t: BoxTeam?, _ k: String) -> String? {
        guard let v = value(t, k) else { return nil }
        if k.hasSuffix("Pct") { return "\(Int(v.rounded())) %" }
        return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

struct StatDef: Identifiable { let key: String; let label: String; var id: String { key } }

struct PossessionBar: View {
    let home: Double
    let away: Double
    let homeColor: Color
    let awayColor: Color
    var body: some View {
        let total = max(home + away, 1)
        VStack(spacing: 8) {
            Text("Possession").font(.footnote).foregroundStyle(.secondary)
            GeometryReader { g in
                HStack(spacing: 3) {
                    Text("\(Int(home.rounded())) %")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.leading, 10)
                        .frame(width: max(g.size.width * home / total - 1.5, 0), alignment: .leading)
                        .frame(maxHeight: .infinity)
                        .background(homeColor)
                    Text("\(Int(away.rounded())) %")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.trailing, 10)
                        .frame(width: max(g.size.width * away / total - 1.5, 0), alignment: .trailing)
                        .frame(maxHeight: .infinity)
                        .background(awayColor)
                }
                .clipShape(Capsule())
            }
            .frame(height: 28)
        }
    }
}

struct StatRow: View {
    let label: String
    let home: String
    let away: String
    let homeValue: Double
    let awayValue: Double
    let lowerIsBetter: Bool
    let homeColor: Color
    let awayColor: Color

    var body: some View {
        let homeLeads = lowerIsBetter ? homeValue < awayValue : homeValue > awayValue
        let awayLeads = lowerIsBetter ? awayValue < homeValue : awayValue > homeValue
        HStack {
            pill(home, lead: homeLeads, color: homeColor)
            Spacer()
            Text(label).font(.subheadline).multilineTextAlignment(.center)
            Spacer()
            pill(away, lead: awayLeads, color: awayColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    func pill(_ s: String, lead: Bool, color: Color) -> some View {
        Text(s)
            .font(.subheadline.weight(lead ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(lead ? .white : .primary)
            .padding(.horizontal, 9)
            .frame(minWidth: 40, minHeight: 26)
            .background(Capsule().fill(lead ? color : .clear))
    }
}
