import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TextureCombinerStore
    @EnvironmentObject private var lod2Store: LOD2Store
    @EnvironmentObject private var updateController: AppUpdateController
    @State private var isDropTargeted = false
    @State private var showsExperimentalDecalMaps = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if updateController.state == .available || updateController.state == .downloading {
                updateBanner
            }
            Divider()
            assetTypeSelector
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            Divider()
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            mainTextureMapsHeader
                            ForEach(store.selectedAssetType.groups) { group in
                        GroupBox(group.title) {
                            VStack(spacing: 0) {
                                ForEach(Array(group.slots.enumerated()), id: \.element) { index, slot in
                                    SlotRow(slot: slot)
                                    if index < group.slots.count - 1 {
                                        Divider().padding(.leading, 42)
                                    }
                                }
                                if group.showsOpacitySource {
                                    Divider().padding(.leading, 42)
                                    HStack(spacing: 8) {
                                        Image(systemName: "circle.lefthalf.filled")
                                            .foregroundStyle(.secondary)
                                        Text(store.opacitySource.description)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                }
                            }
                            .padding(.vertical, 2)
                                }
                            }
                            if store.selectedAssetType == .decal {
                                experimentalDecalSection
                            }
                            Text(store.selectedAssetType.sizeDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 10) {
                                if let exportGuidance {
                                    Label(exportGuidance, systemImage: "info.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if !store.lastExportedURLs.isEmpty {
                                    Label(store.status, systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color.green)
                                        .lineLimit(2)
                                } else if store.selectedAssetType == .decal,
                                          store.baseColor != nil,
                                          !store.isWorking {
                                    Label(decalExportSummary, systemImage: store.decalExperimentalOutputCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(store.decalExperimentalOutputCount > 0 ? Color.orange : Color.secondary)
                                }
                                Spacer()
                                Button {
                                    store.export()
                                } label: {
                                    if store.isWorking {
                                        HStack(spacing: 7) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Exporting…")
                                        }
                                    } else {
                                        Text(exportButtonTitle)
                                    }
                                }
                                .buttonStyle(HoverButtonStyle(prominent: true))
                                .disabled(!store.canExport)
                                .keyboardShortcut("e")
                            }
                            Divider()
                            if store.selectedAssetType.supportsLOD2 {
                                LOD2View(lod2Store: lod2Store, mainOutputDirectory: store.outputDirectory)
                            }
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(minWidth: 700, idealWidth: 750, minHeight: 800, idealHeight: 880)
        .buttonStyle(HoverButtonStyle())
        .task {
            await updateController.checkForUpdates(silent: true)
        }
        .onChange(of: store.decalExperimentalMapsEnabled) { _, enabled in
            if enabled { showsExperimentalDecalMaps = true }
        }
    }

    private var updateBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("CS2 Combiner \(availableUpdateVersion) is available")
                    .font(.callout.weight(.semibold))
                Text(updateController.state == .downloading ? "Downloading and verifying the update…" : "Install it now, or review the release details first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("View Release") { updateController.openReleasePage() }
                .disabled(updateController.state == .downloading)
            Button("Later") { updateController.dismiss() }
                .disabled(updateController.state == .downloading)
            Button("Update Now") {
                Task { await updateController.installAvailableUpdate() }
            }
            .buttonStyle(HoverButtonStyle(prominent: true))
            .disabled(updateController.state == .downloading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.08))
    }

    private var availableUpdateVersion: String {
        updateController.release?.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) ?? ""
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 30, weight: .light))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drop maps or a whole folder")
                        .font(.headline)
                    Text("Recognised filenames fill their slots; drop on a row to assign manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(15)
            .background(
                isDropTargeted ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.28),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            }
            .dropDestination(for: URL.self) { urls, _ in
                importMaps(urls)
                return true
            } isTargeted: { isDropTargeted = $0 }

            statusBlock

        }
        .padding(18)
    }

    private var mainTextureMapsHeader: some View {
        HStack {
            Text("\(store.selectedAssetType.rawValue) texture maps")
                .font(.headline)
            Spacer()
            Button("Add Maps…") { store.chooseImages(onSelection: importMaps) }
            Button("Add Folder…") { store.chooseFolder(onSelection: importMaps) }
            Button("Clear") { store.clear() }
                .disabled(store.inputs.isEmpty || store.isWorking)
        }
    }

    private func importMaps(_ urls: [URL]) {
        store.importDropped(urls)
        if store.selectedAssetType.supportsLOD2 {
            lod2Store.importDropped(urls)
        }
    }

    private var assetTypeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .trailing) {
                Text("Asset type")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Picker("Asset type", selection: $store.selectedAssetType) {
                    ForEach(AssetType.allCases) { assetType in
                        Text(assetType.rawValue).tag(assetType)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            .frame(maxWidth: .infinity)
            Text(store.selectedAssetType.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !store.selectedAssetType.canExport {
                Label("Profile prepared — export packing will be added next.", systemImage: "hammer")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var experimentalDecalSection: some View {
        DisclosureGroup(isExpanded: $showsExperimentalDecalMaps) {
            VStack(alignment: .leading, spacing: 10) {
                Text("The CS2 guide states that these decal textures have not been tested and may not work as expected. Use them only for experimentation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                GroupBox("Experimental inputs") {
                    VStack(spacing: 0) {
                        ForEach(Array(AssetType.decal.experimentalSlots.enumerated()), id: \.element) { index, slot in
                            SlotRow(slot: slot)
                            if index < AssetType.decal.experimentalSlots.count - 1 {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Experimental maps (untested)", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.orange)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .onChange(of: showsExperimentalDecalMaps) { _, expanded in
            if expanded { store.enableExperimentalDecalMaps() }
        }
    }

    private var decalExportSummary: String {
        let experimental = store.decalExperimentalOutputCount
        guard experimental > 0 else { return "3 required textures" }
        return "3 required + \(experimental) experimental texture\(experimental == 1 ? "" : "s")"
    }

    private var exportButtonTitle: String {
        switch store.selectedAssetType {
        case .building:
            lod2Store.sets.isEmpty ? "Export" : "Export Main"
        case .surface:
            "Export Surface"
        case .decal:
            "Export Decal"
        }
    }

    private var exportGuidance: String? {
        if !store.selectedAssetType.canExport {
            return "Export is not available for this profile yet."
        }
        if store.baseColor == nil {
            return "Add a BaseColor map to enable export."
        }
        if store.isWorking {
            return store.status
        }
        return nil
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.usesCustomOutputLocation ? "Custom CS2 output" : "Default CS2 output: CS2 Export")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(store.outputDirectory?.path(percentEncoded: false) ?? "Set by the BaseColor source location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if store.usesCustomOutputLocation, let defaultPath = store.defaultOutputDirectory {
                        Text("Default in source folder: \(defaultPath.path(percentEncoded: false))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Button("Choose Location…") { store.chooseCustomExportLocation() }
                    .disabled(store.baseColor == nil || store.isWorking)
                if store.usesCustomOutputLocation {
                    Button("Use Default") { store.useDefaultExportLocation() }
                        .disabled(store.isWorking)
                }
                Button("Clear All") { clearAll() }
                    .disabled((store.inputs.isEmpty && lod2Store.sets.isEmpty) || store.isWorking || lod2Store.isWorking)
                if !store.lastExportedURLs.isEmpty {
                    Button("Reveal") { store.revealOutput() }
                }
                if store.selectedAssetType.supportsLOD2 && ExportAvailability.showsExportAll(
                    hasBaseColor: store.baseColor != nil,
                    hasLOD2Sets: !lod2Store.sets.isEmpty
                ) {
                    Button {
                        exportAll()
                    } label: {
                        if store.isWorking {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 96)
                        } else {
                            Text("Export All")
                                .frame(width: 96)
                        }
                    }
                    .buttonStyle(HoverButtonStyle(prominent: true))
                    .disabled(!store.canExport || lod2Store.isWorking)
                }
            }
        }
        .padding(18)
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            statusRow(store.status, isComplete: !store.lastExportedURLs.isEmpty)
            if store.selectedAssetType.supportsLOD2 && !lod2Store.sets.isEmpty {
                statusRow(lod2Store.status, isComplete: !lod2Store.lastExportedURLs.isEmpty)
            }
        }
    }

    private func exportAll() {
        guard store.selectedAssetType.supportsLOD2 else { return }
        guard !lod2Store.sets.isEmpty else {
            store.export()
            return
        }
        let lod2Count = lod2Store.outputCount
        store.export(additionalOutputCount: lod2Count) { succeeded in
            guard succeeded else { return }
            self.lod2Store.useMainOutput = true
            self.lod2Store.export(mainOutputDirectory: self.store.outputDirectory)
        }
    }

    private func clearAll() {
        store.clear()
        lod2Store.clear()
    }

    private func statusRow(_ status: String, isComplete: Bool) -> some View {
        HStack(alignment: .top) {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
            }
            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct HoverButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        HoverButtonLabel(configuration: configuration, prominent: prominent)
    }
}

private struct HoverButtonLabel: View {
    let configuration: ButtonStyle.Configuration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(prominent && isEnabled ? Color.white : Color.primary)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            .opacity(!isEnabled ? 0.42 : (configuration.isPressed ? 0.78 : 1))
            .onHover { isHovered = $0 }
    }

    private var background: Color {
        if !isEnabled { return Color.secondary.opacity(0.08) }
        if prominent { return Color.accentColor.opacity(isHovered ? 0.88 : 0.76) }
        return Color.secondary.opacity(isHovered ? 0.18 : 0.10)
    }
}
