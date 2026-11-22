import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ResearchStore
    @State private var showOffline = false
    var body: some View {
        Form {
            Section("Answer model") {
                Picker("Model", selection: $store.preferredModel) {
                    Text("Automatic · available memory").tag("")
                    ForEach((store.library?.models ?? []).filter { ModelCandidate(id: $0.packId, file: $0.filePath, bytes: $0.sizeBytes).supported }, id: \.packId) {
                        Text($0.title).tag($0.packId)
                    }
                }
                Text(store.model).font(.caption).foregroundStyle(PaperTheme.secondary)
                Text("Automatic selection admits only a model estimated to fit os_proc_available_memory. The file size plus 1 GiB is a conservative estimate that still needs validation on each device. Ling is not enabled.").font(.caption)
                Stepper("CPU threads: \(store.threads)", value: $store.threads, in: 2...6)
                Stepper("Thinking budget: \(store.thinkBudget) tokens", value: $store.thinkBudget, in: 64...512, step: 64)
                Button("Unload model", action: store.unloadModel)
            }.disabled(store.busy)
            Section("Privacy") {
                Button("What offline means on iOS") { showOffline = true }
                Text("No network code, analytics or crash-reporting SDKs. Your library and history are excluded from iCloud backup. Sharing a report or answer is an explicit action.").font(.caption)
            }
            Section {
                NavigationLink("Diagnostics & device checks") { DiagnosticsView() }
                NavigationLink("Open-source licenses") { LicenseView() }
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development")
                LabeledContent("Core build", value: store.build)
            }
        }.scrollContentBackground(.hidden).background(PaperTheme.paper).navigationTitle("Settings")
            .sheet(isPresented: $showOffline) { OfflineWelcome { showOffline = false } }
    }
}

struct LicenseView: View {
    @State private var text = "Loading…"
    var body: some View {
        ScrollView { Text(text).font(.callout).textSelection(.enabled).padding(20).frame(maxWidth: 740, alignment: .leading).frame(maxWidth: .infinity) }
            .background(PaperTheme.paper).navigationTitle("Licenses").navigationBarTitleDisplayMode(.inline)
            .task {
                guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") else { text = "License notices are missing from this build."; return }
                text = (try? String(contentsOf: url, encoding: .utf8)) ?? "The notices could not be read."
            }
    }
}
