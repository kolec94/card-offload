import Foundation

enum OffloadError: LocalizedError {
    case noSource
    case noDestination
    case sourceUnavailable
    case destinationUnavailable
    case cannotReadSource
    case sameFolder
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSource:
            return "Pick the card you want to copy from."
        case .noDestination:
            return "Pick the drive you want to copy to."
        case .sourceUnavailable:
            return "The card isn't there any more. Reconnect it and pick it again."
        case .destinationUnavailable:
            return "The drive isn't there any more. Reconnect it and pick it again."
        case .cannotReadSource:
            return "Couldn't read the card. Try unplugging it and plugging it back in."
        case .sameFolder:
            return "The card and the drive are the same folder. Pick a different destination."
        case .verificationFailed(let name):
            return "\(name) didn't match after copying. The copy was removed — try again."
        }
    }
}
