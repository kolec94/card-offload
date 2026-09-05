import Foundation
import SwiftUI
import UIKit

/// The app's single source of truth: which folders are picked, what was found,
/// and how far along the current copy is.
@MainActor
final class OffloadSession: ObservableObject {

    enum Phase: Equatable {
        case idle
        case scanning
        case ready
        case transferring
        case finished
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var files: [MediaFile] = []
    @Published private(set) var scanProgress = VolumeScanner.Progress(filesSeen: 0, matches: 0)
    @Published private(set) var transferProgress = TransferEngine.Progress()
    @Published private(set) var results: [TransferResult] = []
    @Published private(set) var summary: OffloadSummary?
    @Published var errorMessage: String?

    @Published private(set) var sourceName: String?
    @Published private(set) var destinationName: String?

    @Published var settings: OffloadSettings = .load() {
        didSet { settings.save() }
    }

    /// Resolved, security-scoped URLs. Held for the lifetime of the pick so the
    /// sandbox keeps letting us read and write; released when replaced.
    private var sourceURL: URL?
    private var destinationURL: URL?
    private var work: Task<Void, Never>?
    private var transferStart: Date?

    init() {
        restore(.source)
        restore(.destination)
    }

    // MARK: - Derived state

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    var isBusy: Bool { phase == .scanning || phase == .transferring }
    var canStart: Bool { phase == .ready && !files.isEmpty }

    var fractionComplete: Double {
        guard transferProgress.totalBytes > 0 else { return 0 }
        return min(1, Double(transferProgress.bytesDone) / Double(transferProgress.totalBytes))
    }

    /// Bytes per second so far, or nil before there is enough data to be meaningful.
    var throughput: Double? {
        guard let start = transferStart else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 1, transferProgress.bytesDone > 0 else { return nil }
        return Double(transferProgress.bytesDone) / elapsed
    }

    var estimatedTimeRemaining: TimeInterval? {
        guard let rate = throughput, rate > 0 else { return nil }
        let remaining = transferProgress.totalBytes - transferProgress.bytesDone
        guard remaining > 0 else { return nil }
        return Double(remaining) / rate
    }

    var counts: [MediaFile.Kind: Int] {
        Dictionary(grouping: files, by: \.kind).mapValues(\.count)
    }

    // MARK: - Folder selection

    func setSource(_ url: URL) {
        release(&sourceURL)
        // Scope has to be open before the bookmark is made, or the bookmark is useless.
        _ = url.startAccessingSecurityScopedResource()
        guard let bookmark = FolderBookmark(url: url) else {
            url.stopAccessingSecurityScopedResource()
            errorMessage = OffloadError.sourceUnavailable.errorDescription
            return
        }
        FolderBookmarkStore.save(bookmark, forKey: .source)
        sourceURL = url
        sourceName = url.lastPathComponent
        resetFindings()
        scan()
    }

    func setDestination(_ url: URL) {
        release(&destinationURL)
        _ = url.startAccessingSecurityScopedResource()
        guard let bookmark = FolderBookmark(url: url) else {
            url.stopAccessingSecurityScopedResource()
            errorMessage = OffloadError.destinationUnavailable.errorDescription
            return
        }
        FolderBookmarkStore.save(bookmark, forKey: .destination)
        destinationURL = url
        destinationName = url.lastPathComponent
    }

    private func restore(_ key: FolderBookmarkStore.Key) {
        guard let bookmark = FolderBookmarkStore.load(key) else { return }
        let url = bookmark.resolve()
        switch key {
        case .source:
            sourceURL = url
            sourceName = url?.lastPathComponent ?? bookmark.displayName
        case .destination:
            destinationURL = url
            destinationName = url?.lastPathComponent ?? bookmark.displayName
        }
    }

    /// True when a folder was picked previously but its volume is not currently attached.
    func isDetached(_ key: FolderBookmarkStore.Key) -> Bool {
        switch key {
        case .source: return sourceName != nil && sourceURL == nil
        case .destination: return destinationName != nil && destinationURL == nil
        }
    }

    // MARK: - Scanning

    func scan() {
        guard let source = sourceURL else {
            errorMessage = OffloadError.noSource.errorDescription
            return
        }
        work?.cancel()
        resetFindings()
        phase = .scanning

        let settings = self.settings
        work = Task { [weak self] in
            do {
                let found = try await VolumeScanner.scan(root: source, settings: settings) { progress in
                    Task { @MainActor in self?.scanProgress = progress }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.files = found
                    self?.phase = .ready
                }
            } catch is CancellationError {
                await MainActor.run { self?.phase = .idle }
            } catch {
                await MainActor.run {
                    self?.errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    self?.phase = .idle
                }
            }
        }
    }

    // MARK: - Transferring

    func start() {
        guard sourceURL != nil else {
            errorMessage = OffloadError.noSource.errorDescription
            return
        }
        guard let destination = destinationURL else {
            errorMessage = OffloadError.noDestination.errorDescription
            return
        }
        guard destination.standardizedFileURL != sourceURL?.standardizedFileURL else {
            errorMessage = OffloadError.sameFolder.errorDescription
            return
        }

        work?.cancel()
        results = []
        summary = nil
        transferStart = Date()
        transferProgress = TransferEngine.Progress(totalFiles: files.count, totalBytes: totalBytes)
        phase = .transferring

        // A long offload with the screen asleep gets throttled; keep the device awake.
        UIApplication.shared.isIdleTimerDisabled = true

        let engine = TransferEngine(destinationRoot: destination, settings: settings)
        let queue = files
        work = Task { [weak self] in
            var outcome: OffloadSummary?
            do {
                outcome = try await engine.run(files: queue) { progress in
                    Task { @MainActor in self?.transferProgress = progress }
                } onResult: { result in
                    Task { @MainActor in self?.results.append(result) }
                }
            } catch is CancellationError {
                var cancelled = OffloadSummary()
                cancelled.wasCancelled = true
                cancelled.copied = await MainActor.run {
                    self?.results.filter {
                        if case .copied = $0.outcome { return true }
                        return false
                    }.count ?? 0
                }
                outcome = cancelled
            } catch {
                await MainActor.run {
                    self?.errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }

            let finished = outcome
            await MainActor.run {
                UIApplication.shared.isIdleTimerDisabled = false
                self?.summary = finished
                self?.phase = .finished
            }
        }
    }

    func cancel() {
        work?.cancel()
    }

    func reset() {
        work?.cancel()
        resetFindings()
        phase = sourceURL == nil ? .idle : .ready
        if sourceURL != nil { scan() }
    }

    private func resetFindings() {
        files = []
        results = []
        summary = nil
        scanProgress = VolumeScanner.Progress(filesSeen: 0, matches: 0)
        transferProgress = TransferEngine.Progress()
        transferStart = nil
    }

    private func release(_ url: inout URL?) {
        url?.stopAccessingSecurityScopedResource()
        url = nil
    }
}
