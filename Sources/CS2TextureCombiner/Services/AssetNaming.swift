import Foundation

enum AssetNaming {
    static func inferredAssetName(from sourceURL: URL) -> String {
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let suffixes = [
            "base[ _-]*colou?r",
            "albedo",
            "diffuse",
            "opacity",
            "transparency",
            "alpha",
            "control[ _-]*mask[ _-]*[123]",
            "control[ _-]*[123]",
            "cm[ _-]*[123]",
            "snow[ _-]*remove",
            "metallic[ _-]*mask",
            "metalness[ _-]*mask",
            "normal[ _-]*mask",
            "detail[ _-]*mask",
            "metallic",
            "metalness",
            "clear[ _-]*coat",
            "coat",
            "roughness",
            "rough",
            "normal[ _-]*gl",
            "open[ _-]*gl[ _-]*normal",
            "open[ _-]*gl",
            "normal",
            "emissive",
            "emission"
        ]
        let pattern = "(?i)[ _.-]*(?:\(suffixes.joined(separator: "|")))[ _.-]*$"
        let inferred = stem.replacingOccurrences(
            of: pattern,
            with: "",
            options: .regularExpression
        )
        let trimmed = inferred.trimmingCharacters(in: CharacterSet(charactersIn: " _.-"))
        if !trimmed.isEmpty {
            return trimmed
        }

        let parent = sourceURL.deletingLastPathComponent().lastPathComponent
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return parent.isEmpty ? "CS2 texture" : parent
    }

    static func outputDirectory(baseColorURL: URL, customRoot: URL?) -> URL {
        customRoot ?? baseColorURL
            .deletingLastPathComponent()
            .appendingPathComponent("CS2 Export", isDirectory: true)
    }
}
