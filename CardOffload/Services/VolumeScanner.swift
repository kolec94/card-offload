import Foundation

/// Walks a picked folder and returns the media files inside it.
enum VolumeScanner {

    struct Progress {
        var filesSeen: Int
        var matches: Int
    }

    /// Recursively enumerates `root`, keeping only files that match `settings`.
    ///
    /// `root` must already be inside a security scope held by the caller.
    static func scan(root: URL,
                     settings: OffloadSettings,
                     onProgress: @escaping @Sendable (Progress) -> Void) async throws -> [MediaFile] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
            .creationDateKey, .isHiddenKey
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw OffloadError.cannotReadSource
        }

        var found: [MediaFile] = []
        var seen = 0

        // NSEnumerator's Sequence conformance is unavailable from an async context
        // (a hard error under Swift 6), so step the enumerator by hand.
        while let entry = enumerator.nextObject() {
            guard let url = entry as? URL else { continue }
            try Task.checkCancellation()
            seen += 1
            if seen % 100 == 0 {
                let snapshot = Progress(filesSeen: seen, matches: found.count)
                await MainActor.run { onProgress(snapshot) }
            }

            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }

            // Cameras and macOS both scatter junk across cards; none of it is worth copying.
            let name = url.lastPathComponent
            if name.hasPrefix("._") || name == ".DS_Store" { continue }

            guard let kind = MediaFile.kind(forExtension: url.pathExtension) else { continue }
            guard include(kind, settings: settings) else { continue }

            let date = values.creationDate ?? values.contentModificationDate ?? Date()
            if let since = settings.since, date < since { continue }

            found.append(MediaFile(
                url: url,
                relativePath: relativePath(of: url, under: root),
                size: Int64(values.fileSize ?? 0),
                captureDate: date,
                kind: kind
            ))
        }

        let final = Progress(filesSeen: seen, matches: found.count)
        await MainActor.run { onProgress(final) }

        // Oldest first, so an interrupted run leaves a contiguous block of history behind.
        return found.sorted { $0.captureDate < $1.captureDate }
    }

    private static func include(_ kind: MediaFile.Kind, settings: OffloadSettings) -> Bool {
        switch kind {
        case .photo, .rawPhoto: return settings.includePhotos
        case .video: return settings.includeVideos
        case .sidecar: return settings.includeSidecars
        }
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
            return url.lastPathComponent
        }
        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
