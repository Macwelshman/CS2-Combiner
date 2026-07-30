import Foundation

enum MapSlot: String, CaseIterable, Identifiable, Sendable {
    case baseColor
    case opacity
    case cm1
    case cm2
    case cm3
    case snowRemove
    case metallic
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
        case .coat: "MaskMap Green · default black"
        case .roughness: "MaskMap Alpha · inverted · default rough"
        case .normal: "Normal RGB · default neutral"
        case .emissive: "Emissive RGB · default black"
        }
    }

    var isRequired: Bool { self == .baseColor }
}

enum SlotGroup: String, CaseIterable, Identifiable {
    case baseColor = "BaseColor"
    case controlMask = "Control Mask"
    case maskMap = "Mask Map"
    case surface = "Surface"

    var id: String { rawValue }

    var slots: [MapSlot] {
        switch self {
        case .baseColor: [.baseColor, .opacity]
        case .controlMask: [.cm1, .cm2, .cm3, .snowRemove]
        case .maskMap: [.metallic, .coat, .roughness]
        case .surface: [.normal, .emissive]
        }
    }
}
