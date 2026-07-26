import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageRaster: Sendable {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    func red(at pixel: Int) -> UInt8 { bytes[pixel * 4] }
}

enum ImageLoader {
    static func dimensions(of url: URL) throws -> PixelSize {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw CombinerError.unreadableImage(url)
        }
        return PixelSize(width: width, height: height)
    }

    static func raster(from url: URL, target: PixelSize) throws -> ImageRaster {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        else {
            throw CombinerError.unreadableImage(url)
        }

        let byteCount = target.width * target.height * 4
        var bytes = [UInt8](repeating: 0, count: byteCount)
        // Texture channels are data, not display colour. Drawing into the
        // source colour space preserves its component values instead of
        // transforming mask bytes through the current display profile.
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let created = bytes.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let base = rawBuffer.baseAddress, let context = CGContext(
                data: base,
                width: target.width,
                height: target.height,
                bitsPerComponent: 8,
                bytesPerRow: target.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                    CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }

            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
            return true
        }
        guard created else { throw CombinerError.cannotCreateImage }

        // CGContext returns premultiplied RGB. Convert to straight bytes before
        // repacking channels so translucent source pixels preserve their colour.
        for pixel in 0..<(target.width * target.height) {
            let index = pixel * 4
            let alpha = Int(bytes[index + 3])
            guard alpha > 0, alpha < 255 else { continue }
            bytes[index] = UInt8(min(255, (Int(bytes[index]) * 255 + alpha / 2) / alpha))
            bytes[index + 1] = UInt8(min(255, (Int(bytes[index + 1]) * 255 + alpha / 2) / alpha))
            bytes[index + 2] = UInt8(min(255, (Int(bytes[index + 2]) * 255 + alpha / 2) / alpha))
        }

        return ImageRaster(width: target.width, height: target.height, bytes: bytes)
    }

    static func writePNG(_ raster: ImageRaster, to url: URL) throws {
        let data = Data(raster.bytes) as CFData
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let provider = CGDataProvider(data: data),
            let image = CGImage(
                width: raster.width,
                height: raster.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: raster.width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue |
                    CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw CombinerError.cannotWrite(url)
        }

        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyPNGDictionary: [:]
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CombinerError.cannotWrite(url)
        }
    }
}
