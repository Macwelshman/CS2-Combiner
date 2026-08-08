import Foundation

enum TexturePacking {
    static func validateBaseColor(_ input: InputMap?) throws -> PixelSize {
        guard let input else { throw CombinerError.baseColorRequired }
        try validateMainInputSize(input.size, name: input.slot.title)
        return input.size
    }

    static func validateMainInputSize(_ size: PixelSize, name: String) throws {
        guard size.isSquare, [512, 1024, 2048, 4096].contains(size.width) else {
            throw CombinerError.invalidMainTextureSize(name: name, size: size)
        }
    }

    static func validateInputSizes(
        _ inputs: [MapSlot: InputMap],
        targetSize: PixelSize
    ) throws {
        guard let baseColor = inputs[.baseColor] else {
            throw CombinerError.baseColorRequired
        }
        try validateMainInputSize(baseColor.size, name: baseColor.slot.title)
        guard targetSize == baseColor.size else {
            throw CombinerError.exportSizeMismatch(
                imported: baseColor.size,
                requested: targetSize
            )
        }

        let mismatches = inputs.values
            .filter { $0.size != baseColor.size }
            .sorted { $0.slot.title < $1.slot.title }
            .map { "\($0.slot.title): \($0.size)" }
        guard mismatches.isEmpty else {
            throw CombinerError.mismatchedTextureSizes(
                expected: baseColor.size,
                maps: mismatches
            )
        }
    }

    static func export(_ plan: TextureExportPlan) throws -> [URL] {
        try validateInputSizes(plan.inputs, targetSize: plan.targetSize)

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: plan.outputDirectory,
            withIntermediateDirectories: true
        )

        let staging = plan.outputDirectory.appendingPathComponent(
            ".cs2-combiner-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: staging) }

        try writeBaseColor(
            plan,
            to: staging.appendingPathComponent(plan.outputName(suffix: "BaseColor"))
        )
        try writeControlMask(
            plan,
            to: staging.appendingPathComponent(plan.outputName(suffix: "ControlMask"))
        )
        try writeMaskMap(
            plan,
            to: staging.appendingPathComponent(plan.outputName(suffix: "MaskMap"))
        )
        try writeNormal(
            plan,
            to: staging.appendingPathComponent(plan.outputName(suffix: "Normal"))
        )
        try writeEmissive(
            plan,
            to: staging.appendingPathComponent(plan.outputName(suffix: "Emissive"))
        )

        for name in plan.outputNames {
            let staged = staging.appendingPathComponent(name)
            let final = plan.outputDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: final.path) {
                try fileManager.removeItem(at: final)
            }
            try fileManager.moveItem(at: staged, to: final)
        }
        return plan.outputURLs
    }

    private static func writeBaseColor(_ plan: TextureExportPlan, to url: URL) throws {
        guard let baseInput = plan.inputs[.baseColor] else {
            throw CombinerError.baseColorRequired
        }
        let usesEmbeddedAlpha = try ImageLoader.hasAlphaChannel(baseInput.url)
        var base = try ImageLoader.raster(from: baseInput.url)
        let usesOpacityMap = plan.inputs[.opacity] != nil &&
            (!usesEmbeddedAlpha || plan.opacityMapOverridesBaseColorAlpha)
        let opacity = try usesOpacityMap ? plan.inputs[.opacity].map {
            try ImageLoader.raster(from: $0.url)
        } : nil

        if let opacity {
            for pixel in 0..<(plan.targetSize.width * plan.targetSize.height) {
                base.bytes[pixel * 4 + 3] = opacity.red(at: pixel)
            }
        } else if !usesEmbeddedAlpha {
            for pixel in 0..<(plan.targetSize.width * plan.targetSize.height) {
                base.bytes[pixel * 4 + 3] = 255
            }
        }
        try ImageLoader.writePNG(base, to: url)
    }

    private static func writeControlMask(_ plan: TextureExportPlan, to url: URL) throws {
        let channels = try [.cm1, .cm2, .cm3, .snowRemove].map { slot in
            try plan.inputs[slot].map {
                try ImageLoader.raster(from: $0.url)
            }
        }
        var output = blank(plan.targetSize, alpha: 0)
        for pixel in 0..<(plan.targetSize.width * plan.targetSize.height) {
            for channel in 0..<4 {
                output.bytes[pixel * 4 + channel] = channels[channel]?.red(at: pixel) ?? 0
            }
        }
        try ImageLoader.writePNG(output, to: url)
    }

    private static func writeMaskMap(_ plan: TextureExportPlan, to url: URL) throws {
        let metallic = try raster(for: .metallic, in: plan)
        let coat = try raster(for: .coat, in: plan)
        let roughness = try raster(for: .roughness, in: plan)
        var output = blank(plan.targetSize, alpha: 0)
        for pixel in 0..<(plan.targetSize.width * plan.targetSize.height) {
            let index = pixel * 4
            output.bytes[index] = metallic?.red(at: pixel) ?? 0
            output.bytes[index + 1] = coat?.red(at: pixel) ?? 0
            output.bytes[index + 2] = 0
            output.bytes[index + 3] = 255 - (roughness?.red(at: pixel) ?? 255)
        }
        try ImageLoader.writePNG(output, to: url)
    }

    private static func writeNormal(_ plan: TextureExportPlan, to url: URL) throws {
        if var normal = try raster(for: .normal, in: plan) {
            if plan.normalizeNormalOnExport {
                NormalMapNormalization.normalize(&normal)
            }
            for pixel in 0..<(plan.targetSize.width * plan.targetSize.height) {
                normal.bytes[pixel * 4 + 3] = 255
            }
            try ImageLoader.writePNG(normal, to: url)
        } else {
            try ImageLoader.writePNG(
                solid(plan.targetSize, red: 128, green: 128, blue: 255),
                to: url
            )
        }
    }

    private static func writeEmissive(_ plan: TextureExportPlan, to url: URL) throws {
        if var emissive = try raster(for: .emissive, in: plan) {
            for pixel in 0..<(plan.targetSize.width * plan.targetSize.height) {
                emissive.bytes[pixel * 4 + 3] = 255
            }
            try ImageLoader.writePNG(emissive, to: url)
        } else {
            try ImageLoader.writePNG(solid(plan.targetSize, red: 0, green: 0, blue: 0), to: url)
        }
    }

    private static func raster(for slot: MapSlot, in plan: TextureExportPlan) throws -> ImageRaster? {
        try plan.inputs[slot].map {
            try ImageLoader.raster(from: $0.url)
        }
    }

    private static func blank(_ size: PixelSize, alpha: UInt8) -> ImageRaster {
        var raster = ImageRaster(
            width: size.width,
            height: size.height,
            bytes: [UInt8](repeating: 0, count: size.width * size.height * 4)
        )
        if alpha != 0 {
            for pixel in 0..<(size.width * size.height) {
                raster.bytes[pixel * 4 + 3] = alpha
            }
        }
        return raster
    }

    private static func solid(
        _ size: PixelSize,
        red: UInt8,
        green: UInt8,
        blue: UInt8
    ) -> ImageRaster {
        var raster = blank(size, alpha: 255)
        for pixel in 0..<(size.width * size.height) {
            let index = pixel * 4
            raster.bytes[index] = red
            raster.bytes[index + 1] = green
            raster.bytes[index + 2] = blue
        }
        return raster
    }
}
