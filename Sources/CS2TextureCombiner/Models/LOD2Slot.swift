import Foundation

enum LOD2Slot: String, CaseIterable, Identifiable, Sendable {
    case baseColor, colourMask1, colourMask2, colourMask3, roughness, normal, emissive
    var id: String { rawValue }
    var title: String { switch self { case .baseColor: "BaseColor"; case .colourMask1: "\(AppSpelling.colour)Mask1"; case .colourMask2: "\(AppSpelling.colour)Mask2"; case .colourMask3: "\(AppSpelling.colour)Mask3"; case .roughness: "Roughness"; case .normal: "Normal"; case .emissive: "Emissive" } }
}

struct LOD2Set: Identifiable {
    let name: String
    var inputs: [LOD2Slot: URL]
    var id: String { name }
}
