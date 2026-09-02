import AppKit
import CryptoKit
import Foundation

struct AppVersion: Comparable, Equatable, Sendable {
    let components: [Int]

    init?(_ value: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let core = cleaned.split(whereSeparator: { $0 == "-" || $0 == "+" }).first ?? ""
        let parsed = core.split(separator: ".").map(String.init)
        guard !parsed.isEmpty, parsed.allSatisfy({ Int($0) != nil }) else { return nil }
        components = parsed.map { Int($0)! }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

struct GitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name, digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case name, body, draft, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    var version: AppVersion? { AppVersion(tagName) }

    func macOSAsset() -> Asset? {
        assets.first { $0.name.lowercased().hasSuffix("-macos.zip") }
    }
}

enum AppUpdateError: LocalizedError {
    case invalidResponse
    case invalidRelease
    case missingAsset
    case missingDigest
    case digestMismatch
    case invalidPackage
    case unwritableInstallation
    case translocatedApplication

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The update server returned an invalid response."
        case .invalidRelease: "The latest release has an invalid version."
        case .missingAsset: "The release does not include a macOS update."
        case .missingDigest: "The update has no published SHA-256 digest and cannot be installed safely."
        case .digestMismatch: "The downloaded update did not match its published SHA-256 digest."
        case .invalidPackage: "The downloaded update is not a valid CS2 Combiner application."
        case .unwritableInstallation: "CS2 Combiner cannot update this copy in place. Move it to a folder you can write to, then try again."
        case .translocatedApplication: "Move CS2 Combiner to Applications before updating it."
        }
    }
}

struct AppUpdateService: Sendable {
    static let releasesURL = URL(string: "https://api.github.com/repos/Macwelshman/CS2-Combiner/releases/latest")!
    static let bundleIdentifier = "com.ianmaclarty.CS2TextureCombiner"

    func latestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.releasesURL)
        request.setValue("CS2-Combiner-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppUpdateError.invalidResponse
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease, release.version != nil else {
            throw AppUpdateError.invalidRelease
        }
        return release
    }

    func downloadAndStage(_ release: GitHubRelease, currentBundle: URL) async throws -> URL {
        guard !currentBundle.path.contains("/AppTranslocation/") else {
            throw AppUpdateError.translocatedApplication
        }
        guard FileManager.default.isWritableFile(atPath: currentBundle.deletingLastPathComponent().path) else {
            throw AppUpdateError.unwritableInstallation
        }
        guard let asset = release.macOSAsset() else { throw AppUpdateError.missingAsset }
        guard let expectedDigest = asset.digest?.lowercased(), expectedDigest.hasPrefix("sha256:") else {
            throw AppUpdateError.missingDigest
        }

        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("CS2-Combiner-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        let (temporaryDownload, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppUpdateError.invalidResponse
        }
        let data = try Data(contentsOf: temporaryDownload, options: .mappedIfSafe)
        let actualDigest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard expectedDigest == "sha256:\(actualDigest)" else { throw AppUpdateError.digestMismatch }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CS2CombinerUpdate-\(UUID().uuidString)", isDirectory: true)
        let archive = root.appendingPathComponent(asset.name)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: temporaryDownload, to: archive)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])

        guard let app = try findApplication(in: staging),
              let info = Bundle(url: app),
              info.bundleIdentifier == Self.bundleIdentifier,
              let packagedVersion = info.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              AppVersion(packagedVersion) == release.version else {
            throw AppUpdateError.invalidPackage
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        return app
    }

    func launchInstaller(stagedApplication: URL, currentBundle: URL) throws {
        let helper = stagedApplication.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("install-update.sh")
        let script = """
        #!/bin/sh
        pid="$1"
        source_app="$2"
        destination_app="$3"
        backup_app="${destination_app}.update-backup.$$"
        attempts=0
        while /bin/kill -0 "$pid" 2>/dev/null && [ "$attempts" -lt 300 ]; do
          /bin/sleep 0.1
          attempts=$((attempts + 1))
        done
        if ! /bin/mv "$destination_app" "$backup_app"; then
          /usr/bin/open "$destination_app"
          exit 1
        fi
        if /usr/bin/ditto "$source_app" "$destination_app"; then
          /bin/rm -rf "$backup_app"
          /usr/bin/open "$destination_app"
          exit 0
        fi
        /bin/rm -rf "$destination_app"
        if [ -e "$backup_app" ]; then /bin/mv "$backup_app" "$destination_app"; fi
        /usr/bin/open "$destination_app"
        exit 1
        """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [helper.path, String(ProcessInfo.processInfo.processIdentifier), stagedApplication.path, currentBundle.path]
        try process.run()
    }

    private func findApplication(in directory: URL) throws -> URL? {
        let children = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return children.first { $0.pathExtension == "app" && $0.lastPathComponent == "CS2 Combiner.app" }
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "CS2CombinerUpdater", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}

@MainActor
final class AppUpdateController: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case available
        case downloading
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var release: GitHubRelease?
    private let service = AppUpdateService()
    private let fallbackVersion = "0.3.3"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackVersion
    }

    func checkForUpdates(silent: Bool) async {
        guard state != .checking && state != .downloading else { return }
        state = .checking
        do {
            let latest = try await service.latestRelease()
            if let current = AppVersion(currentVersion), let available = latest.version, available > current {
                release = latest
                state = .available
            } else {
                release = nil
                state = .idle
                if !silent { showMessage("CS2 Combiner is up to date.") }
            }
        } catch {
            state = silent ? .idle : .failed(error.localizedDescription)
            if !silent { showMessage(error.localizedDescription) }
        }
    }

    func installAvailableUpdate() async {
        guard let release else { return }
        state = .downloading
        do {
            let staged = try await service.downloadAndStage(release, currentBundle: Bundle.main.bundleURL)
            try service.launchInstaller(stagedApplication: staged, currentBundle: Bundle.main.bundleURL)
            NSApplication.shared.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
            showMessage(error.localizedDescription)
        }
    }

    func dismiss() {
        release = nil
        state = .idle
    }

    func openReleasePage() {
        guard let release else { return }
        NSWorkspace.shared.open(release.htmlURL)
    }

    private func showMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "CS2 Combiner Updates"
        alert.informativeText = message
        alert.runModal()
    }
}
