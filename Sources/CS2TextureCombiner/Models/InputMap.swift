import Foundation

struct PixelSize: Equatable, Sendable, CustomStringConvertible {
    let width: Int
    let height: Int

    var description: String { "\(width) × \(height)" }
    var isSquare: Bool { width == height }
}

struct InputMap: Identifiable, Equatable, Sendable {
    let slot: MapSlot
    let url: URL
    let size: PixelSize

    var id: MapSlot { slot }
}

struct TextureExportPlan: Sendable {
    let inputs: [MapSlot: InputMap]
    let targetSize: PixelSize
    let outputDirectory: URL
    let assetName: String

    static let outputSuffixes = [
        "BaseColor",
        "ControlMask",
        "MaskMap",
        "Normal",
        "Emissive"
    ]

    var outputNames: [String] {
        Self.outputSuffixes.map { "\(assetName)_\($0).png" }
    }

    var outputURLs: [URL] {
        outputNames.map { outputDirectory.appendingPathComponent($0) }
    }

    func outputName(suffix: String) -> String {
        "\(assetName)_\(suffix).png"
    }
}

enum CombinerError: LocalizedError {
    case unreadableImage(URL)
    case baseColorRequired
    case invalidBaseColorSize(PixelSize)
    case cannotCreateImage
    case cannotWrite(URL)

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let url):
            "Could not read image data from \(url.lastPathComponent)."
        case .baseColorRequired:
            "Add a Base Color map before exporting."
        case .invalidBaseColorSize(let size):
            "Base Color must be square and between 512 and 4096 pixels. It is \(size)."
        case .cannotCreateImage:
            "The packed image could not be created."
        case .cannotWrite(let url):
            "Could not write \(url.lastPathComponent)."
        }
    }
}
