import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TextureCombinerStore
    @EnvironmentObject private var lod2Store: LOD2Store
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            mainTextureMapsHeader
                            ForEach(SlotGroup.allCases) { group in
                        GroupBox(group.rawValue) {
                            VStack(spacing: 0) {
                                ForEach(Array(group.slots.enumerated()), id: \.element) { index, slot in
                                    SlotRow(slot: slot)
                                    if index < group.slots.count - 1 {
                                        Divider().padding(.leading, 42)
                                    }
                                }
                                if group == .baseColor {
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
                            HStack {
                                Spacer()
                                Button(lod2Store.sets.isEmpty ? "Export" : "Export Main") { store.export() }
                                    .buttonStyle(HoverButtonStyle(prominent: true))
                                    .disabled(!store.canExport)
                                    .keyboardShortcut("e")
                            }
                            Divider()
                            LOD2View(lod2Store: lod2Store, mainOutputDirectory: store.outputDirectory)
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(minWidth: 700, idealWidth: 750, minHeight: 800, idealHeight: 880)
        .buttonStyle(HoverButtonStyle())
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
            Text("Main texture maps")
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
        lod2Store.importDropped(urls)
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
                if ExportAvailability.showsExportAll(
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
            if !lod2Store.sets.isEmpty {
                statusRow(lod2Store.status, isComplete: !lod2Store.lastExportedURLs.isEmpty)
            }
        }
    }

    private func exportAll() {
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
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .onHover { isHovered = $0 }
    }

    private var background: Color {
        if prominent { return Color.accentColor.opacity(isHovered ? 0.88 : 0.76) }
        return Color.secondary.opacity(isHovered ? 0.18 : 0.10)
    }
}
