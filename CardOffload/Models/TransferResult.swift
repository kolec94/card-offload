import Foundation

/// What happened to a single file once the engine got to it.
struct TransferResult: Identifiable {
    let id = UUID()
    let file: MediaFile
    let outcome: Outcome

    enum Outcome {
        case copied(destination: URL)
        case skippedAlreadyPresent
        case failed(String)

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }
}

/// Summary shown when a run finishes.
struct OffloadSummary {
    var copied: Int = 0
    var skipped: Int = 0
    var failed: Int = 0
    var bytesCopied: Int64 = 0
    var duration: TimeInterval = 0
    var wasCancelled: Bool = false

    var totalConsidered: Int { copied + skipped + failed }
}
