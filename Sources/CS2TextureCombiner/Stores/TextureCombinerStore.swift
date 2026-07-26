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
    @Published private(set) var isNormalizing = false
    @Published private(set) var normalizationStatus = "Assign an OpenGL Normal map to enable normalization."
    @Published private(set) var lastNormalizedURL: URL?

    var baseColor: InputMap? { inputs[.baseColor] }
    var normalInput: InputMap? { inputs[.normal] }
    var assetName: String? {
        baseColor.map { AssetNaming.inferredAssetName(from: $0.url) }
    }
    var outputFolderName: String? {
        baseColor.map { AssetNaming.outputFolderName(for: $0.url) }
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
    var canExport: Bool { baseColor != nil && !isWorking && !isNormalizing }
    var canNormalize: Bool { normalInput != nil && !isWorking && !isNormalizing }

    func input(for slot: MapSlot) -> InputMap? { inputs[slot] }

    func importDropped(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var assigned = 0
        var skipped = 0
        var directXNormals = 0

        for root in urls {
            let isDirectory = (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let candidates = MapDetector.imageURLs(in: [root])
            for candidate in candidates {
                guard let slot = MapDetector.slot(for: candidate) else {
                    skipped += 1
                    continue
                }
                if slot == .normal, MapDetector.isDirectXNormal(candidate) {
                    directXNormals += 1
                    continue
                }
                if isDirectory, inputs[slot] != nil {
                    skipped += 1
                    continue
                }
                do {
                    try assign(candidate, to: slot)
                    assigned += 1
                } catch {
                    skipped += 1
                }
            }
        }

        var message = assigned == 1 ? "Assigned 1 map." : "Assigned \(assigned) maps."
        if skipped > 0 { message += " Skipped \(skipped) unrecognised or occupied item(s)." }
        if directXNormals > 0 {
            message += " Skipped \(directXNormals) DirectX normal map(s); OpenGL is required."
        }
        status = message
    }

    func chooseImages() {
        let panel = NSOpenPanel()
        panel.title = "Add exported texture maps"
        panel.prompt = "Add Maps"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK {
            importDropped(panel.urls)
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Scan a folder for exported texture maps"
        panel.prompt = "Scan Folder"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK {
            importDropped(panel.urls)
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
        lastExportedURLs = []
        if slot == .normal {
            lastNormalizedURL = nil
            normalizationStatus = "Assign an OpenGL Normal map to enable normalization."
        }
        status = "Removed \(slot.title)."
    }

    func clear() {
        inputs.removeAll()
        lastExportedURLs = []
        lastNormalizedURL = nil
        customExportRoot = nil
        normalizationStatus = "Assign an OpenGL Normal map to enable normalization."
        status = "Cleared all assigned maps."
    }

    func chooseCustomExportLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose a location for \(outputFolderName ?? "the export folder")"
        panel.prompt = "Choose Location"
        panel.message = "The app will create \(outputFolderName ?? "the derived export folder") inside this location."
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
            status = "Output reset beside the Base Color source: \(defaultOutputDirectory.lastPathComponent)."
        }
    }

    func setCustomExportRoot(_ url: URL?) {
        customExportRoot = url
        lastExportedURLs = []
        if let outputDirectory {
            status = "Custom output selected: \(outputDirectory.path(percentEncoded: false))."
        }
    }

    func export() {
        do {
            let size = try TexturePacking.validateBaseColor(baseColor)
            guard let baseColor, let outputDirectory else {
                throw CombinerError.baseColorRequired
            }

            let mismatches = inputs.values
                .filter { $0.slot != .baseColor && $0.size != size }
                .sorted { $0.slot.title < $1.slot.title }
            if !mismatches.isEmpty, !confirmResize(mismatches, target: size) {
                status = "Export cancelled."
                return
            }

            let plan = TextureExportPlan(
                inputs: inputs,
                targetSize: size,
                outputDirectory: outputDirectory,
                assetName: AssetNaming.inferredAssetName(from: baseColor.url)
            )
            let existing = plan.outputURLs.filter {
                FileManager.default.fileExists(atPath: $0.path)
            }
            if !existing.isEmpty, !confirmOverwrite(existing) {
                status = "Export cancelled."
                return
            }

            isWorking = true
            lastExportedURLs = []
            status = "Packing five \(size.width) × \(size.height) PNGs…"
            Task {
                do {
                    let urls = try await Task.detached(priority: .userInitiated) {
                        try TexturePacking.export(plan)
                    }.value
                    self.lastExportedURLs = urls
                    self.status = "Exported five PNGs to \(plan.outputDirectory.lastPathComponent)."
                } catch {
                    self.status = error.localizedDescription
                }
                self.isWorking = false
            }
        } catch {
            status = error.localizedDescription
            presentError(error.localizedDescription)
        }
    }

    func revealOutput() {
        guard let outputDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputDirectory])
    }

    func normalizeNormal() {
        guard let normalInput else {
            normalizationStatus = "Assign an OpenGL Normal map first."
            presentError(normalizationStatus)
            return
        }

        let suggested = NormalMapNormalization.suggestedOutputURL(for: normalInput.url)
        let panel = NSSavePanel()
        panel.title = "Save Normalized Normal Map"
        panel.prompt = "Choose Destination"
        panel.message = "This creates a separate normalized map. It does not replace the Normal slot or run CS2 export."
        panel.directoryURL = suggested.deletingLastPathComponent()
        panel.nameFieldStringValue = suggested.lastPathComponent
        panel.allowedContentTypes = [NormalMapNormalization.outputType(for: normalInput.url)]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else {
            normalizationStatus = "Normalization cancelled."
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Normalize this normal map?"
        alert.informativeText = """
        Source:
        \(normalInput.url.path(percentEncoded: false))

        Destination:
        \(destination.path(percentEncoded: false))

        The selected Normal slot will remain unchanged.
        """
        alert.addButton(withTitle: "Normalize")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            normalizationStatus = "Normalization cancelled."
            return
        }

        isNormalizing = true
        lastNormalizedURL = nil
        normalizationStatus = "Normalizing \(normalInput.url.lastPathComponent)…"
        let source = normalInput.url
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try NormalMapNormalization.normalize(source, to: destination)
                }.value
                self.lastNormalizedURL = destination
                self.normalizationStatus = "Created \(destination.lastPathComponent). Normal slot unchanged."
            } catch {
                self.normalizationStatus = error.localizedDescription
                self.presentError(error.localizedDescription)
            }
            self.isNormalizing = false
        }
    }

    func revealNormalized() {
        guard let lastNormalizedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastNormalizedURL])
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
        inputs[slot] = InputMap(slot: slot, url: url, size: size)
        lastExportedURLs = []
        if slot == .normal {
            lastNormalizedURL = nil
            normalizationStatus = "Ready to normalize \(url.lastPathComponent) as a separate file."
        }
    }

    private func confirmResize(_ maps: [InputMap], target: PixelSize) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Resize companion maps?"
        alert.informativeText = """
        Base Color sets the output to \(target). These maps have different dimensions and will be resized with high-quality filtering:

        \(maps.map { "\($0.slot.title): \($0.size)" }.joined(separator: "\n"))
        """
        alert.addButton(withTitle: "Resize and Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmOverwrite(_ urls: [URL]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Replace existing exports?"
        alert.informativeText = """
        The following files already exist in \(outputFolderName ?? "the export folder"):

        \(urls.map(\.lastPathComponent).joined(separator: "\n"))
        """
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "CS2 Texture Combiner"
        alert.informativeText = message
        alert.runModal()
    }
}
