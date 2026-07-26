import Foundation
import ImageIO
import XCTest
@testable import CS2TextureCombiner

final class CS2TextureCombinerTests: XCTestCase {
    func testFilenameDetection() {
        XCTAssertEqual(MapDetector.slot(for: URL(fileURLWithPath: "/tmp/wall_BaseColor.png")), .baseColor)
        XCTAssertEqual(MapDetector.slot(for: URL(fileURLWithPath: "/tmp/wall_CM2.tif")), .cm2)
        XCTAssertEqual(MapDetector.slot(for: URL(fileURLWithPath: "/tmp/wall_Snow_Remove.png")), .snowRemove)
        XCTAssertEqual(MapDetector.slot(for: URL(fileURLWithPath: "/tmp/wall_NormalGL.png")), .normal)
        XCTAssertTrue(MapDetector.isDirectXNormal(URL(fileURLWithPath: "/tmp/wall_NormalDX.png")))
        XCTAssertNil(MapDetector.slot(for: URL(fileURLWithPath: "/tmp/notes.png")))
    }

    func testAssetNameAndDerivedOutputFolder() {
        let base = URL(fileURLWithPath: "/Textures/Brick_Wall_v2_BaseColor.png")
        XCTAssertEqual(AssetNaming.inferredAssetName(from: base), "Brick_Wall_v2")
        XCTAssertEqual(AssetNaming.outputFolderName(for: base), "Brick_Wall_v2 CS2 textures")
        XCTAssertEqual(
            AssetNaming.outputDirectory(baseColorURL: base, customRoot: nil).path,
            "/Textures/Brick_Wall_v2 CS2 textures"
        )
        XCTAssertEqual(
            AssetNaming.outputDirectory(
                baseColorURL: base,
                customRoot: URL(fileURLWithPath: "/Exports")
            ).path,
            "/Exports/Brick_Wall_v2 CS2 textures"
        )
    }

    func testBareMapNameFallsBackToSourceFolderName() {
        let base = URL(fileURLWithPath: "/Materials/Old_Brick/BaseColor.png")
        XCTAssertEqual(AssetNaming.inferredAssetName(from: base), "Old_Brick")
        XCTAssertEqual(AssetNaming.outputFolderName(for: base), "Old_Brick CS2 textures")
    }

    func testFolderScanSkipsDerivedExportFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2Scan-\(UUID().uuidString)", isDirectory: true)
        let previousOutput = root.appendingPathComponent("Brick CS2 textures", isDirectory: true)
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
        let valid = InputMap(
            slot: .baseColor,
            url: URL(fileURLWithPath: "/tmp/BaseColor.png"),
            size: PixelSize(width: 512, height: 512)
        )
        XCTAssertEqual(try TexturePacking.validateBaseColor(valid), PixelSize(width: 512, height: 512))

        let nonSquare = InputMap(
            slot: .baseColor,
            url: valid.url,
            size: PixelSize(width: 512, height: 1024)
        )
        XCTAssertThrowsError(try TexturePacking.validateBaseColor(nonSquare))
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
            try ImageLoader.writePNG(
                solid(size, red: colour.0, green: colour.1, blue: colour.2),
                to: url
            )
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

    func testNormalizingCreatesSeparateOutputAndPreservesSource() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2Normalizing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Brick_NormalGL.png")
        let output = root.appendingPathComponent("Brick_NormalGL_normalized.png")
        let size = PixelSize(width: 1, height: 1)
        try ImageLoader.writePNG(solid(size, red: 210, green: 80, blue: 190), to: source)
        let sourceBefore = try Data(contentsOf: source)

        try NormalMapNormalization.normalize(source, to: output)

        XCTAssertEqual(try Data(contentsOf: source), sourceBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let pixel = try firstPixel(output)
        let x = Double(pixel[0]) / 255.0 * 2.0 - 1.0
        let y = Double(pixel[1]) / 255.0 * 2.0 - 1.0
        let z = Double(pixel[2]) / 255.0 * 2.0 - 1.0
        XCTAssertEqual(sqrt(x * x + y * y + z * z), 1.0, accuracy: 0.01)
    }

    private func solid(
        _ size: PixelSize,
        red: UInt8,
        green: UInt8,
        blue: UInt8
    ) -> ImageRaster {
        var bytes = [UInt8]()
        bytes.reserveCapacity(size.width * size.height * 4)
        for _ in 0..<(size.width * size.height) {
            bytes.append(contentsOf: [red, green, blue, 255])
        }
        return ImageRaster(width: size.width, height: size.height, bytes: bytes)
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
