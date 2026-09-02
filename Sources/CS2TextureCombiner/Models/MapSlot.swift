import Foundation

enum MapSlot: String, CaseIterable, Identifiable, Sendable {
    case baseColor
    case opacity
    case cm1
    case cm2
    case cm3
    case snowRemove
    case metallic
    case metallicMask
    case normalMask
    case coat
    case roughness
    case normal
    case emissive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .baseColor: "BaseColor"
        case .opacity: "Opacity"
        case .cm1: "\(AppSpelling.colour)Mask1"
        case .cm2: "\(AppSpelling.colour)Mask2"
        case .cm3: "\(AppSpelling.colour)Mask3"
        case .snowRemove: "Snow Remove"
        case .metallic: "Metallic"
        case .metallicMask: "Metallic Mask"
        case .normalMask: "Normal Mask"
        case .coat: "Coat"
        case .roughness: "Roughness"
        case .normal: "Normal"
        case .emissive: "Emissive"
        }
    }

    var channelDescription: String {
        switch self {
        case .baseColor: "BaseColor RGB + embedded Alpha"
        case .opacity: "BaseColor Alpha fallback · default white"
        case .cm1: "ControlMask Red · default black"
        case .cm2: "ControlMask Green · default black"
        case .cm3: "ControlMask Blue · default black"
        case .snowRemove: "ControlMask Alpha · default black"
        case .metallic: "MaskMap Red · default black"
        case .metallicMask: "MaskMap Green · default white"
        case .normalMask: "MaskMap Blue · default white"
        case .coat: "MaskMap Green · default black"
        case .roughness: "MaskMap Alpha · inverted · default rough"
        case .normal: "Normal RGB · default neutral"
        case .emissive: "Emissive RGB · default black"
        }
    }

    var isRequired: Bool { self == .baseColor }
}

struct AssetProfileGroup: Identifiable, Sendable {
    let title: String
    let slots: [MapSlot]
    let showsOpacitySource: Bool

    var id: String { title }
}

enum AssetType: String, CaseIterable, Identifiable, Sendable {
    case building = "Building"
    case surface = "Surface"
    case decal = "Decal"

    var id: String { rawValue }

    var groups: [AssetProfileGroup] {
        switch self {
        case .building:
            [
                AssetProfileGroup(title: "BaseColor", slots: [.baseColor, .opacity], showsOpacitySource: true),
                AssetProfileGroup(title: "Control Mask", slots: [.cm1, .cm2, .cm3, .snowRemove], showsOpacitySource: false),
                AssetProfileGroup(title: "Mask Map", slots: [.metallic, .coat, .roughness], showsOpacitySource: false),
                AssetProfileGroup(title: "Surface", slots: [.normal, .emissive], showsOpacitySource: false)
            ]
        case .surface:
            [
                AssetProfileGroup(title: "BaseColor", slots: [.baseColor, .opacity], showsOpacitySource: true),
                AssetProfileGroup(title: "Mask Map", slots: [.metallic, .metallicMask, .normalMask, .roughness], showsOpacitySource: false),
                AssetProfileGroup(title: "Normal", slots: [.normal], showsOpacitySource: false)
            ]
        case .decal:
            [
                AssetProfileGroup(title: "BaseColor", slots: [.baseColor, .opacity], showsOpacitySource: true),
                AssetProfileGroup(title: "Mask Map", slots: [.metallic, .coat, .roughness], showsOpacitySource: false),
                AssetProfileGroup(title: "Normal", slots: [.normal], showsOpacitySource: false)
            ]
        }
    }

    var experimentalSlots: [MapSlot] {
        self == .decal ? [.cm1, .cm2, .cm3, .snowRemove, .emissive] : []
    }

    var supportedSlots: Set<MapSlot> {
        Set(groups.flatMap(\.slots) + experimentalSlots)
    }

    var outputSuffixes: [String] {
        switch self {
        case .building: ["BaseColor", "ControlMask", "MaskMap", "Normal", "Emissive"]
        case .surface, .decal: ["BaseColor", "MaskMap", "Normal"]
        }
    }

    var allowedSizes: [Int] {
        switch self {
        case .surface: [512, 1024, 2048]
        case .building, .decal: [512, 1024, 2048, 4096]
        }
    }

    var supportsLOD2: Bool { self == .building }
    var canExport: Bool { true }

    var description: String {
        switch self {
        case .building: "Five packed textures with optional building LOD2 sets."
        case .surface: "Three tiling textures with the surface-specific MaskMap layout."
        case .decal: "Three required decal textures, with ControlMask and Emissive written only when supplied."
        }
    }

    var sizeDescription: String {
        switch self {
        case .surface: "Surface maps must match at 512, 1024, or 2048 pixels. Textures are never resized."
        case .building, .decal: "Maps must match at 512, 1024, 2048, or 4096 pixels. Textures are never resized."
        }
    }
}
