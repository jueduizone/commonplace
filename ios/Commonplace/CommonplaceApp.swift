import SwiftUI

@main
struct CommonplaceApp: App {
    @StateObject private var store = ResearchStore()
    @Environment(\.scenePhase) private var scene
    @AppStorage("offlineExplanationRead") private var onboarded = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(PaperTheme.rubric)
                .preferredColorScheme(nil)
                .task { await store.start() }
                .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
                    OfflineWelcome { onboarded = true }
                }
                .alert("Commonplace", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK") { store.error = nil }
                } message: { Text(store.error ?? "") }
                .onChange(of: scene) { _, phase in store.sceneChanged(active: phase == .active) }
        }
    }
}
