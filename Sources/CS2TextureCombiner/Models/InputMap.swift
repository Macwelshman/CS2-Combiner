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

enum OpacitySource: Equatable, Sendable {
    case baseColorAlpha(opacityMapIgnored: Bool)
    case opacityMap(overridingBaseColorAlpha: Bool)
    case opaqueDefault

    static func resolve(
        hasBaseColor: Bool,
        baseColorHasAlpha: Bool,
        hasOpacityMap: Bool,
        opacityMapOverridesBaseColorAlpha: Bool
    ) -> Self {
        guard hasBaseColor else { return .opaqueDefault }
        if hasOpacityMap, opacityMapOverridesBaseColorAlpha || !baseColorHasAlpha {
            return .opacityMap(
                overridingBaseColorAlpha: baseColorHasAlpha && opacityMapOverridesBaseColorAlpha
            )
        }
        if baseColorHasAlpha {
            return .baseColorAlpha(opacityMapIgnored: hasOpacityMap)
        }
        return .opaqueDefault
    }

    var description: String {
        switch self {
        case .baseColorAlpha(opacityMapIgnored: false):
            "Opacity: BaseColor alpha"
        case .baseColorAlpha(opacityMapIgnored: true):
            "Opacity: BaseColor alpha · Opacity map ignored"
        case .opacityMap(overridingBaseColorAlpha: false):
            "Opacity: Opacity map"
        case .opacityMap(overridingBaseColorAlpha: true):
            "Opacity: Opacity map · overriding BaseColor alpha"
        case .opaqueDefault:
            "Opacity: Opaque default"
        }
    }
}

struct TextureExportPlan: Sendable {
    let inputs: [MapSlot: InputMap]
    let targetSize: PixelSize
    let outputDirectory: URL
    let assetName: String
    let opacityMapOverridesBaseColorAlpha: Bool
    let normalizeNormalOnExport: Bool
    let assetType: AssetType

    init(
        inputs: [MapSlot: InputMap],
        targetSize: PixelSize,
        outputDirectory: URL,
        assetName: String,
        opacityMapOverridesBaseColorAlpha: Bool = false,
        normalizeNormalOnExport: Bool = false,
        assetType: AssetType = .building
    ) {
        self.inputs = inputs
        self.targetSize = targetSize
        self.outputDirectory = outputDirectory
        self.assetName = assetName
        self.opacityMapOverridesBaseColorAlpha = opacityMapOverridesBaseColorAlpha
        self.normalizeNormalOnExport = normalizeNormalOnExport
        self.assetType = assetType
    }

    static let outputSuffixes = [
        "BaseColor",
        "ControlMask",
        "MaskMap",
        "Normal",
        "Emissive"
    ]

    var outputSuffixes: [String] {
        guard assetType == .decal else { return assetType.outputSuffixes }
        var suffixes = assetType.outputSuffixes
        if inputs.keys.contains(where: { [.cm1, .cm2, .cm3, .snowRemove].contains($0) }) {
            suffixes.insert("ControlMask", at: 1)
        }
        if inputs[.emissive] != nil {
            suffixes.append("Emissive")
        }
        return suffixes
    }

    var outputNames: [String] {
        outputSuffixes.map { "\(assetName)_\($0).png" }
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
    case profileNotImplemented(String)
    case invalidProfileTextureSize(profile: String, name: String, size: PixelSize, allowed: [Int])
    case invalidMainTextureSize(name: String, size: PixelSize)
    case exportSizeMismatch(imported: PixelSize, requested: PixelSize)
    case mismatchedTextureSizes(expected: PixelSize, maps: [String])
    case mismatchedLOD2TextureSizes(maps: [String])
    case cannotCreateImage
    case cannotWrite(URL)

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let url):
            "Could not read image data from \(url.lastPathComponent)."
        case .baseColorRequired:
            "Add a BaseColor map before exporting."
        case .profileNotImplemented(let profile):
            "\(profile) export is not available yet. Choose Building to export textures."
        case .invalidProfileTextureSize(let profile, let name, let size, let allowed):
            "\(name) for \(profile) must be square and exactly \(allowed.map(String.init).joined(separator: ", ")) pixels. It is \(size)."
        case .invalidMainTextureSize(let name, let size):
            "\(name) must be square and exactly 512, 1024, 2048, or 4096 pixels. It is \(size)."
        case .exportSizeMismatch(let imported, let requested):
            "The export size \(requested) does not match the imported BaseColor size \(imported). Textures are never resized."
        case .mismatchedTextureSizes(let expected, let maps):
            """
            All assigned main maps must match the BaseColor size \(expected). Textures are never resized.

            \(maps.joined(separator: "\n"))
            """
        case .mismatchedLOD2TextureSizes(let maps):
            """
            All assigned LOD2 maps must be exactly 512 × 512. Textures are never resized.

            \(maps.joined(separator: "\n"))
            """
        case .cannotCreateImage:
            "The packed image could not be created."
        case .cannotWrite(let url):
            "Could not write \(url.lastPathComponent)."
        }
    }
}
