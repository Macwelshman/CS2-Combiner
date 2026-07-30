import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class LOD2Store: ObservableObject {
    @Published private(set) var sets: [LOD2Set] = []
    @Published private(set) var status = "Drop LOD2 maps or a folder to begin."
    @Published private(set) var lastExportedURLs: [URL] = []
    @Published private(set) var isWorking = false
    @Published var useMainOutput = true
    @Published private(set) var customOutputRoot: URL?

    var canExport: Bool { !sets.isEmpty && !isWorking && (useMainOutput || customOutputRoot != nil) }
    var outputCount: Int {
        sets.reduce(0) { count, set in
            count + LOD2TextureExportPlan(inputs: set.inputs, assetName: set.name, outputDirectory: URL(fileURLWithPath: "/")).outputURLs.count
        }
    }

    func importDropped(_ urls: [URL]) {
        var grouped = Dictionary(uniqueKeysWithValues: sets.map { ($0.name, $0.inputs) })
        var imported = 0
        var rejected: [String] = []
        for url in MapDetector.imageURLs(in: urls) {
            guard let slot = Self.slot(for: url), Self.isLOD2File(url, slot: slot) else { continue }
            do {
                guard try ImageLoader.dimensions(of: url) == PixelSize(width: 512, height: 512) else {
                    rejected.append(url.lastPathComponent)
                    continue
                }
            } catch {
                rejected.append(url.lastPathComponent)
                continue
            }
            let name = setName(for: url, slot: slot)
            var inputs = grouped[name] ?? [:]
            inputs[slot] = url
            grouped[name] = inputs
            imported += 1
        }
        sets = grouped.map { LOD2Set(name: $0.key, inputs: $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        lastExportedURLs = []
        if imported > 0 {
            status = "Imported \(imported) LOD2 map\(imported == 1 ? "" : "s")."
        }
        if !rejected.isEmpty {
            status = "\(status) Skipped non-512 × 512 files: \(rejected.joined(separator: ", "))."
        }
    }

    func chooseImages() { choose(images: true) }
    func chooseFolder() { choose(images: false) }
    func clear() { sets = []; lastExportedURLs = []; status = "Cleared LOD2 maps." }

    func chooseReplacement(for setName: String, slot: LOD2Slot) {
        let panel = NSOpenPanel()
        panel.title = "Choose \(slot.title) for \(setName)"
        panel.prompt = inputs(for: setName)[slot] == nil ? "Assign" : "Replace"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard try ImageLoader.dimensions(of: url) == PixelSize(width: 512, height: 512) else {
                status = "LOD2 maps must already be 512 × 512."
                return
            }
            guard let index = sets.firstIndex(where: { $0.name == setName }) else { return }
            sets[index].inputs[slot] = url
            status = "Assigned \(slot.title) for \(setName)."
        } catch {
            status = error.localizedDescription
        }
    }

    func chooseOutput() {
        let panel = NSOpenPanel()
        panel.title = "Choose LOD2 export location"
        panel.prompt = "Choose Location"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { customOutputRoot = url; useMainOutput = false; lastExportedURLs = []; status = "LOD2 output location selected: \(url.lastPathComponent)." }
    }

    func export(mainOutputDirectory: URL?) {
        guard let root = useMainOutput ? mainOutputDirectory : customOutputRoot else { status = "Choose an LOD2 output location."; return }
        let plans = sets.map { LOD2TextureExportPlan(inputs: $0.inputs, assetName: $0.name, outputDirectory: root) }
        let planned = plans.flatMap(\.outputURLs)
        do {
            let invalid = try sets.flatMap(\.inputs).compactMap { _, source in
                try ImageLoader.dimensions(of: source) == PixelSize(width: 512, height: 512) ? nil : source
            }
            guard invalid.isEmpty else {
                status = "LOD2 maps must already be 512 × 512: \(invalid.map(\.lastPathComponent).joined(separator: ", "))."
                return
            }
        } catch {
            status = error.localizedDescription
            return
        }
        let existing = planned.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !existing.isEmpty, !confirmOverwrite(existing) {
            status = "LOD2 export cancelled."
            return
        }
        isWorking = true; status = "Exporting \(planned.count) combined 512 × 512 LOD2 textures…"
        Task {
            do {
                let urls = try await Task.detached(priority: .userInitiated) {
                    for destination in planned where FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    return try plans.flatMap { try LOD2TexturePacking.export($0) }
                }.value
                lastExportedURLs = urls
                status = "Exported \(urls.count) LOD2 texture\(urls.count == 1 ? "" : "s") to \(root.lastPathComponent)."
            } catch { status = error.localizedDescription }
            isWorking = false
        }
    }

    private func choose(images: Bool) {
        let panel = NSOpenPanel()
        panel.title = images ? "Add LOD2 maps" : "Scan a folder for LOD2 maps"
        panel.prompt = images ? "Add Maps" : "Scan Folder"
        panel.allowsMultipleSelection = images; panel.canChooseDirectories = !images; panel.canChooseFiles = images
        if images { panel.allowedContentTypes = [.image] }
        if panel.runModal() == .OK { importDropped(panel.urls) }
    }

    private func confirmOverwrite(_ urls: [URL]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = nil
        alert.messageText = "Replace existing exports"
        alert.informativeText = urls.map(\.lastPathComponent).joined(separator: "\n")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func inputs(for setName: String) -> [LOD2Slot: URL] {
        sets.first(where: { $0.name == setName })?.inputs ?? [:]
    }

    nonisolated static func isLOD2Candidate(_ url: URL) -> Bool {
        guard let slot = slot(for: url) else { return false }
        return isLOD2File(url, slot: slot)
    }

    nonisolated private static func slot(for url: URL) -> LOD2Slot? {
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "(?i)[ _.-]*lod[ _-]*2$", with: "", options: .regularExpression)
            .lowercased().filter { $0.isLetter || $0.isNumber }
        if name.contains("colormask1") || name.contains("colourmask1") || name.contains("colormaskone") || name.contains("colourmaskone") || name.contains("cm1") { return .colourMask1 }
        if name.contains("colormask2") || name.contains("colourmask2") || name.contains("colormasktwo") || name.contains("colourmasktwo") || name.contains("cm2") { return .colourMask2 }
        if name.contains("colormask3") || name.contains("colourmask3") || name.contains("colormaskthree") || name.contains("colourmaskthree") || name.contains("cm3") { return .colourMask3 }
        if name.contains("roughness") || name.contains("rough") { return .roughness }
        if name.contains("emissive") || name.contains("emission") || name.contains("emit") { return .emissive }
        if name.contains("normal") { return .normal }
        if name.contains("basecolor") || name.contains("basecolour") || name.contains("albedo") || name.contains("diffuse") { return .baseColor }
        return nil
    }

    private func setName(for url: URL, slot: LOD2Slot) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let suffix = Self.suffix(for: slot)
        let result = stem.replacingOccurrences(
            of: "(?i)[ _.-]*(?:(?:lod[ _-]*2)[ _.-]*" + suffix + "|" + suffix + "[ _.-]*(?:lod[ _-]*2))$",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: CharacterSet(charactersIn: " _.-"))
        return result.isEmpty ? AssetNaming.inferredAssetName(from: url) : result
    }

    nonisolated private static func isLOD2File(_ url: URL, slot: LOD2Slot) -> Bool {
        let suffix = suffix(for: slot)
        return url.deletingPathExtension().lastPathComponent.range(
            of: "(?i)(?:" + suffix + "[ _.-]*lod[ _-]*2|lod[ _-]*2[ _.-]*" + suffix + ")$",
            options: .regularExpression
        ) != nil
    }

    nonisolated private static func suffix(for slot: LOD2Slot) -> String {
        switch slot { case .baseColor: "(?:base[ _-]*colou?r|albedo|diffuse)"; case .colourMask1: "(?:colou?r[ _-]*mask[ _-]*(?:1|one)|cm[ _-]*1)"; case .colourMask2: "(?:colou?r[ _-]*mask[ _-]*(?:2|two)|cm[ _-]*2)"; case .colourMask3: "(?:colou?r[ _-]*mask[ _-]*(?:3|three)|cm[ _-]*3)"; case .roughness: "(?:roughness|rough)"; case .normal: "(?:normal)"; case .emissive: "(?:emissive|emission|emit)" }
    }
}
