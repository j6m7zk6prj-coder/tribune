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
    let league: String
    var size: CGFloat = 20
    var body: some View {
        if let u = store.logo(for: league) {
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

/// Ligne d'en-tête d'une compétition dans la liste des matchs.
struct LeagueHeaderRow: View {
    let league: String
    let name: String
    var body: some View {
        HStack(spacing: 10) {
            LeagueLogo(league: league, size: 20)
            Text(name).font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
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
