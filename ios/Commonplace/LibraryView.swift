import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var store: ResearchStore
    let onAsk: (String, String) -> Void
    @State private var importKind: ImportKind = .packs
    @State private var importing = false
    @State private var removing: String?
    @State private var noticeID: String?

    var body: some View {
        List {
            Section {
                Menu {
                    Button("Import downloaded packs", systemImage: "archivebox") { pick(.packs) }
                    Button("Open an unpacked pack folder in place", systemImage: "folder") { pick(.folder) }
                    Button("Add a document", systemImage: "doc.badge.plus") { pick(.document) }
                } label: { Label("Add to your library", systemImage: "plus") }.disabled(!store.ready || store.busy)
                Link(destination: URL(string: "https://huggingface.co/datasets/0xPD33/commonplace-packs")!) {
                    Label("Get packs in your browser", systemImage: "arrow.up.right.square")
                }
                Text("Downloads open in your browser. Commonplace imports local files and never downloads packs itself.").font(.caption).foregroundStyle(PaperTheme.secondary)
            }
            if store.busy {
                Section {
                    Text(store.status).font(.callout)
                    if let progress = store.importProgress { ProgressView(value: progress) } else { ProgressView() }
                }
            }
            if !store.diagnosticText.isEmpty { Section("Last check") { Text(store.diagnosticText).font(.callout).textSelection(.enabled) } }
            if let library = store.library {
                Section("Storage") {
                    ProgressView(value: Double(min(library.totalBytes, library.capBytes)), total: Double(max(library.capBytes, 1)))
                    Text("\(size(library.totalBytes)) of \(size(library.capBytes)) · mounted folders are included").font(.caption).foregroundStyle(PaperTheme.secondary)
                }
                if library.packs.isEmpty && library.models.isEmpty {
                    Section {
                        ContentUnavailableView("Build your pocket library", systemImage: "books.vertical", description: Text("Import a pack you downloaded, or add a text PDF. Files must be available on this device before you go offline."))
                    }
                }
                Section("Reference works & documents") {
                    ForEach(library.packs, id: \.packId) { pack in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: Binding(get: { pack.enabled }, set: { store.setEnabled(pack.packId, $0) })) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(pack.title).font(.headline)
                                    Text("\(size(pack.sizeBytes)) · \(pack.license)").font(.caption).foregroundStyle(PaperTheme.secondary)
                                    if store.mountedIDs.contains(pack.packId) { Label("Opened in place", systemImage: "folder").font(.caption) }
                                }
                            }.disabled(store.busy)
                            HStack {
                                Button("Ask this \(pack.userDocument ? "document" : "pack")") { onAsk(pack.packId, pack.title) }.disabled(store.busy)
                                Spacer()
                                packMenu(pack.packId)
                            }.font(.subheadline).frame(minHeight: 44)
                        }.padding(.vertical, 4)
                    }
                    if library.hasWikidata {
                        Toggle("Wikidata facts", isOn: Binding(get: { library.wikidataEnabled }, set: { store.setEnabled("wikidata-facts", $0) })).disabled(store.busy)
                        packMenu("wikidata-facts")
                    }
                }
                Section("Answer models") {
                    ForEach(library.models, id: \.packId) { model in
                        let candidate = ModelCandidate(id: model.packId, file: model.filePath, bytes: model.sizeBytes)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.title).font(.headline)
                            Text("\(size(model.sizeBytes)) · \(model.license)").font(.caption).foregroundStyle(PaperTheme.secondary)
                            if !candidate.supported { Text("Unavailable on iOS. Use a MiniCPM5-2B or Gemma E2B GGUF pack.").font(.caption) }
                            packMenu(model.packId)
                        }.padding(.vertical, 4)
                    }
                }
                if !library.skipped.isEmpty {
                    Section("Needs attention") {
                        ForEach(library.skipped, id: \.packId) { pack in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(pack.packId).font(.headline)
                                Text(pack.reason).font(.caption)
                                Text("If a mounted folder moved, reselect it in Files after removing this entry.").font(.caption).foregroundStyle(PaperTheme.secondary)
                                packMenu(pack.packId)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(PaperTheme.paper).navigationTitle("Library")
        .fileImporter(isPresented: $importing, allowedContentTypes: types, allowsMultipleSelection: importKind != .folder) { result in
            switch result { case .success(let urls): store.importFiles(urls, kind: importKind); case .failure(let error): store.error = error.localizedDescription }
        }
        .confirmationDialog("Remove this pack?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove from library", role: .destructive) { if let id = removing { store.removePack(id) }; removing = nil }
        } message: { Text("Imported files are deleted. For a folder opened in place, only its library link is removed; the original stays in Files.") }
        .sheet(item: Binding(get: { noticeID.map(NoticeID.init) }, set: { noticeID = $0?.id })) { id in NoticeView(id: id.id).environmentObject(store) }
    }

    private var types: [UTType] {
        switch importKind {
        case .folder: [.folder]
        case .document: [.pdf, .plainText, UTType(filenameExtension: "md") ?? .text]
        case .packs: [.data, .archive, .json]
        }
    }
    private func pick(_ kind: ImportKind) { importKind = kind; importing = true }
    private func size(_ bytes: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file) }
    private func packMenu(_ id: String) -> some View {
        Menu {
            Button("Verify files", systemImage: "checkmark.shield") { store.verifyPack(id) }
            Button("Credits & license", systemImage: "doc.text") { noticeID = id }
            Button("Remove", systemImage: "trash", role: .destructive) { removing = id }
        } label: { Label("Pack details", systemImage: "ellipsis.circle").frame(minHeight: 44) }.disabled(store.busy)
    }
}

private struct NoticeID: Identifiable { var id: String; init(_ id: String) { self.id = id } }
struct NoticeView: View {
    @EnvironmentObject private var store: ResearchStore
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var notice = "Loading…"
    var body: some View {
        NavigationStack {
            ScrollView { Text(notice).textSelection(.enabled).padding(20).frame(maxWidth: 740, alignment: .leading).frame(maxWidth: .infinity) }
                .background(PaperTheme.paper).navigationTitle("Credits & license").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
                .task { do { let text = try await store.worker.notice(id); notice = text.isEmpty ? "No NOTICE.txt is installed for this pack." : text } catch { notice = error.localizedDescription } }
        }
    }
}
