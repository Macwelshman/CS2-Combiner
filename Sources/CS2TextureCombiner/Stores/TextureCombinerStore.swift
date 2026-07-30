import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class TextureCombinerStore: ObservableObject {
    @Published private(set) var inputs: [MapSlot: InputMap] = [:]
    @Published private(set) var status = "Drop exported maps or a folder to begin."
    @Published private(set) var isWorking = false
    @Published private(set) var lastExportedURLs: [URL] = []
    @Published private(set) var customExportRoot: URL?
    @Published private(set) var baseColorHasAlpha = false
    @Published private(set) var opacityMapOverridesBaseColorAlpha = false
    @Published private(set) var normalizeNormalOnExport = false

    var baseColor: InputMap? { inputs[.baseColor] }
    var normalInput: InputMap? { inputs[.normal] }
    var opacitySource: OpacitySource {
        OpacitySource.resolve(
            hasBaseColor: baseColor != nil,
            baseColorHasAlpha: baseColorHasAlpha,
            hasOpacityMap: inputs[.opacity] != nil,
            opacityMapOverridesBaseColorAlpha: opacityMapOverridesBaseColorAlpha
        )
    }
    var assetName: String? {
        baseColor.map { AssetNaming.inferredAssetName(from: $0.url) }
    }
    var defaultOutputDirectory: URL? {
        guard let baseColor else { return nil }
        return AssetNaming.outputDirectory(baseColorURL: baseColor.url, customRoot: nil)
    }
    var outputDirectory: URL? {
        guard let baseColor else { return nil }
        return AssetNaming.outputDirectory(
            baseColorURL: baseColor.url,
            customRoot: customExportRoot
        )
    }
    var usesCustomOutputLocation: Bool { customExportRoot != nil }
    var canExport: Bool { baseColor != nil && !isWorking }

    func input(for slot: MapSlot) -> InputMap? { inputs[slot] }

    func setOpacityMapOverride(_ enabled: Bool) {
        opacityMapOverridesBaseColorAlpha = enabled && inputs[.opacity] != nil
        lastExportedURLs = []
    }

    func setNormalizeNormalOnExport(_ enabled: Bool) {
        normalizeNormalOnExport = enabled && normalInput != nil
        lastExportedURLs = []
    }

    func importDropped(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var assigned = 0
        var rejected: [String] = []

        for root in urls {
            let isDirectory = (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let candidates = MapDetector.imageURLs(in: [root])
            for candidate in candidates {
                if LOD2Store.isLOD2Candidate(candidate) {
                    continue
                }
                guard let slot = MapDetector.slot(for: candidate) else {
                    continue
                }
                if slot == .normal, MapDetector.isDirectXNormal(candidate) {
                    continue
                }
                if isDirectory, inputs[slot] != nil {
                    continue
                }
                do {
                    try assign(candidate, to: slot)
                    assigned += 1
                } catch {
                    rejected.append(candidate.lastPathComponent)
                }
            }
        }

        status = "Imported \(assigned) main map\(assigned == 1 ? "" : "s")."
        if !rejected.isEmpty {
            status += " Skipped incompatible files: \(rejected.joined(separator: ", ")). Main maps must be square 1K, 2K, or 4K."
        }
    }

    func chooseImages(onSelection: (([URL]) -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Add exported texture maps"
        panel.prompt = "Add Maps"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK {
            if let onSelection { onSelection(panel.urls) } else { importDropped(panel.urls) }
        }
    }

    func chooseFolder(onSelection: (([URL]) -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Scan a folder for exported texture maps"
        panel.prompt = "Scan Folder"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK {
            if let onSelection { onSelection(panel.urls) } else { importDropped(panel.urls) }
        }
    }

    func chooseReplacement(for slot: MapSlot) {
        let panel = NSOpenPanel()
        panel.title = "Choose \(slot.title)"
        panel.prompt = inputs[slot] == nil ? "Assign" : "Replace"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        assignWithErrorHandling(url, to: slot)
    }

    func assignDropped(_ urls: [URL], to slot: MapSlot) {
        guard let url = MapDetector.imageURLs(in: urls).first else {
            status = "That item is not a readable image."
            return
        }
        assignWithErrorHandling(url, to: slot)
    }

    func remove(_ slot: MapSlot) {
        inputs.removeValue(forKey: slot)
        if slot == .baseColor {
            baseColorHasAlpha = false
        } else if slot == .opacity {
            opacityMapOverridesBaseColorAlpha = false
        } else if slot == .normal {
            normalizeNormalOnExport = false
        }
        lastExportedURLs = []
        status = "Removed \(slot.title)."
    }

    func clear() {
        inputs.removeAll()
        baseColorHasAlpha = false
        opacityMapOverridesBaseColorAlpha = false
        normalizeNormalOnExport = false
        lastExportedURLs = []
        customExportRoot = nil
        status = "Cleared all assigned maps."
    }

    func chooseCustomExportLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose export location"
        panel.prompt = "Choose Location"
        panel.message = "Exported textures will be written directly into the selected folder."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = customExportRoot ?? baseColor?.url.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            setCustomExportRoot(url)
        }
    }

    func useDefaultExportLocation() {
        customExportRoot = nil
        lastExportedURLs = []
        if let defaultOutputDirectory {
            status = "Output reset to \(defaultOutputDirectory.lastPathComponent) in the BaseColor source folder."
        }
    }

    func setCustomExportRoot(_ url: URL?) {
        customExportRoot = url
        lastExportedURLs = []
        if let outputDirectory {
            status = "Custom output selected: \(outputDirectory.path(percentEncoded: false))."
        }
    }

    func export(additionalOutputCount: Int = 0, completion: @escaping (Bool) -> Void = { _ in }) {
        do {
            let size = try TexturePacking.validateBaseColor(baseColor)
            guard let baseColor, let outputDirectory else {
                throw CombinerError.baseColorRequired
            }
            try TexturePacking.validateInputSizes(inputs, targetSize: size)

            let plan = TextureExportPlan(
                inputs: inputs,
                targetSize: size,
                outputDirectory: outputDirectory,
                assetName: AssetNaming.inferredAssetName(from: baseColor.url),
                opacityMapOverridesBaseColorAlpha: opacityMapOverridesBaseColorAlpha,
                normalizeNormalOnExport: normalizeNormalOnExport
            )
            let existing = plan.outputURLs.filter {
                FileManager.default.fileExists(atPath: $0.path)
            }
            if !existing.isEmpty, !confirmOverwrite(existing) {
                status = "Export cancelled."
                completion(false)
                return
            }

            isWorking = true
            lastExportedURLs = []
            status = additionalOutputCount > 0
                ? "Exporting 5 main textures and \(additionalOutputCount) LOD2 texture\(additionalOutputCount == 1 ? "" : "s")…"
                : "Packing five \(size.width) × \(size.height) PNGs…"
            Task {
                do {
                    let urls = try await Task.detached(priority: .userInitiated) {
                        try TexturePacking.export(plan)
                    }.value
                    self.lastExportedURLs = urls
                    self.status = "Exported 5 main textures to \(plan.outputDirectory.lastPathComponent)."
                    completion(true)
                } catch {
                    self.status = error.localizedDescription
                    completion(false)
                }
                self.isWorking = false
            }
        } catch {
            status = error.localizedDescription
            presentError(error.localizedDescription)
            completion(false)
        }
    }

    func revealOutput() {
        guard let outputDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputDirectory])
    }

    private func assignWithErrorHandling(_ url: URL, to slot: MapSlot) {
        if slot == .normal, MapDetector.isDirectXNormal(url) {
            status = "DirectX normals are not accepted. Choose an OpenGL normal map."
            presentError(status)
            return
        }
        do {
            let wasOccupied = inputs[slot] != nil
            try assign(url, to: slot)
            status = "\(wasOccupied ? "Replaced" : "Assigned") \(slot.title)."
        } catch {
            status = error.localizedDescription
            presentError(error.localizedDescription)
        }
    }

    private func assign(_ url: URL, to slot: MapSlot) throws {
        let size = try ImageLoader.dimensions(of: url)
        try TexturePacking.validateMainInputSize(size, name: slot.title)
        if slot == .baseColor {
            baseColorHasAlpha = try ImageLoader.hasAlphaChannel(url)
        }
        inputs[slot] = InputMap(slot: slot, url: url, size: size)
        lastExportedURLs = []
    }

    private func confirmOverwrite(_ urls: [URL]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = nil
        alert.messageText = "Replace existing exports"
        alert.informativeText = """
        The following files already exist in \(outputDirectory?.lastPathComponent ?? "the export folder"):

        \(urls.map(\.lastPathComponent).joined(separator: "\n"))

        If one of these files is an assigned source map, replacing it will update that source file.
        """
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "CS2 Combiner"
        alert.informativeText = message
        alert.runModal()
    }
}
