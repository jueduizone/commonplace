import Combine
import Foundation
import CryptoKit
import UIKit

@MainActor
final class ResearchStore: ObservableObject {
    @Published var ready = false
    @Published var library: LibraryInfo?
    @Published var conversation = ConversationRecord()
    @Published var history: [ConversationRecord] = []
    @Published var input = ""
    @Published var busy = false
    @Published var cancellable = false
    @Published var status = "Opening your library…"
    @Published var error: String?
    @Published var card: AnswerCard?
    @Published var model = "No model loaded"
    @Published var thinking = false
    @Published var importProgress: Double?
    @Published var mountedIDs: Set<String> = []
    @Published var build = "Starting"
    @Published var diagnosticText = ""
    @Published var exportURL: URL?
    @Published var exportMetadataURL: URL?
    @Published var preferredModel: String { didSet { UserDefaults.standard.set(preferredModel, forKey: "model") } }
    @Published var useMmap: Bool { didSet { UserDefaults.standard.set(useMmap, forKey: "mmap") } }
    @Published var threads: Int { didSet { UserDefaults.standard.set(threads, forKey: "threads") } }
    @Published var thinkBudget: Int { didSet { UserDefaults.standard.set(thinkBudget, forKey: "thinkBudget") } }
    let worker: CoreWorker
    let background = ContinuedWork()
    let root: URL
    private let storage: ConversationStorage
    private var core: CommonplaceEngine?
    private var task: Task<Void, Never>?
    private var streamID: UUID?
    private var snapshots: [DeviceSnapshot] = []
    private var lastTiming: Timing?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Commonplace", isDirectory: true)
        worker = CoreWorker(root: root)
        storage = ConversationStorage(directory: root.appendingPathComponent("conversations"))
        preferredModel = UserDefaults.standard.string(forKey: "model") ?? ""
        useMmap = UserDefaults.standard.bool(forKey: "mmap")
        threads = max(2, min(6, UserDefaults.standard.integer(forKey: "threads") == 0 ? 4 : UserDefaults.standard.integer(forKey: "threads")))
        thinkBudget = max(64, min(512, UserDefaults.standard.integer(forKey: "thinkBudget") == 0 ? 256 : UserDefaults.standard.integer(forKey: "thinkBudget")))
        background.cancel = { [weak self] in self?.stop() }
        background.register()
    }

    func start() async {
        guard !ready else { return }
        do {
            let (engine, lib, unavailable) = try await worker.start()
            core = engine; library = lib; mountedIDs = await worker.mountedIDs()
            build = try await worker.deviceInfo().build
            history = try storage.all()
            ready = true; status = "Ready"
            if !unavailable.isEmpty { error = "Files access expired for \(unavailable.joined(separator: ", ")). Remove the unavailable entry, then open the pack folder again." }
            capture("launch")
        } catch { self.error = error.localizedDescription; status = "Library could not start" }
    }

    func ask(_ text: String? = nil) {
        let query = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard ready, !busy, !query.isEmpty else { return }
        if text == nil { input = "" }
        busy = true; cancellable = true; card = nil; status = "Loading model…"; error = nil
        let id = UUID(); streamID = id
        let history = conversation.turns.filter { $0.error == nil && $0.kind != "chat" && !$0.stopped }.suffix(2).map {
            TurnRecord(query: $0.question, answer: $0.answer, sources: $0.sources.map(\.ffi))
        }
        conversation.turns.append(TurnRecordData(question: query, answer: ""))
        let scope = conversation.scopeID.map { [$0] } ?? []
        let listener = StreamingListener(store: self, id: id)
        background.begin(); capture("before-model-load")
        task = Task {
            var successful = false
            defer {
                if streamID == id { streamID = nil }
                busy = false; cancellable = false; background.end(success: successful)
                persist(); capture("after-answer")
                if UIApplication.shared.applicationState != .active { Task { await worker.unload(); model = "Unloaded while off screen" } }
            }
            do {
                try await worker.updateSettings(threads: UInt32(threads), maxTokens: 400, thinkBudget: UInt32(thinkBudget))
                model = try await worker.loadModel(preferred: preferredModel.isEmpty ? nil : preferredModel, useMmap: useMmap)
                capture("after-model-load")
                try Task.checkCancellation()
                status = "Searching…"
                let result = try await worker.ask(AskInput(query: query, history: history, think: thinking, thermalHeadroom: nil, packs: scope), listener: listener)
                streamID = nil
                guard let index = conversation.turns.indices.last else { return }
                conversation.turns[index].answer = result.answerText
                conversation.turns[index].sources = result.sources.map(SourceRecord.init)
                conversation.turns[index].segments = result.segments.map(SegmentRecord.init)
                conversation.turns[index].kind = result.kind == .chat ? "chat" : (result.kind == .reformat ? "reformat" : "question")
                lastTiming = result.timing; card = result.card
                status = String(format: "%.1f s · %@", result.timing.totalMs / 1000, model)
                successful = !Task.isCancelled
            } catch is CancellationError { status = "Stopped" }
            catch {
                self.error = error.localizedDescription; status = "Answer interrupted"
                if let index = conversation.turns.indices.last { conversation.turns[index].error = error.localizedDescription }
            }
        }
    }

    func stop() {
        core?.cancel(); task?.cancel()
        if let index = conversation.turns.indices.last, busy { conversation.turns[index].stopped = true }
        status = "Stopping…"
    }

    func receive(_ event: StreamEvent, id: UUID) {
        guard streamID == id, let index = conversation.turns.indices.last else { return }
        switch event {
        case .stage(let stage):
            switch stage {
            case .searching: status = "Searching your library…"
            case .reading: status = "Reading the evidence…"
            case .computing: status = "Checking the calculation…"
            case .thinking: status = "Thinking it through…"
            case .writing: status = "Writing an answer…"
            case .done: break
            }
        case .card(let value): card = value
        case .sources(let values): conversation.turns[index].sources = values.map(SourceRecord.init)
        case .thinking(let text): conversation.turns[index].thinking = text
        case .answer(let segments):
            let mapped = segments.map(SegmentRecord.init)
            conversation.turns[index].segments = mapped
            conversation.turns[index].answer = mapped.map(\.text).joined()
            background.progress(characters: conversation.turns[index].answer.count)
        }
    }

    func newTopic(packID: String? = nil, title: String? = nil) {
        guard !busy else { return }
        persist(); conversation = ConversationRecord(scopeID: packID, scopeTitle: title); card = nil; input = ""; status = "Ready"
    }
    func open(_ record: ConversationRecord) { guard !busy else { return }; persist(); conversation = record; card = nil }
    func delete(_ id: UUID) { do { try storage.remove(id); history = try storage.all(); if conversation.id == id { newTopic() } } catch { self.error = error.localizedDescription } }

    private func persist() {
        guard !conversation.turns.isEmpty else { return }
        do { conversation.updated = Date(); try storage.save(conversation); history = try storage.all() }
        catch { self.error = "The conversation could not be saved: \(error.localizedDescription)" }
    }

    func importFiles(_ urls: [URL], kind: ImportKind) {
        guard ready, !busy else { return }
        busy = true; importProgress = nil; status = kind == .folder ? "Verifying pack in place…" : "Importing…"
        let listener = ProgressListener { [weak self] done, total in
            Task { @MainActor in self?.importProgress = total > 0 ? Double(done) / Double(total) : nil }
        }
        task = Task {
            defer { busy = false; importProgress = nil }
            do {
                switch kind {
                case .packs: _ = try await worker.importPacks(urls, listener: listener)
                case .folder: for url in urls { _ = try await worker.mount(url) }
                case .document: for url in urls { _ = try await worker.addDocument(url, listener: listener) }
                }
                library = try await worker.library(); mountedIDs = await worker.mountedIDs(); status = "Library updated"
            } catch {
                library = try? await worker.library()
                self.error = error.localizedDescription; status = "Import could not finish"
            }
        }
    }

    func setEnabled(_ id: String, _ enabled: Bool) { operation { try await self.worker.setEnabled(id, enabled: enabled) } }
    func removePack(_ id: String) { operation { try await self.worker.remove(id); self.model = "No model loaded" } }
    func verifyPack(_ id: String) { operation { let bad = try await self.worker.verify(id); self.diagnosticText = bad.isEmpty ? "All files match their manifest." : "Files that failed verification: \(bad.joined(separator: ", "))" } }
    func unloadModel() { operation { await self.worker.unload(); self.model = "No model loaded" } }

    private func operation(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true
        task = Task {
            defer { busy = false }
            do { try await action() }
            catch { self.error = error.localizedDescription }
            library = try? await worker.library(); mountedIDs = await worker.mountedIDs()
        }
    }

    func sceneChanged(active: Bool) {
        capture(active ? "foreground" : "background")
        if !active { persist(); if !busy { Task { await worker.unload(); model = "Unloaded while off screen" } } }
    }

    func capture(_ phase: String) {
        snapshots.append(.capture(build: build, phase: phase, model: model, mmap: useMmap, background: background.status))
        if snapshots.count > 200 { snapshots.removeFirst() }
    }

    func exportDiagnostics() {
        do {
            capture("export")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("commonplace-device-checks.json")
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshots).write(to: url, options: .atomic); exportURL = url; exportMetadataURL = nil
            diagnosticText = "Export includes device, OS, build, available memory, physical footprint, resident memory, thermal state and foreground/background samples. It contains no questions or answers."
        } catch { self.error = error.localizedDescription }
    }

    func probe(_ url: URL) {
        operation {
            self.capture("before-files-probe")
            let result = try await Task.detached { try FileProbe.read(url) }.value
            self.capture("after-files-probe")
            self.diagnosticText = "Mapped in place: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: result.bytes), countStyle: .file)). Sampled up to \(ByteCountFormatter.string(fromByteCount: Int64(clamping: result.sampledBytes), countStyle: .file)) in \(String(format: "%.1f", result.milliseconds)) ms; checksum \(result.checksum). No copy was made. This is a bounded read probe, not an 11 GB resident-memory test."
        }
    }
}

enum ImportKind { case packs, folder, document }
enum StreamEvent: Sendable { case stage(AskStage), card(AnswerCard), sources([SourceItem]), thinking(String), answer([AnswerSegment]) }

final class StreamingListener: AskListener, @unchecked Sendable {
    private weak var store: ResearchStore?
    private let id: UUID
    init(store: ResearchStore, id: UUID) { self.store = store; self.id = id }
    private func send(_ event: StreamEvent) { Task { @MainActor [weak store, id] in store?.receive(event, id: id) } }
    func onStage(stage: AskStage, detail: String) { send(.stage(stage)) }
    func onCard(card: AnswerCard) { send(.card(card)) }
    func onSources(sources: [SourceItem]) { send(.sources(sources)) }
    func onThinking(text: String, done: Bool) { send(.thinking(text)) }
    func onAnswer(segments: [AnswerSegment], done: Bool) { send(.answer(segments)) }
}

final class ProgressListener: ImportListener, @unchecked Sendable {
    private let progress: @Sendable (UInt64, UInt64) -> Void
    init(_ progress: @escaping @Sendable (UInt64, UInt64) -> Void) { self.progress = progress }
    func onProgress(bytesDone: UInt64, bytesTotal: UInt64) { progress(bytesDone, bytesTotal) }
    func onPartDone(name: String) {}
    func onPack(packId: String) {}
}

extension ResearchStore {
    /// Produces the schema consumed by eval/import.py; never invokes a network judge on the phone.
    func runQuestions(_ url: URL, mode: String, coolStartConfirmed: Bool = false) {
        guard !busy, ready else { return }
        if mode == "speed", !coolStartConfirmed { error = "Measure the phone temperature (≤34 °C) and confirm the cool start before running a speed check."; return }
        busy = true; cancellable = true; status = "Preparing \(mode) run…"; background.begin()
        task = Task {
            var success = false
            defer { busy = false; cancellable = false; background.end(success: success); capture("after-\(mode)-run") }
            do {
                let active = url.startAccessingSecurityScopedResource()
                defer { if active { url.stopAccessingSecurityScopedResource() } }
                let info = try url.resourceValues(forKeys: [.fileSizeKey])
                guard (info.fileSize ?? 0) <= 2_000_000 else { throw CoreFailure(message: "Question sets must be smaller than 2 MB.") }
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else { throw CoreFailure(message: "The question set must be UTF-8 JSONL.") }
                if mode == "speed" {
                    guard let perfURL = Bundle.main.url(forResource: "perf", withExtension: "jsonl"), try Data(contentsOf: perfURL) == data else {
                        throw CoreFailure(message: "Speed checks accept only the unchanged scripts/bench/perf.jsonl set. Accuracy sets must stay separate.")
                    }
                }
                let questions = try text.split(whereSeparator: \.isNewline).map { try JSONDecoder().decode(EvalQuestion.self, from: Data($0.utf8)) }
                guard !questions.isEmpty, Set(questions.map(\.id)).count == questions.count else { throw CoreFailure(message: "The set is empty or contains duplicate question IDs.") }
                try await worker.updateSettings(threads: UInt32(threads), maxTokens: 400, thinkBudget: UInt32(thinkBudget))
                model = try await worker.loadModel(preferred: preferredModel.isEmpty ? nil : preferredModel, useMmap: useMmap)
                guard core?.modelStatus().loaded == true else { throw CoreFailure(message: "Install a supported answer model before running an evaluation.") }
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let output = root.appendingPathComponent("\(mode)-\(stamp).answers.jsonl")
                FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                let handle = try FileHandle(forWritingTo: output)
                defer { try? handle.close(); exportURL = output }
                let assets = try await worker.evalAssetMetadata()
                let executable = try Data(contentsOf: Bundle.main.executableURL!, options: .mappedIfSafe)
                var answered = 0
                var complete = false
                var meta: [String: Any] = ["mode": mode, "build": build, "model": model, "mmap": useMmap,
                    "model_file": assets.modelFile, "model_sha256": assets.modelSHA256,
                    "model_hash_source": "verified pack manifest", "pack_manifest_sha256": assets.packManifests,
                    "binary_sha256": SHA256.hash(data: executable).map { String(format: "%02x", $0) }.joined(),
                    "questions_sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                    "requested": questions.count,
                    "device": DeviceSnapshot.capture(build: build, phase: "\(mode)-start", model: model, mmap: useMmap, background: background.status).device,
                    "os": UIDevice.current.systemVersion, "questions_file": url.lastPathComponent,
                    "cool_start_confirmed": coolStartConfirmed, "threads": threads,
                    "packs": (library?.buildDates ?? [:]), "physical_device": !Self.isSimulator]
                let metaURL = output.appendingPathExtension("meta.json")
                exportMetadataURL = metaURL
                defer {
                    meta["answered"] = answered; meta["complete"] = complete
                    try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]).write(to: metaURL, options: .atomic)
                }
                try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]).write(to: metaURL, options: .atomic)
                capture("before-\(mode)-run")
                for (index, question) in questions.enumerated() {
                    try Task.checkCancellation()
                    status = "\(mode.capitalized): \(index + 1) of \(questions.count)"
                    let turns = (question.history ?? []).map { TurnRecord(query: $0.query, answer: $0.answer, sources: []) }
                    let result = try await worker.ask(AskInput(query: question.query, history: turns, think: false, thermalHeadroom: nil, packs: []), listener: SilentListener())
                    let segments: [[String: Any]] = result.segments.map {
                        switch $0 { case .text(let text): return ["Text": text]; case .unverified(let text): return ["Unverified": text]; case .cite(let n): return ["Cite": n] }
                    }
                    let sources: [[String: Any]] = result.sources.map { ["n": $0.n, "pack_id": $0.packId, "passage_id": $0.passageId, "article_id": $0.articleId, "title": $0.title, "section": $0.section, "snippet": $0.snippet, "license": $0.license, "source_url": $0.sourceUrl] }
                    let timing = result.timing
                    var record: [String: Any] = ["build": build, "model_id": model, "card_ms": timing.cardMs,
                        "total_ms": timing.totalMs, "peak_rss_mb": timing.peakRssMb,
                        "unverified_sentences": segments.filter { $0["Unverified"] != nil }.count,
                        "physical_footprint_bytes": CPPhysicalFootprint(),
                        "foreground": UIApplication.shared.applicationState == .active,
                        "synthesis": ["gen_tokens": timing.genTokens, "prompt_tokens": timing.promptTokens, "cached_tokens": timing.cachedTokens]]
                    if let first = timing.ttftMs { record["ttft_ms"] = first }
                    if let rate = timing.decodeTps { record["decode_tps"] = rate }
                    let row: [String: Any] = ["id": question.id, "query": question.query, "answer": result.answerText, "segments": segments, "sources": sources, "record": record]
                    var encoded = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]); encoded.append(10)
                    try handle.write(contentsOf: encoded); try handle.synchronize(); answered += 1
                    capture("\(mode)-question-\(index + 1)")
                    background.progress(characters: (index + 1) * 1_600 / questions.count)
                }
                diagnosticText = "Completed \(questions.count) \(mode) questions on \(Self.isSimulator ? "a simulator" : "this physical device"). Share the answer file and its metadata. \(mode == "accuracy" ? "Import it with eval/import.py and run the judge, abstention checks and gate on the desktop." : "No judge was used. Compare interleaved runs from cool starts.")"
                try Task.checkCancellation()
                exportURL = output; complete = true; success = true; status = "Run finished"
            } catch is CancellationError { diagnosticText = "Stopped. The answer file contains only completed questions."; status = "Stopped" }
            catch { self.error = error.localizedDescription; status = "Run interrupted" }
        }
    }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}

final class SilentListener: AskListener, @unchecked Sendable {
    func onStage(stage: AskStage, detail: String) {}
    func onCard(card: AnswerCard) {}
    func onSources(sources: [SourceItem]) {}
    func onThinking(text: String, done: Bool) {}
    func onAnswer(segments: [AnswerSegment], done: Bool) {}
}
