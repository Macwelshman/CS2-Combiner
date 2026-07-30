import SwiftUI

struct SlotRow: View {
    @EnvironmentObject private var store: TextureCombinerStore
    let slot: MapSlot
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: input == nil ? "circle.dashed" : "checkmark.circle.fill")
                .foregroundStyle(input == nil ? Color.secondary : Color.green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(slot.title)
                        .fontWeight(slot.isRequired ? .semibold : .regular)
                    if slot.isRequired {
                        Text("Required")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
                Text(input.map { "\($0.url.lastPathComponent) · \($0.size)" } ?? slot.channelDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 10)

            if slot == .normal {
                Toggle(AppSpelling.normalise, isOn: Binding(
                    get: { store.normalizeNormalOnExport },
                    set: { store.setNormalizeNormalOnExport($0) }
                ))
                .toggleStyle(.checkbox)
                .disabled(input == nil)
                .help("\(AppSpelling.normalise) only the exported Normal texture; the source map remains unchanged")
            }
            if slot == .opacity {
                Toggle("Override BaseColor alpha", isOn: Binding(
                    get: { store.opacityMapOverridesBaseColorAlpha },
                    set: { store.setOpacityMapOverride($0) }
                ))
                .toggleStyle(.checkbox)
                .disabled(input == nil)
                .help("Use the assigned Opacity map even when BaseColor contains alpha")
            }
            Button(input == nil ? "Assign…" : "Replace…") {
                store.chooseReplacement(for: slot)
            }
            if input != nil {
                Button {
                    store.remove(slot)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Remove \(slot.title)")
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(
            isTargeted ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .dropDestination(for: URL.self) { urls, _ in
            store.assignDropped(urls, to: slot)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var input: InputMap? { store.input(for: slot) }

}
