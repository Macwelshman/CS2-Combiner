import SwiftUI

struct LOD2View: View {
    @ObservedObject var lod2Store: LOD2Store
    let mainOutputDirectory: URL?
    @State private var isDropTargeted = false

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LOD2 texture maps").font(.headline)
                    }
                    Spacer()
                    Button("Add Maps…") { lod2Store.chooseImages() }
                    Button("Add Folder…") { lod2Store.chooseFolder() }
                    Button("Clear") { lod2Store.clear() }.disabled(lod2Store.sets.isEmpty || lod2Store.isWorking)
                }
                ForEach(lod2Store.sets) { set in
                    GroupBox(set.name) {
                        VStack(spacing: 0) {
                            ForEach(Array(LOD2Slot.allCases.enumerated()), id: \.element) { index, slot in
                                LOD2SlotRow(slot: slot, sourceURL: set.inputs[slot]) {
                                    lod2Store.chooseReplacement(for: set.name, slot: slot)
                                }
                                if index < LOD2Slot.allCases.count - 1 {
                                    Divider().padding(.leading, 42)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                if lod2Store.sets.isEmpty { Text("No LOD2 maps imported.").foregroundStyle(.secondary) }
                Toggle("Export in the main texture folder", isOn: $lod2Store.useMainOutput)
                    .disabled(mainOutputDirectory == nil)
                if mainOutputDirectory == nil && lod2Store.customOutputRoot == nil {
                    Text("Add a main Base Color to use its texture folder, or choose a separate LOD2 location.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(lod2Store.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !lod2Store.sets.isEmpty {
                        Button("Choose Location…") { lod2Store.chooseOutput() }
                        Button(lod2Store.isWorking ? "Exporting…" : "Export LOD2") { lod2Store.export(mainOutputDirectory: mainOutputDirectory) }
                            .buttonStyle(HoverButtonStyle(prominent: true))
                            .disabled(!lod2Store.canExport || (lod2Store.useMainOutput && mainOutputDirectory == nil))
                    }
                }
            }
            .padding(.vertical, 2)
            .dropDestination(for: URL.self) { urls, _ in lod2Store.importDropped(urls); return true } isTargeted: { isDropTargeted = $0 }
        }
    }
}

private struct LOD2SlotRow: View {
    let slot: LOD2Slot
    let sourceURL: URL?
    let chooseReplacement: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sourceURL == nil ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(sourceURL == nil ? Color.secondary : Color.green)
                .font(.title3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title)
                    .fontWeight(.medium)
                Text(sourceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(sourceURL == nil ? "Assign…" : "Replace…") {
                chooseReplacement()
            }
        }
        .padding(.vertical, 7)
    }

    private var sourceDescription: String {
        guard let sourceURL else {
            return slot == .normal ? "Not added — flat normal exported" : "Not added — not exported"
        }
        let size = (try? ImageLoader.dimensions(of: sourceURL)).map { " · \($0)" } ?? ""
        return sourceURL.lastPathComponent + size
    }
}
