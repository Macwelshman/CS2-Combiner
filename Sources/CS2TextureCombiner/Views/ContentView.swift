import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TextureCombinerStore
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(SlotGroup.allCases) { group in
                        GroupBox(group.rawValue) {
                            VStack(spacing: 0) {
                                ForEach(Array(group.slots.enumerated()), id: \.element) { index, slot in
                                    SlotRow(slot: slot)
                                    if index < group.slots.count - 1 {
                                        Divider().padding(.leading, 42)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(minWidth: 700, idealWidth: 750, minHeight: 800, idealHeight: 880)
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CS2 Texture Combiner")
                        .font(.title2.weight(.semibold))
                    Text("Pack exported maps into five Source 2 textures.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Maps…") { store.chooseImages() }
                Button("Add Folder…") { store.chooseFolder() }
            }

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
                store.importDropped(urls)
                return true
            } isTargeted: { isDropTargeted = $0 }
        }
        .padding(18)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            normalizationRow
            Divider()

            HStack(alignment: .top) {
                Image(systemName: store.lastExportedURLs.isEmpty ? "info.circle" : "checkmark.circle.fill")
                    .foregroundStyle(store.lastExportedURLs.isEmpty ? Color.secondary : Color.green)
                Text(store.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.usesCustomOutputLocation ? "Custom CS2 output" : "Default CS2 output beside source")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(store.outputDirectory?.path(percentEncoded: false) ?? "Set by the Base Color source")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if store.usesCustomOutputLocation, let defaultPath = store.defaultOutputDirectory {
                        Text("Default beside source: \(defaultPath.path(percentEncoded: false))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Button("Choose Location…") { store.chooseCustomExportLocation() }
                    .disabled(store.baseColor == nil || store.isWorking || store.isNormalizing)
                if store.usesCustomOutputLocation {
                    Button("Use Default") { store.useDefaultExportLocation() }
                        .disabled(store.isWorking || store.isNormalizing)
                }
                Button("Clear") { store.clear() }
                    .disabled(store.inputs.isEmpty || store.isWorking || store.isNormalizing)
                if !store.lastExportedURLs.isEmpty {
                    Button("Reveal") { store.revealOutput() }
                }
                Button {
                    store.export()
                } label: {
                    if store.isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 96)
                    } else {
                        Text("Export 5 PNGs")
                            .frame(width: 96)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canExport)
                .keyboardShortcut("e")
            }
        }
        .padding(18)
    }

    private var normalizationRow: some View {
        HStack(spacing: 12) {
            Image(systemName: store.lastNormalizedURL == nil ? "waveform.path" : "checkmark.circle.fill")
                .foregroundStyle(store.lastNormalizedURL == nil ? Color.secondary : Color.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text("Normal-map utility")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(store.normalizationStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let normal = store.normalInput {
                    Text("Source remains: \(normal.url.lastPathComponent)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if store.lastNormalizedURL != nil {
                Button("Reveal Normalized") { store.revealNormalized() }
            }
            Button {
                store.normalizeNormal()
            } label: {
                if store.isNormalizing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 124)
                } else {
                    Text("Normalize Normals…")
                        .frame(width: 124)
                }
            }
            .disabled(!store.canNormalize)
        }
    }
}
