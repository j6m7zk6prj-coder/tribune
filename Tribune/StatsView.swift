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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
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
            .padding(.bottom, 8)
        }
        .glassSurface(cornerRadius: 26, wash: [colors.0, colors.1], washOpacity: 0.12)
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
    @State private var shown = false

    var body: some View {
        let total = max(home + away, 1)
        let share = shown ? home / total : 0.5
        VStack(spacing: 8) {
            Text("Possession").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            GeometryReader { g in
                HStack(spacing: 4) {
                    Text("\(Int(home.rounded())) %")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.leading, 14)
                        .frame(width: max(g.size.width * share - 2, 0), alignment: .leading)
                        .frame(maxHeight: .infinity)
                        .background(LinearGradient(colors: [homeColor, homeColor.opacity(0.65)], startPoint: .leading, endPoint: .trailing))
                    Text("\(Int(away.rounded())) %")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.trailing, 14)
                        .frame(width: max(g.size.width * (1 - share) - 2, 0), alignment: .trailing)
                        .frame(maxHeight: .infinity)
                        .background(LinearGradient(colors: [awayColor.opacity(0.65), awayColor], startPoint: .leading, endPoint: .trailing))
                }
                .clipShape(Capsule())
            }
            .frame(height: 36)
        }
        .onAppear { withAnimation(.smooth(duration: 0.9).delay(0.1)) { shown = true } }
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
    @State private var shown = false

    var body: some View {
        let homeLeads = lowerIsBetter ? homeValue < awayValue : homeValue > awayValue
        let awayLeads = lowerIsBetter ? awayValue < homeValue : awayValue > homeValue
        let total = homeValue + awayValue
        let hShare = total > 0 ? homeValue / total : 0.5
        VStack(spacing: 7) {
            HStack {
                Text(home)
                    .font(.subheadline.weight(homeLeads ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(homeLeads ? Color.primary : Color.secondary)
                Spacer()
                Text(label).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
                Text(away)
                    .font(.subheadline.weight(awayLeads ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(awayLeads ? Color.primary : Color.secondary)
            }
            GeometryReader { g in
                let half = g.size.width / 2 - 2
                HStack(spacing: 4) {
                    ZStack(alignment: .trailing) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule()
                            .fill(LinearGradient(colors: [homeColor.opacity(0.5), homeColor], startPoint: .leading, endPoint: .trailing))
                            .frame(width: shown ? half * min(hShare * 2, 1) : 0)
                            .opacity(homeLeads ? 1 : 0.55)
                    }
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule()
                            .fill(LinearGradient(colors: [awayColor, awayColor.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: shown ? half * min((1 - hShare) * 2, 1) : 0)
                            .opacity(awayLeads ? 1 : 0.55)
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear { withAnimation(.smooth(duration: 0.8).delay(0.15)) { shown = true } }
    }
}
