import SwiftUI

// MARK: - Logos

struct Logo: View {
    let url: URL?
    var size: CGFloat = 24
    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            if let img = phase.image {
                img.resizable().interpolation(.high).scaledToFit()
            } else {
                Circle().fill(Color(.tertiarySystemFill)).padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct LeagueLogo: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let league: String
    var size: CGFloat = 20
    var body: some View {
        if let u = store.logo(for: league, dark: scheme == .dark) {
            Logo(url: u, size: size)
        } else {
            Image(systemName: "trophy.fill")
                .font(.system(size: size * 0.6))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Ligne de match (liste)

struct MatchRow: View {
    let match: Match
    var showStatus = true

    var body: some View {
        HStack(spacing: 0) {
            if showStatus {
                Text(match.shortStatus)
                    .font(.caption.weight(match.state == .live ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(match.state == .live ? Color.brand : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 34, alignment: .leading)
            }
            HStack(spacing: 8) {
                Text(match.home.short)
                    .font(.subheadline)
                    .fontWeight(match.state == .post && match.home.winner ? .semibold : .regular)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Logo(url: match.home.logo, size: 22)
            }
            center.frame(width: 64)
            HStack(spacing: 8) {
                Logo(url: match.away.logo, size: 22)
                Text(match.away.short)
                    .font(.subheadline)
                    .fontWeight(match.state == .post && match.away.winner ? .semibold : .regular)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var center: some View {
        if match.hasScore {
            VStack(spacing: 1) {
                Text("\(match.home.score ?? "0") - \(match.away.score ?? "0")")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(match.state == .live ? Color.brand : .primary)
                if let h = match.home.shootout, let a = match.away.shootout {
                    Text("(\(h) - \(a))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        } else if match.state == .off {
            Text(match.kickoff).font(.subheadline.monospacedDigit()).strikethrough().foregroundStyle(.secondary)
        } else {
            Text(match.kickoff).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

/// Carte de match : deux lignes d'équipes, voile aux couleurs des deux clubs.
struct MatchCard: View {
    let match: Match
    var showLeague = false

    var body: some View {
        let colors = teamColors(match)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 11) {
                teamLine(match.home, score: match.home.score, lost: match.state == .post && match.away.winner)
                teamLine(match.away, score: match.away.score, lost: match.state == .post && match.home.winner)
            }
            Capsule().fill(Color.primary.opacity(0.12)).frame(width: 1).padding(.vertical, 2)
            status.frame(width: 62)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassSurface(cornerRadius: 24, wash: [colors.0, colors.1], washOpacity: match.state == .live ? 0.42 : 0.30)
        .overlay {
            if match.state == .live {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.brand.opacity(0.55), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func teamLine(_ s: Side, score: String?, lost: Bool) -> some View {
        HStack(spacing: 11) {
            Logo(url: s.logo, size: 26)
            Text(s.short)
                .font(.body.weight(.semibold))
                .foregroundStyle(lost ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if match.hasScore {
                Text(score ?? "0")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(lost ? Color.secondary : Color.primary)
                    .contentTransition(.numericText())
            }
        }
    }

    @ViewBuilder private var status: some View {
        VStack(spacing: 4) {
            switch match.state {
            case .live:
                HStack(spacing: 5) {
                    LiveDot()
                    Text(match.shortStatus).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Color.brand)
                }
                Text("En direct").font(.caption2).foregroundStyle(.secondary)
            case .post:
                Text(match.shortStatus).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                if let h = match.home.shootout, let a = match.away.shootout {
                    Text("\(h)-\(a) tab").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            case .pre:
                Text(match.kickoff).font(.headline.monospacedDigit())
                if showLeague { Text(match.leagueName).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            case .off:
                Text(match.shortStatus).font(.subheadline).foregroundStyle(.secondary)
                Text(match.kickoff).font(.caption2).strikethrough().foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }
}

/// Ligne d'en-tête d'une compétition dans la liste des matchs.
struct LeagueHeaderRow: View {
    let league: String
    let name: String
    var body: some View {
        HStack(spacing: 10) {
            LeagueLogo(league: league, size: 24)
            Text(name).font(.headline)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
    }
}

/// Ligne cliquable sans chevron (comme FotMob).
struct PlainLink<V: Hashable, Label: View>: View {
    let value: V
    @ViewBuilder let label: () -> Label
    var body: some View {
        ZStack {
            NavigationLink(value: value) { EmptyView() }.opacity(0)
            label()
        }
    }
}

// MARK: - Liquid Glass sur iOS 26, matériaux standard avant

extension View {
    @ViewBuilder func minimizingTabBar() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else { self }
        #else
        self
        #endif
    }

    @ViewBuilder func glassCapsule() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self.background(.regularMaterial, in: Capsule())
        }
        #else
        self.background(.regularMaterial, in: Capsule())
        #endif
    }
}

// MARK: - États vides

struct LoadingOrEmpty: View {
    let loading: Bool
    let empty: Bool
    let failed: Bool
    let emptyTitle: String
    let emptyIcon: String
    var emptyText: String? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        if loading {
            ProgressView().controlSize(.large)
        } else if failed {
            ContentUnavailableView {
                Label("Connexion impossible", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Vérifie ta connexion internet.")
            } actions: {
                if let retry { Button("Réessayer", action: retry) }
            }
        } else if empty {
            ContentUnavailableView(emptyTitle, systemImage: emptyIcon, description: emptyText.map { Text($0) })
        }
    }
}
