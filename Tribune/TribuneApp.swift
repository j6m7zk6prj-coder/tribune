import SwiftUI

@main
struct TribuneApp: App {
    @State private var store = AppStore()

    init() {
        // Cache généreux pour les logos des équipes et des compétitions.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if Launch.args.contains("-diag") { DiagView() }
                else if Launch.args.contains("-widgets") { NavigationStack { WidgetPreviewView() } }
                else { RootView() }
            }
                .environment(store)
                .preferredColorScheme(store.appearance.scheme)
                .tint(.brand)
                .fontDesign(.rounded)
        }
    }
}

enum AppTab: String { case matches, leagues, following }

struct RootView: View {
    @State private var tab: AppTab = AppTab(rawValue: Launch.value("-tab") ?? "") ?? .matches

    var body: some View {
        TabView(selection: $tab) {
            MatchesView()
                .tabItem { Label("Matchs", systemImage: "soccerball") }
                .tag(AppTab.matches)
            LeaguesView()
                .tabItem { Label("Ligues", systemImage: "trophy") }
                .tag(AppTab.leagues)
            FollowingView()
                .tabItem { Label("Suivis", systemImage: "star") }
                .tag(AppTab.following)
        }
        .minimizingTabBar()
    }
}
