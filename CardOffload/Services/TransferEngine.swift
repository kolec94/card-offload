import Foundation

/// Copies a list of files from the card to the drive, one at a time.
struct TransferEngine {

    struct Progress {
        var fileIndex: Int = 0
        var totalFiles: Int = 0
        var currentFileName: String = ""
        var bytesDone: Int64 = 0
        var totalBytes: Int64 = 0
        var phase: Phase = .copying

        enum Phase {
            case copying, verifying

            var label: String {
                switch self {
                case .copying: return "Copying"
                case .verifying: return "Verifying"
                }
            }
        }
    }

    let destinationRoot: URL
    let settings: OffloadSettings

    /// Runs the copy. Throws `CancellationError` if the task is cancelled;
    /// per-file problems are reported as `.failed` results rather than thrown,
    /// so one unreadable file doesn't abandon the rest of the card.
    func run(files: [MediaFile],
             onProgress: @escaping @Sendable (Progress) -> Void,
             onResult: @escaping @Sendable (TransferResult) -> Void) async throws -> OffloadSummary {
        let started = Date()
        var summary = OffloadSummary()
        var progress = Progress(totalFiles: files.count,
                                totalBytes: files.reduce(0) { $0 + $1.size })
        var claimedPaths = Set<String>()

        for (index, file) in files.enumerated() {
            try Task.checkCancellation()

            progress.fileIndex = index + 1
            progress.currentFileName = file.filename
            progress.phase = .copying
            let copyingSnapshot = progress
            await MainActor.run { onProgress(copyingSnapshot) }

            let target = destination(for: file, claimed: &claimedPaths)

            if settings.skipExisting, isAlreadyPresent(file, at: target) {
                summary.skipped += 1
                progress.bytesDone += file.size
                let skipSnapshot = progress
                await MainActor.run {
                    onProgress(skipSnapshot)
                    onResult(TransferResult(file: file, outcome: .skippedAlreadyPresent))
                }
                continue
            }

            do {
                let bytesAtFileStart = progress.bytesDone
                var bytesThisFile: Int64 = 0
                var lastReport = Date.distantPast

                let sourceDigest = try FileCopier.copy(from: file.url, to: target) { written in
                    bytesThisFile += Int64(written)
                    // Throttle UI updates: a fast reader fires this hundreds of times a second.
                    let now = Date()
                    guard now.timeIntervalSince(lastReport) > 0.1 else { return }
                    lastReport = now
                    var snapshot = progress
                    snapshot.bytesDone = bytesAtFileStart + bytesThisFile
                    Task { @MainActor in onProgress(snapshot) }
                }

                progress.bytesDone = bytesAtFileStart + bytesThisFile

                if settings.verifyAfterCopy {
                    progress.phase = .verifying
                    let verifySnapshot = progress
                    await MainActor.run { onProgress(verifySnapshot) }

                    let copiedDigest = try FileCopier.hash(of: target)
                    guard copiedDigest == sourceDigest else {
                        try? FileManager.default.removeItem(at: target)
                        throw OffloadError.verificationFailed(file.filename)
                    }
                }

                summary.copied += 1
                summary.bytesCopied += file.size
                await MainActor.run {
                    onResult(TransferResult(file: file, outcome: .copied(destination: target)))
                }
            } catch is CancellationError {
                // Don't leave a half-written file that looks complete on the next run.
                try? FileManager.default.removeItem(at: target)
                summary.wasCancelled = true
                summary.duration = Date().timeIntervalSince(started)
                throw CancellationError()
            } catch {
                summary.failed += 1
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    onResult(TransferResult(file: file, outcome: .failed(message)))
                }
            }
        }

        summary.duration = Date().timeIntervalSince(started)
        return summary
    }

    // MARK: - Destination layout

    /// Where a given file lands, honouring the chosen layout and avoiding collisions.
    ///
    /// Camera filenames wrap around (IMG_0001 comes back every 9999 shots), so two
    /// different files can legitimately want the same name. `claimed` tracks names
    /// handed out during this run, since those files don't exist on disk yet.
    private func destination(for file: MediaFile, claimed: inout Set<String>) -> URL {
        let base: URL
        switch settings.organization {
        case .flat:
            base = destinationRoot.appendingPathComponent(file.filename)
        case .mirrorSource:
            base = destinationRoot.appendingPathComponent(file.relativePath)
        case .byDate:
            base = destinationRoot
                .appendingPathComponent(Self.yearFormatter.string(from: file.captureDate))
                .appendingPathComponent(Self.dayFormatter.string(from: file.captureDate))
                .appendingPathComponent(file.filename)
        }

        if !claimed.contains(base.path), !collides(file, with: base) {
            claimed.insert(base.path)
            return base
        }

        let stem = base.deletingPathExtension().lastPathComponent
        let ext = base.pathExtension
        let folder = base.deletingLastPathComponent()
        var suffix = 2
        while true {
            let name = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !claimed.contains(candidate.path), !FileManager.default.fileExists(atPath: candidate.path) {
                claimed.insert(candidate.path)
                return candidate
            }
            suffix += 1
        }
    }

    /// True when something else already occupies `target` that we should not overwrite.
    /// A same-name, same-size file is treated as the same shot — `skipExisting` handles it.
    private func collides(_ file: MediaFile, with target: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: target.path) else { return false }
        if settings.skipExisting, isAlreadyPresent(file, at: target) { return false }
        return true
    }

    private func isAlreadyPresent(_ file: MediaFile, at target: URL) -> Bool {
        guard let values = try? target.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return false }
        return Int64(size) == file.size
    }

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
