import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section {
                    Picker("Apparence", selection: $store.appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                }
                ForEach(CompGroup.allCases) { g in
                    Section {
                        ForEach(Competition.all.filter { $0.group == g }) { c in
                            Toggle(isOn: binding(c.id)) {
                                HStack(spacing: 12) {
                                    LeagueLogo(league: c.id, size: 24)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(c.name)
                                        Text(c.area).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(.brand)
                        }
                    } header: {
                        Text(g.rawValue)
                    } footer: {
                        if g == .top { Text("Choisis les compétitions affichées dans l’onglet Matchs.") }
                    }
                }
                Section {
                    Text("Données : ESPN. Scores mis à jour toutes les 30 secondes pendant les matchs.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Compétitions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
        }
    }

    func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { store.enabled.contains(id) },
                set: { on in if on { store.enabled.insert(id) } else { store.enabled.remove(id) } })
    }
}
