import Foundation

/// One file found on the source volume that is a candidate for copying.
struct MediaFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    /// Path of the file relative to the folder the user picked, e.g. "DCIM/100CANON/IMG_0042.CR3".
    let relativePath: String
    let size: Int64
    let captureDate: Date
    let kind: Kind

    enum Kind: String, CaseIterable {
        case photo
        case rawPhoto
        case video
        case sidecar

        var label: String {
            switch self {
            case .photo: return "Photo"
            case .rawPhoto: return "RAW"
            case .video: return "Video"
            case .sidecar: return "Sidecar"
            }
        }

        var symbol: String {
            switch self {
            case .photo: return "photo"
            case .rawPhoto: return "camera.aperture"
            case .video: return "film"
            case .sidecar: return "doc.text"
            }
        }
    }

    var filename: String { url.lastPathComponent }
}

extension MediaFile {
    /// Extensions we treat as media. Sidecars ride along with whatever they belong to.
    static let photoExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "webp", "avif", "bmp", "gif"
    ]

    static let rawExtensions: Set<String> = [
        "dng", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "raf",
        "orf", "rw2", "raw", "pef", "ptx", "srw", "3fr", "fff", "iiq", "erf",
        "mrw", "dcr", "kdc", "mos", "x3f", "gpr"
    ]

    static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mts", "m2ts", "mxf", "braw", "r3d",
        "insv", "lrv", "360", "wmv", "mkv", "mpg", "mpeg", "3gp"
    ]

    static let sidecarExtensions: Set<String> = [
        "xmp", "thm", "aae", "cos", "pp3", "dop", "wav", "srt", "gpx", "bif", "ind"
    ]

    static func kind(forExtension ext: String) -> Kind? {
        let e = ext.lowercased()
        if rawExtensions.contains(e) { return .rawPhoto }
        if photoExtensions.contains(e) { return .photo }
        if videoExtensions.contains(e) { return .video }
        if sidecarExtensions.contains(e) { return .sidecar }
        return nil
    }
}
