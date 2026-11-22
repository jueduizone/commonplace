import Foundation
import CryptoKit
import PDFKit
import Darwin

struct CoreFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The blocking Rust API runs on a serial actor, away from SwiftUI's main actor.
actor CoreWorker {
    private var engine: CommonplaceEngine?
    private var loadedPack: String?
    private var mmap = false
    private var bookmarks: PackBookmarks?
    let root: URL

    init(root: URL) { self.root = root }

    func start() throws -> (CommonplaceEngine, LibraryInfo, [String]) {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Makes the app's local Files location available for deliberate USB/Files transfers.
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        var protectedDocuments = documents
        var documentValues = URLResourceValues(); documentValues.isExcludedFromBackup = true
        try protectedDocuments.setResourceValues(documentValues)
        var protectedRoot = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedRoot.setResourceValues(values)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: root.path)
        let bookmarkStore = PackBookmarks(file: root.appendingPathComponent("pack-bookmarks.json"))
        let unavailable = try bookmarkStore.restore()
        bookmarks = bookmarkStore
        let encoders = Bundle.main.url(forResource: "Encoders", withExtension: nil) ?? root.appendingPathComponent("encoders")
        let core = try CommonplaceEngine(opts: EngineOptions(
            dataDir: root.path, encodersDir: encoders.path,
            leafModel: "onnx/model_quantized.onnx", ettinModel: "onnx/model_sel8.onnx",
            encoderThreads: 4, llmThreads: 4, pinBigCores: false))
        engine = core
        return (core, core.library(), unavailable)
    }

    private func core() throws -> CommonplaceEngine {
        guard let engine else { throw CoreFailure(message: "The library is still starting. Try again in a moment.") }
        return engine
    }

    func library() throws -> LibraryInfo { try core().library() }
    func mountedIDs() -> Set<String> { bookmarks?.mountedIDs ?? [] }

    func loadModel(preferred: String?, useMmap: Bool) throws -> String {
        let e = try core()
        if let loadedPack, (preferred == nil || preferred == loadedPack), mmap == useMmap, e.modelStatus().loaded { return e.modelStatus().id }
        e.unloadModel()
        loadedPack = nil
        let candidates = e.library().models.map { ModelCandidate(id: $0.packId, file: $0.filePath, bytes: $0.sizeBytes) }
        guard candidates.contains(where: \.supported) else { return "Search only · import a MiniCPM5-2B or Gemma E2B GGUF model pack" }
        let available = CPAvailableMemory()
        guard let chosen = ModelPolicy.select(candidates, available: available, preferred: preferred) else {
            throw CoreFailure(message: "The selected model does not fit the current available-memory estimate. Close other apps or choose a smaller model. Available: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: available), countStyle: .memory)).")
        }
        e.setModelMmap(enabled: useMmap)
        let status = try e.loadModelPack(packId: chosen.id)
        loadedPack = chosen.id
        mmap = useMmap
        return status.id
    }

    func ask(_ input: AskInput, listener: AskListener) throws -> AskResult { try core().ask(input: input, listener: listener) }
    func unload() { engine?.unloadModel(); loadedPack = nil }

    func importPacks(_ urls: [URL], listener: ImportListener) throws -> [String] {
        let e = try core()
        var scoped: [URL] = []
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        var parts: [ImportPart] = []
        do {
            for url in urls {
                if url.startAccessingSecurityScopedResource() { scoped.append(url) }
                let fd = Darwin.open(url.path, O_RDONLY)
                guard fd >= 0 else { throw CoreFailure(message: "Cannot open \(url.lastPathComponent): \(String(cString: strerror(errno))). Download it fully in Files and try again.") }
                var info = stat()
                guard fstat(fd, &info) == 0, info.st_size >= 0 else { Darwin.close(fd); throw CoreFailure(message: "Cannot read the selected file size.") }
                parts.append(ImportPart(name: url.lastPathComponent, fd: fd, size: UInt64(info.st_size), sha256: nil))
            }
        } catch {
            for part in parts { Darwin.close(part.fd) }
            throw error
        }
        // From this call onwards Rust owns every descriptor, including on failure.
        return try e.importPack(parts: parts, listener: listener)
    }

    func mount(_ url: URL) throws -> String {
        // Sandbox-owned folders need no security scope; actual file reads still enforce access.
        let scoped = url.startAccessingSecurityScopedResource()
        var transferred = false
        defer { if scoped && !transferred { url.stopAccessingSecurityScopedResource() } }
        let e = try core()
        let id = try e.mountPack(directory: url.path)
        do { try bookmarks?.keep(url, id: id, scoped: scoped); transferred = true }
        catch { try? e.removePack(packId: id); throw error }
        return id
    }

    func addDocument(_ url: URL, listener: ImportListener) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let pages: [String]
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url), !document.isLocked else { throw CoreFailure(message: "This PDF is locked or unreadable. Export an unlocked text PDF first.") }
            pages = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        } else {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 20_000_000 else { throw CoreFailure(message: "This text file is larger than 20 MB. Split it into smaller documents first.") }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else { throw CoreFailure(message: "Save the document as UTF-8 text and try again.") }
            pages = text.components(separatedBy: "\u{c}")
        }
        guard pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw CoreFailure(message: "No selectable text was found. Scanned PDFs need text recognition before import.") }
        return try core().addDocument(title: url.deletingPathExtension().lastPathComponent, pages: pages, listener: listener)
    }

    func setEnabled(_ id: String, enabled: Bool) throws { try core().setPackEnabled(packId: id, enabled: enabled) }
    func remove(_ id: String) throws { try core().removePack(packId: id); try bookmarks?.remove(id); loadedPack = nil }
    func verify(_ id: String) throws -> [String] { try core().verifyPack(packId: id) }
    func passage(_ source: SourceRecord) throws -> PassageView { try core().passage(packId: source.packID, passageId: source.passageID) }
    func article(_ source: SourceRecord) throws -> ArticleView { try core().article(packId: source.packID, articleId: source.articleID) }
    func notice(_ id: String) throws -> String { try core().packNotice(packId: id) }
    func deviceInfo() throws -> DeviceInfo { try core().deviceInfo() }
    func telemetry() throws -> URL { URL(fileURLWithPath: try core().telemetryPath()) }
    func evalAssetMetadata() throws -> EvalAssetMetadata {
        let e = try core()
        var hashes: [String: String] = [:]
        var modelHash = "", modelFile = ""
        for id in e.library().buildDates.keys {
            let directory = root.appendingPathComponent("library/packs").appendingPathComponent(id)
            let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
            hashes[id] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if id == loadedPack,
               let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let model = manifest["model"] as? [String: Any], let filename = model["file"] as? String,
               let files = manifest["files"] as? [[String: Any]],
               let file = files.first(where: { $0["path"] as? String == filename }) {
                modelFile = filename; modelHash = file["sha256"] as? String ?? ""
            }
        }
        return EvalAssetMetadata(modelFile: modelFile, modelSHA256: modelHash, packManifests: hashes)
    }

    func updateSettings(threads: UInt32, maxTokens: UInt32, thinkBudget: UInt32) throws {
        let e = try core()
        var settings = e.settings()
        settings.llmThreads = threads
        settings.maxAnswerTokens = maxTokens
        settings.thinkBudget = thinkBudget
        e.updateSettings(n: settings)
    }
}

extension SourceRecord {
    init(_ source: SourceItem) {
        number = source.n; packID = source.packId; passageID = source.passageId; articleID = source.articleId
        title = source.title; section = source.section; snippet = source.snippet; license = source.license; sourceURL = source.sourceUrl
    }
    var ffi: SourceItem { SourceItem(n: number, packId: packID, packTitle: "", passageId: passageID, articleId: articleID, title: title, section: section, snippet: snippet, license: license, sourceUrl: sourceURL) }
}

extension SegmentRecord {
    init(_ segment: AnswerSegment) {
        switch segment {
        case .text(let text): self.init(kind: .text, text: text)
        case .unverified(let text): self.init(kind: .unverified, text: text)
        case .cite(let n): self.init(kind: .citation, text: "[\(n)]", number: n)
        }
    }
}
