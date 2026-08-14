import Foundation
import ImageIO
import XCTest
@testable import CS2TextureCombiner

final class CS2TextureCombinerTests: XCTestCase {
    func testExportAllRequiresBothMainBaseColorAndLOD2Maps() {
        XCTAssertFalse(
            ExportAvailability.showsExportAll(hasBaseColor: false, hasLOD2Sets: true)
        )
        XCTAssertFalse(
            ExportAvailability.showsExportAll(hasBaseColor: true, hasLOD2Sets: false)
        )
        XCTAssertFalse(
            ExportAvailability.showsExportAll(hasBaseColor: false, hasLOD2Sets: false)
        )
        XCTAssertTrue(
            ExportAvailability.showsExportAll(hasBaseColor: true, hasLOD2Sets: true)
        )
    }

    func testNormalizeLabelFollowsEnglishLocaleVariant() {
        XCTAssertEqual(AppSpelling.normalise(for: Locale(identifier: "en_GB")), "Normalise")
        XCTAssertEqual(AppSpelling.normalise(for: Locale(identifier: "en_US")), "Normalize")
    }

    func testOpacitySourceDescriptions() {
        XCTAssertEqual(
            OpacitySource.resolve(
                hasBaseColor: true,
                baseColorHasAlpha: true,
                hasOpacityMap: false,
                opacityMapOverridesBaseColorAlpha: false
            ).description,
            "Opacity: BaseColor alpha"
        )
        XCTAssertEqual(
            OpacitySource.resolve(
                hasBaseColor: true,
                baseColorHasAlpha: true,
                hasOpacityMap: true,
                opacityMapOverridesBaseColorAlpha: false
            ).description,
            "Opacity: BaseColor alpha · Opacity map ignored"
        )
        XCTAssertEqual(
            OpacitySource.resolve(
                hasBaseColor: true,
                baseColorHasAlpha: false,
                hasOpacityMap: true,
                opacityMapOverridesBaseColorAlpha: false
            ).description,
            "Opacity: Opacity map"
        )
        XCTAssertEqual(
            OpacitySource.resolve(
                hasBaseColor: true,
                baseColorHasAlpha: false,
                hasOpacityMap: false,
                opacityMapOverridesBaseColorAlpha: false
            ).description,
            "Opacity: Opaque default"
        )
        XCTAssertEqual(
            OpacitySource.resolve(
                hasBaseColor: true,
                baseColorHasAlpha: true,
                hasOpacityMap: true,
                opacityMapOverridesBaseColorAlpha: true
            ).description,
            "Opacity: Opacity map · overriding BaseColor alpha"
        )
    }

    @MainActor
    func testOpacitySourceUpdatesAsSlotsChange() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2OpacityStatus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let size = PixelSize(width: 1024, height: 1024)
        let rgbaBase = root.appendingPathComponent("Glass_BaseColor.png")
        let rgbBase = root.appendingPathComponent("Brick_BaseColor.png")
        let opacity = root.appendingPathComponent("Brick_Opacity.png")
        try ImageLoader.writePNG(
            solid(size, red: 20, green: 40, blue: 60, alpha: 90),
            to: rgbaBase
        )
        try writeRGBPNG(size, red: 20, green: 40, blue: 60, to: rgbBase)
        try ImageLoader.writePNG(
            solid(size, red: 170, green: 0, blue: 0),
            to: opacity
        )

        let store = TextureCombinerStore()
        store.assignDropped([rgbaBase], to: .baseColor)
        XCTAssertEqual(store.opacitySource.description, "Opacity: BaseColor alpha")

        store.assignDropped([opacity], to: .opacity)
        XCTAssertEqual(
            store.opacitySource.description,
            "Opacity: BaseColor alpha · Opacity map ignored"
        )

        store.setOpacityMapOverride(true)
        XCTAssertEqual(
            store.opacitySource.description,
            "Opacity: Opacity map · overriding BaseColor alpha"
        )

        store.assignDropped([rgbBase], to: .baseColor)
        XCTAssertEqual(store.opacitySource.description, "Opacity: Opacity map")

        store.remove(.opacity)
        XCTAssertEqual(store.opacitySource.description, "Opacity: Opaque default")
        XCTAssertFalse(store.opacityMapOverridesBaseColorAlpha)
    }

    @MainActor
    func testNormalizeCheckboxStateTracksNormalSlot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2NormalizeState-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let normalURL = root.appendingPathComponent("Brick_NormalGL.png")
        try ImageLoader.writePNG(
            solid(PixelSize(width: 1024, height: 1024), red: 210, green: 80, blue: 190),
            to: normalURL
        )

        let store = TextureCombinerStore()
        store.setNormalizeNormalOnExport(true)
        XCTAssertFalse(store.normalizeNormalOnExport)

        store.assignDropped([normalURL], to: .normal)
        XCTAssertFalse(store.normalizeNormalOnExport)
        store.setNormalizeNormalOnExport(true)
        XCTAssertTrue(store.normalizeNormalOnExport)

        store.remove(.normal)
        XCTAssertFalse(store.normalizeNormalOnExport)
    }

    @MainActor
    func testMainImportRejectsUnsupportedTextureSize() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2MainImportSize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let invalid = root.appendingPathComponent("Brick_BaseColor.png")
        try ImageLoader.writePNG(
            solid(PixelSize(width: 256, height: 256), red: 20, green: 40, blue: 60),
            to: invalid
        )

        let store = TextureCombinerStore()
        store.importDropped([invalid])

        XCTAssertNil(store.input(for: .baseColor))
        XCTAssertTrue(store.status.contains("Main maps must be square 512, 1024, 2048, or 4096 pixels"))
    }

    @MainActor
    func testLOD2ImportAcceptsOnly512Textures() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2LOD2ImportSize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let invalid = root.appendingPathComponent("Brick_LOD2_BaseColor.png")
        try ImageLoader.writePNG(
            solid(PixelSize(width: 256, height: 256), red: 20, green: 40, blue: 60),
            to: invalid
        )

        let store = LOD2Store()
        store.importDropped([invalid])

        XCTAssertTrue(store.sets.isEmpty)
        XCTAssertTrue(store.status.contains("Skipped non-512 × 512 files"))
    }

    func testFilenameDetection() {
        XCTAssertEqual(MapDetector.slot(for: URL(fileURLWithPath: "/tmp/wall_BaseColor.png")), .baseColor)
        XCTAssertEqual(MapDetector.slot(for: URL(fileURLWithPath: "/tmp/wall_CM2.tif")), .cm2)
        XCTAssertEqual(MapDetector.slot(for: URL(fileURLWithPath: "/tmp/wall_Colour Mask One.png")), .cm1)
        XCTAssertEqual(MapDetector.slot(for: URL(fileURLWithPath: "/tmp/wall_Color_Mask_Two.png")), .cm2)
        XCTAssertEqual(MapDetector.slot(for: URL(fileURLWithPath: "/tmp/wall_colour-mask-three.png")), .cm3)
        XCTAssertEqual(MapDetector.slot(for: URL(fileURLWithPath: "/tmp/wall_Snow_Remove.png")), .snowRemove)
        XCTAssertEqual(MapDetector.slot(for: URL(fileURLWithPath: "/tmp/wall_NormalGL.png")), .normal)
        XCTAssertTrue(MapDetector.isDirectXNormal(URL(fileURLWithPath: "/tmp/wall_NormalDX.png")))
        XCTAssertNil(MapDetector.slot(for: URL(fileURLWithPath: "/tmp/notes.png")))
    }

    func testAssetNameAndDefaultExportFolder() {
        let base = URL(fileURLWithPath: "/Textures/Brick_Wall_v2_BaseColor.png")
        XCTAssertEqual(AssetNaming.inferredAssetName(from: base), "Brick_Wall_v2")
        XCTAssertEqual(
            AssetNaming.outputDirectory(baseColorURL: base, customRoot: nil).path,
            "/Textures/CS2 Export"
        )
        XCTAssertEqual(
            AssetNaming.outputDirectory(
                baseColorURL: base,
                customRoot: URL(fileURLWithPath: "/Exports")
            ).path,
            "/Exports"
        )
    }

    func testBareMapNameFallsBackToSourceFolderName() {
        let base = URL(fileURLWithPath: "/Materials/Old_Brick/BaseColor.png")
        XCTAssertEqual(AssetNaming.inferredAssetName(from: base), "Old_Brick")
        XCTAssertEqual(
            AssetNaming.outputDirectory(baseColorURL: base, customRoot: nil).path,
            "/Materials/Old_Brick/CS2 Export"
        )
    }

    func testFolderScanSkipsDerivedExportFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2Scan-\(UUID().uuidString)", isDirectory: true)
        let previousOutput = root.appendingPathComponent("CS2 Export", isDirectory: true)
        try FileManager.default.createDirectory(at: previousOutput, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let size = PixelSize(width: 1, height: 1)
        let source = root.appendingPathComponent("Brick_BaseColor.png")
        let previous = previousOutput.appendingPathComponent("BaseColor.png")
        try ImageLoader.writePNG(solid(size, red: 1, green: 2, blue: 3), to: source)
        try ImageLoader.writePNG(solid(size, red: 4, green: 5, blue: 6), to: previous)

        XCTAssertNotNil(CGImageSourceCreateWithURL(source as CFURL, nil))
        XCTAssertTrue(MapDetector.isSupportedImage(source))
        XCTAssertEqual(MapDetector.imageURLs(in: [source]), [source])
        XCTAssertEqual(MapDetector.imageURLs(in: [root]), [source])
    }

    func testBaseColorValidation() throws {
        for dimension in [512, 1024, 2048, 4096] {
            let size = PixelSize(width: dimension, height: dimension)
            let valid = InputMap(
                slot: .baseColor,
                url: URL(fileURLWithPath: "/tmp/BaseColor.png"),
                size: size
            )
            XCTAssertEqual(try TexturePacking.validateBaseColor(valid), size)
        }

        let nonSquare = InputMap(
            slot: .baseColor,
            url: URL(fileURLWithPath: "/tmp/BaseColor.png"),
            size: PixelSize(width: 512, height: 1024)
        )
        XCTAssertThrowsError(try TexturePacking.validateBaseColor(nonSquare))

        let unsupportedMainSize = InputMap(
            slot: .baseColor,
            url: nonSquare.url,
            size: PixelSize(width: 256, height: 256)
        )
        XCTAssertThrowsError(try TexturePacking.validateBaseColor(unsupportedMainSize))
    }

    func testExportValidationRejectsUnsupportedBaseColorSize() {
        let size = PixelSize(width: 256, height: 256)
        let baseColor = InputMap(
            slot: .baseColor,
            url: URL(fileURLWithPath: "/tmp/BaseColor.png"),
            size: size
        )

        XCTAssertThrowsError(
            try TexturePacking.validateInputSizes([.baseColor: baseColor], targetSize: size)
        )
    }

    func testMainExportDimensionsMatchImported1KTexture() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2NativeMainSize-\(UUID().uuidString)", isDirectory: true)
        let output = root.appendingPathComponent("Brick CS2 textures", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let size = PixelSize(width: 1024, height: 1024)
        let baseURL = root.appendingPathComponent("Brick_BaseColor.png")
        try ImageLoader.writePNG(solid(size, red: 20, green: 40, blue: 60), to: baseURL)
        let sourceBefore = try Data(contentsOf: baseURL)
        let urls = try TexturePacking.export(
            TextureExportPlan(
                inputs: [.baseColor: InputMap(slot: .baseColor, url: baseURL, size: size)],
                targetSize: size,
                outputDirectory: output,
                assetName: "Brick"
            )
        )

        XCTAssertEqual(urls.count, 5)
        for url in urls {
            XCTAssertEqual(try ImageLoader.dimensions(of: url), size)
        }
        XCTAssertEqual(try Data(contentsOf: baseURL), sourceBefore)
    }

    func testPackingRejectsSizeMismatchWithoutResizingOrWritingOutputs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2NoResize-\(UUID().uuidString)", isDirectory: true)
        let output = root.appendingPathComponent("Brick CS2 textures", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let baseSize = PixelSize(width: 512, height: 512)
        let opacitySize = PixelSize(width: 256, height: 256)
        let baseURL = root.appendingPathComponent("Brick_BaseColor.png")
        let opacityURL = root.appendingPathComponent("Brick_Opacity.png")
        try ImageLoader.writePNG(solid(baseSize, red: 20, green: 40, blue: 60), to: baseURL)
        try ImageLoader.writePNG(solid(opacitySize, red: 170, green: 0, blue: 0), to: opacityURL)
        let baseBefore = try Data(contentsOf: baseURL)
        let opacityBefore = try Data(contentsOf: opacityURL)

        let plan = TextureExportPlan(
            inputs: [
                .baseColor: InputMap(slot: .baseColor, url: baseURL, size: baseSize),
                .opacity: InputMap(slot: .opacity, url: opacityURL, size: opacitySize)
            ],
            targetSize: baseSize,
            outputDirectory: output,
            assetName: "Brick"
        )

        XCTAssertThrowsError(try TexturePacking.export(plan)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Textures are never resized"))
            XCTAssertTrue(error.localizedDescription.contains("Opacity: 256 × 256"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try Data(contentsOf: baseURL), baseBefore)
        XCTAssertEqual(try Data(contentsOf: opacityURL), opacityBefore)
    }

    func testPackingRejectsExportSizeDifferentFromImportedBaseColor() throws {
        let size = PixelSize(width: 512, height: 512)
        let input = InputMap(
            slot: .baseColor,
            url: URL(fileURLWithPath: "/tmp/Brick_BaseColor.png"),
            size: size
        )

        XCTAssertThrowsError(
            try TexturePacking.validateInputSizes(
                [.baseColor: input],
                targetSize: PixelSize(width: 1024, height: 1024)
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("does not match the imported BaseColor size"))
            XCTAssertTrue(error.localizedDescription.contains("Textures are never resized"))
        }
    }

    func testLOD2PackingRejectsNon512InputWithoutResizing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2LOD2NoResize-\(UUID().uuidString)", isDirectory: true)
        let output = root.appendingPathComponent("LOD2", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Brick_LOD2_BaseColor.png")
        try ImageLoader.writePNG(
            solid(PixelSize(width: 1, height: 1), red: 20, green: 40, blue: 60),
            to: source
        )

        XCTAssertThrowsError(
            try LOD2TexturePacking.export(
                LOD2TextureExportPlan(
                    inputs: [.baseColor: source],
                    assetName: "Brick",
                    outputDirectory: output
                )
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("exactly 512 × 512"))
            XCTAssertTrue(error.localizedDescription.contains("Textures are never resized"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testLOD2ExportDimensionsRemain512() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2NativeLOD2Size-\(UUID().uuidString)", isDirectory: true)
        let output = root.appendingPathComponent("LOD2", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let size = PixelSize(width: 512, height: 512)
        let source = root.appendingPathComponent("Brick_LOD2_BaseColor.png")
        try ImageLoader.writePNG(solid(size, red: 20, green: 40, blue: 60), to: source)
        let urls = try LOD2TexturePacking.export(
            LOD2TextureExportPlan(
                inputs: [.baseColor: source],
                assetName: "Brick",
                outputDirectory: output
            )
        )

        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(Set(urls.map(\.lastPathComponent)), Set([
            "Brick_LOD2_BaseColor.png",
            "Brick_LOD2_Normal.png"
        ]))
        for url in urls {
            XCTAssertEqual(try ImageLoader.dimensions(of: url), size)
        }
        XCTAssertEqual(
            try firstPixel(output.appendingPathComponent("Brick_LOD2_Normal.png")),
            [128, 128, 255, 255]
        )
    }

    func testExportsFiveCorrectlyPackedPNGs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2TextureCombinerTests-\(UUID().uuidString)", isDirectory: true)
        let output = root.appendingPathComponent("Brick_Wall_v2 CS2 textures", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let size = PixelSize(width: 512, height: 512)
        let sources: [(MapSlot, (UInt8, UInt8, UInt8))] = [
            (.baseColor, (20, 40, 60)),
            (.opacity, (70, 0, 0)),
            (.cm1, (11, 0, 0)),
            (.cm2, (22, 0, 0)),
            (.cm3, (33, 0, 0)),
            (.snowRemove, (44, 0, 0)),
            (.metallic, (55, 0, 0)),
            (.coat, (66, 0, 0)),
            (.roughness, (77, 0, 0)),
            (.normal, (128, 128, 255)),
            (.emissive, (8, 9, 10))
        ]

        var inputs: [MapSlot: InputMap] = [:]
        for (slot, colour) in sources {
            let url = root.appendingPathComponent("\(slot.rawValue).png")
            if slot == .baseColor {
                try writeRGBPNG(size, red: colour.0, green: colour.1, blue: colour.2, to: url)
            } else {
                try ImageLoader.writePNG(
                    solid(size, red: colour.0, green: colour.1, blue: colour.2),
                    to: url
                )
            }
            inputs[slot] = InputMap(slot: slot, url: url, size: size)
        }

        let plan = TextureExportPlan(
            inputs: inputs,
            targetSize: size,
            outputDirectory: output,
            assetName: "Brick_Wall_v2"
        )
        XCTAssertEqual(plan.outputNames, [
            "Brick_Wall_v2_BaseColor.png",
            "Brick_Wall_v2_ControlMask.png",
            "Brick_Wall_v2_MaskMap.png",
            "Brick_Wall_v2_Normal.png",
            "Brick_Wall_v2_Emissive.png"
        ])
        let urls = try TexturePacking.export(plan)
        XCTAssertEqual(urls.count, 5)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        XCTAssertEqual(try firstPixel(output.appendingPathComponent("Brick_Wall_v2_BaseColor.png")), [20, 40, 60, 70])
        XCTAssertEqual(try firstPixel(output.appendingPathComponent("Brick_Wall_v2_ControlMask.png")), [11, 22, 33, 44])
        XCTAssertEqual(try firstPixel(output.appendingPathComponent("Brick_Wall_v2_MaskMap.png")), [55, 66, 0, 178])
        XCTAssertEqual(try firstPixel(output.appendingPathComponent("Brick_Wall_v2_Normal.png")), [128, 128, 255, 255])
        XCTAssertEqual(try firstPixel(output.appendingPathComponent("Brick_Wall_v2_Emissive.png")), [8, 9, 10, 255])
    }

    func testEmbeddedBaseColorAlphaOverridesOpacityMap() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2EmbeddedAlpha-\(UUID().uuidString)", isDirectory: true)
        let output = root.appendingPathComponent("Glass CS2 textures", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let size = PixelSize(width: 512, height: 512)
        let baseURL = root.appendingPathComponent("Glass_BaseColor.png")
        let opacityURL = root.appendingPathComponent("Glass_Opacity.png")
        try ImageLoader.writePNG(
            solid(size, red: 20, green: 40, blue: 60, alpha: 90),
            to: baseURL
        )
        try ImageLoader.writePNG(
            solid(size, red: 170, green: 0, blue: 0),
            to: opacityURL
        )

        XCTAssertTrue(try ImageLoader.hasAlphaChannel(baseURL))
        _ = try TexturePacking.export(
            TextureExportPlan(
                inputs: [
                    .baseColor: InputMap(slot: .baseColor, url: baseURL, size: size),
                    .opacity: InputMap(slot: .opacity, url: opacityURL, size: size)
                ],
                targetSize: size,
                outputDirectory: output,
                assetName: "Glass"
            )
        )

        XCTAssertEqual(
            try firstPixel(output.appendingPathComponent("Glass_BaseColor.png")),
            [20, 40, 60, 90]
        )

        _ = try TexturePacking.export(
            TextureExportPlan(
                inputs: [
                    .baseColor: InputMap(slot: .baseColor, url: baseURL, size: size),
                    .opacity: InputMap(slot: .opacity, url: opacityURL, size: size)
                ],
                targetSize: size,
                outputDirectory: output,
                assetName: "Glass",
                opacityMapOverridesBaseColorAlpha: true
            )
        )
        XCTAssertEqual(
            try firstPixel(output.appendingPathComponent("Glass_BaseColor.png")),
            [20, 40, 60, 170]
        )
    }

    func testSafeDefaults() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2TextureCombinerDefaults-\(UUID().uuidString)", isDirectory: true)
        let output = root.appendingPathComponent("Old_Brick CS2 textures", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let size = PixelSize(width: 512, height: 512)
        let baseURL = root.appendingPathComponent("BaseColor.png")
        try ImageLoader.writePNG(solid(size, red: 1, green: 2, blue: 3), to: baseURL)
        let base = InputMap(slot: .baseColor, url: baseURL, size: size)
        _ = try TexturePacking.export(
            TextureExportPlan(
                inputs: [.baseColor: base],
                targetSize: size,
                outputDirectory: output,
                assetName: "Old_Brick"
            )
        )

        XCTAssertEqual(try firstPixel(output.appendingPathComponent("Old_Brick_BaseColor.png")), [1, 2, 3, 255])
        XCTAssertEqual(try firstPixel(output.appendingPathComponent("Old_Brick_ControlMask.png")), [0, 0, 0, 0])
        XCTAssertEqual(try firstPixel(output.appendingPathComponent("Old_Brick_MaskMap.png")), [0, 0, 0, 0])
        XCTAssertEqual(try firstPixel(output.appendingPathComponent("Old_Brick_Normal.png")), [128, 128, 255, 255])
        XCTAssertEqual(try firstPixel(output.appendingPathComponent("Old_Brick_Emissive.png")), [0, 0, 0, 255])
    }

    func testNormalizingAffectsOnlyExportedNormalAndPreservesSource() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2Normalizing-\(UUID().uuidString)", isDirectory: true)
        let output = root.appendingPathComponent("Brick CS2 textures", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let size = PixelSize(width: 512, height: 512)
        let baseURL = root.appendingPathComponent("Brick_BaseColor.png")
        let normalURL = root.appendingPathComponent("Brick_NormalGL.png")
        try ImageLoader.writePNG(solid(size, red: 20, green: 40, blue: 60), to: baseURL)
        try ImageLoader.writePNG(solid(size, red: 210, green: 80, blue: 190), to: normalURL)
        let sourceBefore = try Data(contentsOf: normalURL)
        let inputs: [MapSlot: InputMap] = [
            .baseColor: InputMap(slot: .baseColor, url: baseURL, size: size),
            .normal: InputMap(slot: .normal, url: normalURL, size: size)
        ]

        _ = try TexturePacking.export(
            TextureExportPlan(
                inputs: inputs,
                targetSize: size,
                outputDirectory: output,
                assetName: "Brick"
            )
        )
        let normalOutput = output.appendingPathComponent("Brick_Normal.png")
        XCTAssertEqual(try firstPixel(normalOutput), [210, 80, 190, 255])
        XCTAssertEqual(try Data(contentsOf: normalURL), sourceBefore)

        _ = try TexturePacking.export(
            TextureExportPlan(
                inputs: inputs,
                targetSize: size,
                outputDirectory: output,
                assetName: "Brick",
                normalizeNormalOnExport: true
            )
        )
        let pixel = try firstPixel(normalOutput)
        XCTAssertNotEqual(pixel, [210, 80, 190, 255])
        let x = Double(pixel[0]) / 255.0 * 2.0 - 1.0
        let y = Double(pixel[1]) / 255.0 * 2.0 - 1.0
        let z = Double(pixel[2]) / 255.0 * 2.0 - 1.0
        XCTAssertEqual(sqrt(x * x + y * y + z * z), 1.0, accuracy: 0.01)
        XCTAssertEqual(try Data(contentsOf: normalURL), sourceBefore)

        let outputNames = try FileManager.default.contentsOfDirectory(atPath: output.path)
        XCTAssertEqual(Set(outputNames), Set([
            "Brick_BaseColor.png",
            "Brick_ControlMask.png",
            "Brick_MaskMap.png",
            "Brick_Normal.png",
            "Brick_Emissive.png"
        ]))
        XCTAssertFalse(outputNames.contains { $0.localizedCaseInsensitiveContains("normaliz") })
    }

    private func solid(
        _ size: PixelSize,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        alpha: UInt8 = 255
    ) -> ImageRaster {
        var bytes = [UInt8]()
        bytes.reserveCapacity(size.width * size.height * 4)
        for _ in 0..<(size.width * size.height) {
            bytes.append(contentsOf: [red, green, blue, alpha])
        }
        return ImageRaster(width: size.width, height: size.height, bytes: bytes)
    }

    private func writeRGBPNG(
        _ size: PixelSize,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        to url: URL
    ) throws {
        var bytes = [UInt8]()
        bytes.reserveCapacity(size.width * size.height * 3)
        for _ in 0..<(size.width * size.height) {
            bytes.append(contentsOf: [red, green, blue])
        }

        guard
            let provider = CGDataProvider(data: Data(bytes) as CFData),
            let image = CGImage(
                width: size.width,
                height: size.height,
                bitsPerComponent: 8,
                bitsPerPixel: 24,
                bytesPerRow: size.width * 3,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                "public.png" as CFString,
                1,
                nil
            )
        else {
            throw CombinerError.cannotWrite(url)
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CombinerError.cannotWrite(url)
        }
    }

    private func firstPixel(_ url: URL) throws -> [UInt8] {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let data = image.dataProvider?.data
        else {
            throw CombinerError.unreadableImage(url)
        }
        let bytes = CFDataGetBytePtr(data)!
        return Array(UnsafeBufferPointer(start: bytes, count: 4))
    }
}
