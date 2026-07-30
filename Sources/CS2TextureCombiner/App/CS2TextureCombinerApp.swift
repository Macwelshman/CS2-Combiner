import AppKit
import SwiftUI

@main
struct CS2TextureCombinerApp: App {
    @NSApplicationDelegateAdaptor(CombinerAppDelegate.self) private var appDelegate
    @StateObject private var store: TextureCombinerStore
    @StateObject private var lod2Store: LOD2Store

    init() {
        let store = TextureCombinerStore()
        _store = StateObject(wrappedValue: store)
        _lod2Store = StateObject(wrappedValue: LOD2Store())
        CombinerAppDelegate.sharedStore = store
    }

    var body: some Scene {
        WindowGroup("CS2 Combiner") {
            ContentView()
                .environmentObject(store)
                .environmentObject(lod2Store)
        }
        .defaultSize(width: 720, height: 790)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Maps…") { store.chooseImages() }
                    .keyboardShortcut("o")
                Button("Add Folder…") { store.chooseFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("Texture") {
                Button("Export Main Textures") { store.export() }
                    .keyboardShortcut("e")
                    .disabled(!store.canExport)
                Button("Export LOD2") { lod2Store.export(mainOutputDirectory: store.outputDirectory) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!lod2Store.canExport || (lod2Store.useMainOutput && store.outputDirectory == nil))
                Button("Export All") { exportAll() }
                    .disabled(
                        !ExportAvailability.showsExportAll(
                            hasBaseColor: store.baseColor != nil,
                            hasLOD2Sets: !lod2Store.sets.isEmpty
                        ) || store.isWorking || lod2Store.isWorking
                    )
                Divider()
                Button("Clear All") { store.clear() }
                    .disabled(store.inputs.isEmpty)
            }
        }
    }

    private func exportAll() {
        let lod2Count = lod2Store.outputCount
        store.export(additionalOutputCount: lod2Count) { succeeded in
            guard succeeded else { return }
            self.lod2Store.useMainOutput = true
            self.lod2Store.export(mainOutputDirectory: self.store.outputDirectory)
        }
    }
}

@MainActor
final class CombinerAppDelegate: NSObject, NSApplicationDelegate {
    static var sharedStore: TextureCombinerStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Self.sharedStore?.importDropped(urls)
    }
}
