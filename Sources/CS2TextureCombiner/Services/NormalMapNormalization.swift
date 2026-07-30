import Foundation

enum NormalMapNormalization {
    static func normalize(_ raster: inout ImageRaster) {
        for pixel in 0..<(raster.width * raster.height) {
            let index = pixel * 4
            let normalized = normalizedComponents(
                red: raster.bytes[index],
                green: raster.bytes[index + 1],
                blue: raster.bytes[index + 2],
                maximum: UInt8.max
            )
            raster.bytes[index] = normalized.0
            raster.bytes[index + 1] = normalized.1
            raster.bytes[index + 2] = normalized.2
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
}
