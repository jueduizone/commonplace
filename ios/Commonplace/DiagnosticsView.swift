import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsView: View {
    @EnvironmentObject private var store: ResearchStore
    @State private var probing = false
    @State private var evaluation = false
    @State private var coolStartConfirmed = false
    @State private var mode: String = "accuracy"
    var body: some View {
        Form {
            Section("This device") {
                LabeledContent("Build", value: store.build)
                LabeledContent("Available to this process", value: size(CPAvailableMemory()))
                LabeledContent("Physical footprint", value: size(CPPhysicalFootprint()))
                LabeledContent("Resident memory", value: size(CPResidentMemory()))
                LabeledContent("Background work", value: store.background.status)
                Text("Available memory is headroom for this process, not installed RAM. Physical footprint and resident size measure different things.").font(.caption)
                Button("Capture memory sample") { store.capture("manual"); store.exportDiagnostics() }
            }
            Section("Model memory experiment") {
                Toggle("Memory-map weights on the next load", isOn: $store.useMmap).disabled(store.busy)
                Text("Experimental. Unload the model, capture a sample, ask the same question, then export the samples. Compare resident weights and mmap on a physical iPhone; mapped weights can still count against jetsam limits.").font(.caption)
                Button("Unload model", action: store.unloadModel).disabled(store.busy)
            }
            Section("Files experiment") {
                Button("Probe a local file in place") { probing = true }.disabled(store.busy)
                Text("Choose the large file in Files. This maps it without copying and touches at most 64 MiB spread across it. An unavailable cloud-only file fails rather than downloading inside the app.").font(.caption)
            }
            Section("Accuracy and speed") {
                Picker("Run type", selection: $mode) { Text("Accuracy").tag("accuracy"); Text("Speed").tag("speed") }.pickerStyle(.segmented)
                if mode == "speed" { Toggle("I measured a cool start (≤34 °C)", isOn: $coolStartConfirmed) }
                Button("Choose a question set and run") { evaluation = true }.disabled(store.busy || !store.ready)
                Text(mode == "accuracy" ? "Use eval question sets only for accuracy. Export the answers for the existing judge and release gate. The locked test split is for reporting, never tuning." : "Use scripts/bench/perf.jsonl only, without a judge, starting on a cool physical phone (≤34 °C). iOS thermal state does not report that temperature; verify it separately.").font(.caption)
            }
            if !store.diagnosticText.isEmpty { Section("Result") { Text(store.diagnosticText).font(.callout).textSelection(.enabled) } }
            Section("Export") {
                Button("Prepare device report", action: store.exportDiagnostics)
                if let url = store.exportURL {
                    if let metadata = store.exportMetadataURL {
                        ShareLink(items: [url, metadata]) { Label("Share answers & metadata", systemImage: "square.and.arrow.up") }
                    } else {
                        ShareLink(item: url) { Label("Share prepared report", systemImage: "square.and.arrow.up") }
                    }
                }
                Text("Device reports omit your questions and answers. Accuracy and speed exports include them; share those only when you intend to.").font(.caption)
            }
        }.navigationTitle("Diagnostics").navigationBarTitleDisplayMode(.inline).scrollContentBackground(.hidden).background(PaperTheme.paper)
            .fileImporter(isPresented: $probing, allowedContentTypes: [.data]) { result in
                switch result { case .success(let url): store.probe(url); case .failure(let error): store.error = error.localizedDescription }
            }
            .fileImporter(isPresented: $evaluation, allowedContentTypes: [.data, .json]) { result in
                switch result { case .success(let url): store.runQuestions(url, mode: mode, coolStartConfirmed: coolStartConfirmed); case .failure(let error): store.error = error.localizedDescription }
            }
    }
    private func size(_ n: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: n), countStyle: .memory) }
}
