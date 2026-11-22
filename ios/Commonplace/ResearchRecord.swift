import Foundation

struct SourceRecord: Codable, Identifiable, Sendable {
    var id: String { "\(packID):\(passageID):\(number)" }
    var number: UInt32
    var packID: String
    var passageID: UInt32
    var articleID: UInt32
    var title: String
    var section: String
    var snippet: String
    var license: String
    var sourceURL: String
}

struct SegmentRecord: Codable, Sendable {
    enum Kind: String, Codable { case text, unverified, citation }
    var kind: Kind
    var text: String
    var number: UInt32?
}

struct TurnRecordData: Codable, Identifiable, Sendable {
    var id = UUID()
    var question: String
    var answer: String
    var sources: [SourceRecord] = []
    var segments: [SegmentRecord] = []
    var thinking = ""
    var kind = "question"
    var stopped = false
    var error: String?
}

struct ConversationRecord: Codable, Identifiable, Sendable {
    var id = UUID()
    var updated = Date()
    var scopeID: String?
    var scopeTitle: String?
    var turns: [TurnRecordData] = []
    var title: String { turns.first?.question ?? "New research" }
}

struct ConversationStorage {
    let directory: URL

    func save(_ conversation: ConversationRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(conversation)
        let path = directory.appendingPathComponent(conversation.id.uuidString).appendingPathExtension("json")
        try data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func all() throws -> [ConversationRecord] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(ConversationRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updated > $1.updated }
    }

    func remove(_ id: UUID) throws {
        try FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString).appendingPathExtension("json"))
    }
}
