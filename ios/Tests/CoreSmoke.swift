import Foundation

final class SmokeProgress: ImportListener, @unchecked Sendable {
    func onProgress(bytesDone: UInt64, bytesTotal: UInt64) {}
    func onPartDone(name: String) {}
    func onPack(packId: String) {}
}
final class SmokeListener: AskListener, @unchecked Sendable {
    func onStage(stage: AskStage, detail: String) {}
    func onCard(card: AnswerCard) {}
    func onSources(sources: [SourceItem]) {}
    func onThinking(text: String, done: Bool) {}
    func onAnswer(segments: [AnswerSegment], done: Bool) {}
}

@main
struct CoreSmoke {
    static func main() throws {
        guard (2...3).contains(CommandLine.arguments.count) else { fatalError("usage: core-smoke <Encoders directory> [model-pack directory]") }
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("commonplace-swift-smoke-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: data) }
        let engine = try CommonplaceEngine(opts: .init(dataDir: data.path, encodersDir: CommandLine.arguments[1], leafModel: "onnx/model_quantized.onnx", ettinModel: "onnx/model_sel8.onnx", encoderThreads: 2, llmThreads: 2, pinBigCores: false))
        let marker = "copper-sparrow-47"
        let pack = try engine.addDocument(title: "Smoke fixture", pages: ["This is an original Commonplace test fixture. The verification marker is \(marker). This local document is used to check that the native Swift bindings can index a document, search its passages and open the cited evidence without a network connection. It contains no external reference material."], listener: SmokeProgress())
        precondition(engine.library().packs.contains { $0.packId == pack && $0.userDocument })
        let result = try engine.ask(input: .init(query: "What is the verification marker?", history: [], think: false, thermalHeadroom: nil, packs: [pack]), listener: SmokeListener())
        precondition(result.card.topText.contains(marker))
        guard let source = result.sources.first else { fatalError("no source returned") }
        let passage = try engine.passage(packId: source.packId, passageId: source.passageId)
        precondition(passage.text.contains(marker))
        if CommandLine.arguments.count == 3 {
            let modelID = try engine.mountPack(directory: CommandLine.arguments[2])
            let status = try engine.loadModelPack(packId: modelID)
            precondition(status.loaded)
            var settings = engine.settings(); settings.maxAnswerTokens = 64; engine.updateSettings(n: settings)
            let generated = try engine.ask(input: .init(query: "What is the verification marker?", history: [], think: false, thermalHeadroom: nil, packs: [pack]), listener: SmokeListener())
            precondition(!generated.answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            precondition(!generated.sources.isEmpty)
            print("PASS: real GGUF loading and local streamed answer generation (plumbing only)")
            print(generated.answerText)
            engine.unloadModel()
            try engine.removePack(packId: modelID)
        }
        try engine.setPackEnabled(packId: pack, enabled: false)
        precondition(engine.library().packs.first?.enabled == false)
        try engine.setPackEnabled(packId: pack, enabled: true)
        try engine.removePack(packId: pack)
        precondition(engine.library().packs.isEmpty)
        print("PASS: real Swift → UniFFI → Rust → ONNX indexing/retrieval/source reading, pack switching and deletion")
        print("Build: \(engine.deviceInfo().build). Host plumbing check only; no accuracy or phone-speed claim.")
    }
}
