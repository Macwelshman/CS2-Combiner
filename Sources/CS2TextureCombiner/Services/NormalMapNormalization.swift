import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum NormalizationError: LocalizedError {
    case unsupportedImage
    case cannotDecode
    case cannotCreateBitmap
    case cannotCreateOutput
    case cannotWrite

    var errorDescription: String? {
        switch self {
        case .unsupportedImage: "The file is not a supported normal-map image."
        case .cannotDecode: "The normal map could not be decoded."
        case .cannotCreateBitmap: "A normalization buffer could not be created."
        case .cannotCreateOutput: "The normalized image could not be created."
        case .cannotWrite: "The normalized image could not be written."
        }
    }
}

struct NormalMapNormalization {
    static let supportedExtensions = Set([
        "png", "tif", "tiff", "bmp", "jpg", "jpeg", "heic"
    ])

    static func suggestedOutputURL(for sourceURL: URL) -> URL {
        let type = outputUTType(for: sourceURL)
        return sourceURL.deletingLastPathComponent()
            .appendingPathComponent(
                "\(sourceURL.deletingPathExtension().lastPathComponent)_normalized"
            )
            .appendingPathExtension(outputExtension(for: sourceURL, type: type))
    }

    static func outputType(for sourceURL: URL) -> UTType {
        outputUTType(for: sourceURL)
    }

    static func normalize(_ sourceURL: URL, to outputURL: URL) throws {
        guard supportedExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            throw NormalizationError.unsupportedImage
        }
        guard
            let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCache: true
            ] as CFDictionary)
        else {
            throw NormalizationError.cannotDecode
        }

        let useSixteenBit = image.bitsPerComponent > 8
        let normalizedImage = try useSixteenBit
            ? normalize16Bit(image)
            : normalize8Bit(image)
        let outputType = outputUTType(for: outputURL)
        let stagingURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".cs2-normalize-\(UUID().uuidString)")
            .appendingPathExtension(outputURL.pathExtension.isEmpty ? "png" : outputURL.pathExtension)
        defer { try? FileManager.default.removeItem(at: stagingURL) }

        guard let destination = CGImageDestinationCreateWithURL(
            stagingURL as CFURL,
            outputType.identifier as CFString,
            1,
            nil
        ) else {
            throw NormalizationError.cannotCreateOutput
        }

        var properties = (
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        ) ?? [:]
        properties[kCGImagePropertyDepth] = useSixteenBit ? 16 : 8
        CGImageDestinationAddImage(destination, normalizedImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw NormalizationError.cannotWrite
        }

        do {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: stagingURL)
            } else {
                try FileManager.default.moveItem(at: stagingURL, to: outputURL)
            }
        } catch {
            throw NormalizationError.cannotWrite
        }
    }

    static func normalizedComponents<T: BinaryInteger>(
        red: T,
        green: T,
        blue: T,
        maximum: T
    ) -> (T, T, T) {
        let maxValue = Double(maximum)
        let x = (Double(red) / maxValue) * 2.0 - 1.0
        let y = (Double(green) / maxValue) * 2.0 - 1.0
        let z = (Double(blue) / maxValue) * 2.0 - 1.0
        let length = sqrt(x * x + y * y + z * z)

        guard length > 0.000_001 else {
            return (T(maxValue * 0.5), T(maxValue * 0.5), maximum)
        }

        func encode(_ value: Double) -> T {
            let unit = max(-1.0, min(1.0, value / length))
            return T(((unit * 0.5 + 0.5) * maxValue).rounded())
        }
        return (encode(x), encode(y), encode(z))
    }

    private static func normalize8Bit(_ image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw NormalizationError.cannotCreateBitmap
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[index + 3]
            guard alpha > 0 else { continue }
            let result = normalizedComponents(
                red: unpremultiply(pixels[index], alpha: alpha, maximum: UInt8.max),
                green: unpremultiply(pixels[index + 1], alpha: alpha, maximum: UInt8.max),
                blue: unpremultiply(pixels[index + 2], alpha: alpha, maximum: UInt8.max),
                maximum: UInt8.max
            )
            pixels[index] = premultiply(result.0, alpha: alpha, maximum: UInt8.max)
            pixels[index + 1] = premultiply(result.1, alpha: alpha, maximum: UInt8.max)
            pixels[index + 2] = premultiply(result.2, alpha: alpha, maximum: UInt8.max)
        }

        guard let output = context.makeImage() else {
            throw NormalizationError.cannotCreateOutput
        }
        return output
    }

    private static func normalize16Bit(_ image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 16,
            bytesPerRow: width * 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder16Little.rawValue
        ) else {
            throw NormalizationError.cannotCreateBitmap
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[index + 3]
            guard alpha > 0 else { continue }
            let result = normalizedComponents(
                red: unpremultiply(pixels[index], alpha: alpha, maximum: UInt16.max),
                green: unpremultiply(pixels[index + 1], alpha: alpha, maximum: UInt16.max),
                blue: unpremultiply(pixels[index + 2], alpha: alpha, maximum: UInt16.max),
                maximum: UInt16.max
            )
            pixels[index] = premultiply(result.0, alpha: alpha, maximum: UInt16.max)
            pixels[index + 1] = premultiply(result.1, alpha: alpha, maximum: UInt16.max)
            pixels[index + 2] = premultiply(result.2, alpha: alpha, maximum: UInt16.max)
        }

        guard let output = context.makeImage() else {
            throw NormalizationError.cannotCreateOutput
        }
        return output
    }

    private static func unpremultiply<T: FixedWidthInteger>(
        _ component: T,
        alpha: T,
        maximum: T
    ) -> T {
        guard alpha > 0 else { return 0 }
        let result = Double(component) * Double(maximum) / Double(alpha)
        return T(min(Double(maximum), result.rounded()))
    }

    private static func premultiply<T: FixedWidthInteger>(
        _ component: T,
        alpha: T,
        maximum: T
    ) -> T {
        let result = Double(component) * Double(alpha) / Double(maximum)
        return T(min(Double(maximum), result.rounded()))
    }

    private static func outputUTType(for url: URL) -> UTType {
        switch url.pathExtension.lowercased() {
        case "tif", "tiff": .tiff
        case "bmp": .bmp
        default: .png
        }
    }

    private static func outputExtension(for sourceURL: URL, type: UTType) -> String {
        if type == .tiff {
            return sourceURL.pathExtension.lowercased() == "tiff" ? "tiff" : "tif"
        }
        if type == .bmp { return "bmp" }
        return "png"
    }
}
