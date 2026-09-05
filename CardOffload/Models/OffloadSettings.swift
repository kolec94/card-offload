import Foundation

/// User-tunable behaviour, persisted in UserDefaults.
struct OffloadSettings: Codable, Equatable {
    /// How copied files are laid out inside the destination folder.
    var organization: Organization = .byDate
    /// Skip a file when the destination already has one with the same name and byte size.
    var skipExisting: Bool = true
    /// Re-read both copies and compare SHA-256 after copying. Roughly doubles the time.
    var verifyAfterCopy: Bool = true
    /// Include .xmp / .thm / .aae style companion files.
    var includeSidecars: Bool = true
    /// Copy photos (including RAW).
    var includePhotos: Bool = true
    /// Copy videos.
    var includeVideos: Bool = true
    /// Only consider files modified on or after this date. nil means everything.
    var since: Date? = nil

    enum Organization: String, Codable, CaseIterable, Identifiable {
        /// destination/2026/2026-09-05/IMG_0042.CR3
        case byDate
        /// destination/IMG_0042.CR3
        case flat
        /// Mirrors the folder layout on the card, e.g. destination/DCIM/100CANON/IMG_0042.CR3
        case mirrorSource

        var id: String { rawValue }

        var label: String {
            switch self {
            case .byDate: return "Folders by date"
            case .flat: return "One flat folder"
            case .mirrorSource: return "Mirror the card"
            }
        }

        var detail: String {
            switch self {
            case .byDate: return "2026/2026-09-05/IMG_0042.CR3"
            case .flat: return "IMG_0042.CR3"
            case .mirrorSource: return "DCIM/100CANON/IMG_0042.CR3"
            }
        }
    }
}

extension OffloadSettings {
    private static let defaultsKey = "CardOffload.settings"

    static func load() -> OffloadSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(OffloadSettings.self, from: data) else {
            return OffloadSettings()
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
