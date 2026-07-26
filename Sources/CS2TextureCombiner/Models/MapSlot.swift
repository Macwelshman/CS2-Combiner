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
        case .baseColor: "Base Color"
        case .opacity: "Opacity"
        case .cm1: "CM1"
        case .cm2: "CM2"
        case .cm3: "CM3"
        case .snowRemove: "Snow Remove"
        case .metallic: "Metallic"
        case .coat: "Coat"
        case .roughness: "Roughness"
        case .normal: "Normal (OpenGL)"
        case .emissive: "Emissive"
        }
    }

    var channelDescription: String {
        switch self {
        case .baseColor: "RGB → BaseColor RGB"
        case .opacity: "Red → BaseColor Alpha · default white"
        case .cm1: "Red → ControlMask Red · default black"
        case .cm2: "Red → ControlMask Green · default black"
        case .cm3: "Red → ControlMask Blue · default black"
        case .snowRemove: "Red → ControlMask Alpha · default black"
        case .metallic: "Red → MaskMap Red · default black"
        case .coat: "Red → MaskMap Green · default black"
        case .roughness: "Inverted Red → MaskMap Alpha · default rough"
        case .normal: "RGB → Normal RGB · default neutral"
        case .emissive: "RGB → Emissive RGB · default black"
        }
    }

    var isRequired: Bool { self == .baseColor }
}

enum SlotGroup: String, CaseIterable, Identifiable {
    case baseColor = "Base Color"
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
