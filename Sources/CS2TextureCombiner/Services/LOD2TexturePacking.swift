import Foundation

struct LOD2TextureExportPlan: Sendable {
    let inputs: [LOD2Slot: URL]
    let assetName: String
    let outputDirectory: URL
    let targetSize = PixelSize(width: 512, height: 512)

    var outputURLs: [URL] {
        var suffixes: [String] = []
        if inputs[.baseColor] != nil { suffixes.append("BaseColor") }
        if inputs[.colourMask1] != nil || inputs[.colourMask2] != nil || inputs[.colourMask3] != nil { suffixes.append("ControlMask") }
        if inputs[.roughness] != nil { suffixes.append("MaskMap") }
        suffixes.append("Normal")
        if inputs[.emissive] != nil { suffixes.append("Emissive") }
        return suffixes.map { outputDirectory.appendingPathComponent("\(assetName)_LOD2_\($0).png") }
    }
}

enum LOD2TexturePacking {
    static func export(_ plan: LOD2TextureExportPlan) throws -> [URL] {
        let mismatches = try plan.inputs.compactMap { slot, source -> String? in
            let size = try ImageLoader.dimensions(of: source)
            return size == plan.targetSize ? nil : "\(slot.title): \(size)"
        }.sorted()
        guard mismatches.isEmpty else {
            throw CombinerError.mismatchedLOD2TextureSizes(maps: mismatches)
        }

        try FileManager.default.createDirectory(at: plan.outputDirectory, withIntermediateDirectories: true)
        let target = plan.targetSize
        var urls: [URL] = []
        if let source = plan.inputs[.baseColor] {
            let url = output(plan, "BaseColor"); try ImageLoader.writePNG(ImageLoader.raster(from: source), to: url); urls.append(url)
        }
        if plan.inputs[.colourMask1] != nil || plan.inputs[.colourMask2] != nil || plan.inputs[.colourMask3] != nil {
            let channels = try [LOD2Slot.colourMask1, .colourMask2, .colourMask3].map { try plan.inputs[$0].map { try ImageLoader.raster(from: $0) } }
            var bytes = [UInt8](repeating: 0, count: target.width * target.height * 4)
            for pixel in 0..<(target.width * target.height) {
                let index = pixel * 4
                bytes[index] = channels[0]?.red(at: pixel) ?? 0
                bytes[index + 1] = channels[1]?.red(at: pixel) ?? 0
                bytes[index + 2] = channels[2]?.red(at: pixel) ?? 0
                bytes[index + 3] = 0
            }
            let url = output(plan, "ControlMask"); try ImageLoader.writePNG(ImageRaster(width: target.width, height: target.height, bytes: bytes), to: url); urls.append(url)
        }
        if let source = plan.inputs[.roughness] {
            let roughness = try ImageLoader.raster(from: source)
            var bytes = [UInt8](repeating: 0, count: target.width * target.height * 4)
            for pixel in 0..<(target.width * target.height) { bytes[pixel * 4 + 3] = 255 - roughness.red(at: pixel) }
            let url = output(plan, "MaskMap"); try ImageLoader.writePNG(ImageRaster(width: target.width, height: target.height, bytes: bytes), to: url); urls.append(url)
        }
        let normal = try plan.inputs[.normal].map { try ImageLoader.raster(from: $0) }
            ?? flatNormal(target)
        let normalURL = output(plan, "Normal")
        try ImageLoader.writePNG(normal, to: normalURL)
        urls.append(normalURL)
        if let source = plan.inputs[.emissive] {
            let url = output(plan, "Emissive"); try ImageLoader.writePNG(ImageLoader.raster(from: source), to: url); urls.append(url)
        }
        return urls
    }

    private static func output(_ plan: LOD2TextureExportPlan, _ suffix: String) -> URL {
        plan.outputDirectory.appendingPathComponent("\(plan.assetName)_LOD2_\(suffix).png")
    }

    private static func flatNormal(_ size: PixelSize) -> ImageRaster {
        var bytes = [UInt8]()
        bytes.reserveCapacity(size.width * size.height * 4)
        for _ in 0..<(size.width * size.height) {
            bytes.append(contentsOf: [128, 128, 255, 255])
        }
        return ImageRaster(width: size.width, height: size.height, bytes: bytes)
    }
}
