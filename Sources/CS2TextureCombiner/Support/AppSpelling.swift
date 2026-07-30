import Foundation

enum AppSpelling {
    static var colour: String { "Color" }
    static var normalise: String { normalise(for: .current) }

    static func normalise(for locale: Locale) -> String {
        let identifier = locale.identifier
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        return identifier.hasPrefix("en_us") ? "Normalize" : "Normalise"
    }
}
