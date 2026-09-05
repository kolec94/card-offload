import Foundation
import CryptoKit

/// Streams bytes from one file to another, hashing as it goes.
///
/// `FileManager.copyItem` would be shorter, but it gives no progress inside a single
/// file — and a 40-minute 4K clip is one file. Chunked copying keeps the progress bar
/// honest and lets a cancel take effect mid-file. Hashing during the copy means
/// verification only costs one extra read instead of two.
enum FileCopier {

    /// 4 MB — large enough that syscall overhead disappears, small enough that
    /// cancellation feels immediate and memory stays flat.
    private static let chunkSize = 4 * 1024 * 1024

    /// Copies `source` to `destination`, creating intermediate folders.
    /// - Parameter onBytes: called with the byte count of each chunk written.
    /// - Returns: SHA-256 of the bytes that were read from the source.
    @discardableResult
    static func copy(from source: URL,
                     to destination: URL,
                     onBytes: (Int) -> Void) throws -> SHA256Digest {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(),
                               withIntermediateDirectories: true)

        // A leftover partial file from a previous interrupted run must not be appended to.
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        guard fm.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteNoPermission)
        }

        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }

        var hasher = SHA256()
        while true {
            // A cancelled Task leaves a partial file behind; the caller deletes it.
            try Task.checkCancellation()
            guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            try output.write(contentsOf: chunk)
            onBytes(chunk.count)
        }
        try output.synchronize()

        // Carry the capture timestamp across so the SSD copy sorts like the original.
        if let values = try? source.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) {
            var attributes: [FileAttributeKey: Any] = [:]
            if let created = values.creationDate { attributes[.creationDate] = created }
            if let modified = values.contentModificationDate { attributes[.modificationDate] = modified }
            try? fm.setAttributes(attributes, ofItemAtPath: destination.path)
        }

        return hasher.finalize()
    }

    /// Reads a file back and returns its SHA-256, for post-copy verification.
    static func hash(of url: URL) throws -> SHA256Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }
}
