import Foundation

@main
struct PolicyAndStorageTests {
    static func main() throws {
        let mini = ModelCandidate(id: "mini", file: "/packs/MiniCPM5-2B-pureQ4_0.gguf", bytes: 1_420_000_000)
        let gemma = ModelCandidate(id: "gemma", file: "/packs/gemma-4-E2B-it-Q4_0.gguf", bytes: 2_800_000_000)
        let ling = ModelCandidate(id: "ling", file: "/packs/Ling-3.0-tiny-Q4_0.gguf", bytes: 4_620_000_000)
        let tensor = ModelCandidate(id: "tensor", file: "/packs/gemma-4-E2B-it_Google_Tensor_G5.litertlm", bytes: 3_110_000_000)
        precondition(!ling.supported && !tensor.supported)
        precondition(ModelPolicy.select([ling, tensor], available: .max, preferred: nil) == nil)
        precondition(ModelPolicy.select([gemma, mini], available: 4_500_000_000, preferred: nil) == mini)
        precondition(ModelPolicy.select([gemma, mini], available: 4_500_000_000, preferred: "gemma") == gemma)
        precondition(ModelPolicy.select([gemma, mini], available: 3_000_000_000, preferred: "gemma") == nil)
        precondition(ModelPolicy.select([mini], available: mini.estimatedPeak, preferred: nil) == nil)
        precondition(ModelPolicy.select([mini], available: 0, preferred: nil) == nil)
        precondition(ModelCandidate(id: "overflow", file: mini.file, bytes: .max).estimatedPeak == .max)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ConversationStorage(directory: directory)
        let source = SourceRecord(number: 1, packID: "doc-123", passageID: 0, articleID: 0, title: "研究记录", section: "p. 2", snippet: "Evidence", license: "User document", sourceURL: "")
        let turn = TurnRecordData(question: "为什么？", answer: "Evidence [1]", sources: [source], segments: [.init(kind: .text, text: "Evidence "), .init(kind: .citation, text: "[1]", number: 1)], stopped: true)
        var conversation = ConversationRecord(scopeID: "doc-123", scopeTitle: "研究记录", turns: [turn])
        try storage.save(conversation)
        let first = try storage.all()
        precondition(first.count == 1 && first[0].scopeID == "doc-123")
        precondition(first[0].turns[0].sources[0].title == "研究记录")
        precondition(first[0].turns[0].segments[1].number == 1 && first[0].turns[0].stopped)
        conversation.turns.append(.init(question: "Again", answer: "", error: "Stopped"))
        try storage.save(conversation)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("corrupt.json"))
        let updated = try storage.all()
        precondition(updated.count == 1 && updated[0].turns.count == 2)
        try storage.remove(conversation.id)
        let remaining = try storage.all()
        precondition(remaining.isEmpty)
        print("PASS: model admission, unsupported formats, overflow, history round-trip, citations, scope, atomic replacement and corrupt-file isolation")
    }
}
