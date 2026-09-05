import Foundation

/// A folder the user granted us access to via the document picker.
///
/// iOS hands back a security-scoped URL. We persist it as a bookmark so the app can
/// re-open the same SSD folder on the next launch without asking again — though a
/// bookmark to a removable volume goes stale as soon as the drive is unplugged, so
/// every call site has to handle `resolve()` returning nil.
struct FolderBookmark: Codable, Equatable {
    let data: Data
    /// Display name captured at pick time, so the UI has something to show
    /// even when the volume is currently detached.
    let displayName: String

    init?(url: URL) {
        guard let bookmark = try? url.bookmarkData(options: .minimalBookmark,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) else { return nil }
        self.data = bookmark
        self.displayName = url.lastPathComponent
    }

    /// Resolves the bookmark back to a URL. Returns nil if the volume is gone.
    ///
    /// The caller owns the security scope: balance a successful resolve with
    /// `stopAccessingSecurityScopedResource()`.
    func resolve() -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            url.stopAccessingSecurityScopedResource()
            return nil
        }
        return url
    }
}

/// Stores the two folders the app cares about between launches.
enum FolderBookmarkStore {
    private static let sourceKey = "CardOffload.bookmark.source"
    private static let destinationKey = "CardOffload.bookmark.destination"

    static func save(_ bookmark: FolderBookmark?, forKey key: Key) {
        let defaults = UserDefaults.standard
        guard let bookmark, let encoded = try? JSONEncoder().encode(bookmark) else {
            defaults.removeObject(forKey: key.storageKey)
            return
        }
        defaults.set(encoded, forKey: key.storageKey)
    }

    static func load(_ key: Key) -> FolderBookmark? {
        guard let data = UserDefaults.standard.data(forKey: key.storageKey) else { return nil }
        return try? JSONDecoder().decode(FolderBookmark.self, from: data)
    }

    enum Key {
        case source, destination

        var storageKey: String {
            switch self {
            case .source: return FolderBookmarkStore.sourceKey
            case .destination: return FolderBookmarkStore.destinationKey
            }
        }
    }
}
