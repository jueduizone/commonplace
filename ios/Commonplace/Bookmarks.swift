import Foundation

/// Holds security-scoped access for as long as mmap/readers may use a mounted directory.
/// Bookmarks stay in Application Support, are never shared and are excluded from backup.
final class PackBookmarks: @unchecked Sendable {
    private let file: URL
    private var open: [String: URL] = [:]
    private var bookmarks: [String: Data] = [:]

    init(file: URL) { self.file = file }

    func restore() throws -> [String] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        bookmarks = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: file))
        var unavailable: [String] = []
        var changed = false
        for (id, data) in bookmarks {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
                let scoped = url.startAccessingSecurityScopedResource()
                guard scoped || FileManager.default.isReadableFile(atPath: url.path) else { unavailable.append(id); continue }
                if scoped { open[id] = url }
                if stale { bookmarks[id] = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil); changed = true }
            } catch { unavailable.append(id) }
        }
        if changed { try persist() }
        return unavailable
    }

    func keep(_ url: URL, id: String, scoped: Bool) throws {
        let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let old = bookmarks[id]
        bookmarks[id] = data
        do { try persist() } catch { bookmarks[id] = old; throw error }
        open[id]?.stopAccessingSecurityScopedResource()
        open[id] = scoped ? url : nil // Caller transfers an active scope only when one was granted.
    }

    func remove(_ id: String) throws {
        bookmarks.removeValue(forKey: id)
        try persist()
        open.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
    }

    var mountedIDs: Set<String> { Set(bookmarks.keys) }

    private func persist() throws {
        try JSONEncoder().encode(bookmarks).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    deinit { for url in open.values { url.stopAccessingSecurityScopedResource() } }
}
