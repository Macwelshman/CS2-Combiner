import Foundation
import ImageIO

enum MapDetector {
    private static let supportedExtensions = Set([
        "png", "tif", "tiff", "bmp", "jpg", "jpeg", "heic"
    ])

    static func slot(for url: URL) -> MapSlot? {
        let name = normalizedStem(url)

        let rules: [(MapSlot, [String])] = [
            (.snowRemove, ["snowremove", "snowremoval"]),
            (.baseColor, ["basecolor", "basecolour", "albedo", "diffuse"]),
            (.opacity, ["opacity", "transparency", "alpha"]),
            (.cm1, ["controlmask1", "control1", "cm1", "colormask1", "colourmask1", "colormaskone", "colourmaskone"]),
            (.cm2, ["controlmask2", "control2", "cm2", "colormask2", "colourmask2", "colormasktwo", "colourmasktwo"]),
            (.cm3, ["controlmask3", "control3", "cm3", "colormask3", "colourmask3", "colormaskthree", "colourmaskthree"]),
            (.metallic, ["metallic", "metalness"]),
            (.coat, ["clearcoat", "coat"]),
            (.roughness, ["roughness", "rough"]),
            (.emissive, ["emissive", "emission", "emit"]),
            (.normal, ["normalgl", "openglnormal", "opengl", "normal"])
        ]

        return rules.first(where: { _, tokens in
            tokens.contains(where: name.contains)
        })?.0
    }

    static func isDirectXNormal(_ url: URL) -> Bool {
        let name = normalizedStem(url)
        return name.contains("directx") || name.contains("normaldx") || name.contains("dxnormal")
    }

    static func imageURLs(in droppedURLs: [URL]) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey]
        var results: [URL] = []

        for url in droppedURLs {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                guard let enumerator = FileManager.default.enumerator(atPath: url.path) else {
                    continue
                }

                for case let relativePath as String in enumerator {
                    let candidate = url.appendingPathComponent(relativePath)
                    let candidateValues = try? candidate.resourceValues(forKeys: keys)
                    if candidateValues?.isHidden == true { continue }
                    let isInsideExportFolder = candidate.pathComponents.contains {
                        let component = $0.lowercased()
                        return component == "export files" ||
                            component.hasSuffix(" export files") ||
                            component == "cs2 export" ||
                            component.hasSuffix(" cs2 export") ||
                            component == "cs2 textures" ||
                            component.hasSuffix(" cs2 textures")
                    }
                    if isInsideExportFolder {
                        continue
                    }
                    if candidateValues?.isDirectory != true, isSupportedImage(candidate) {
                        results.append(candidate)
                    }
                }
            } else if isSupportedImage(url) {
                results.append(url)
            }
        }

        return results.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private static func normalizedStem(_ url: URL) -> String {
        String(
            url.deletingPathExtension().lastPathComponent
                .lowercased()
                .filter { $0.isLetter || $0.isNumber }
        )
    }

    static func isSupportedImage(_ url: URL) -> Bool {
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            return false
        }
        return CGImageSourceCreateWithURL(url as CFURL, nil) != nil
    }
}
