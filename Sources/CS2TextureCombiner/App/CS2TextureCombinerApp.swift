import AppKit
import SwiftUI

@main
struct CS2TextureCombinerApp: App {
    @NSApplicationDelegateAdaptor(CombinerAppDelegate.self) private var appDelegate
    @StateObject private var store: TextureCombinerStore

    init() {
        let store = TextureCombinerStore()
        _store = StateObject(wrappedValue: store)
        CombinerAppDelegate.sharedStore = store
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
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
                Button("Export 5 PNGs") { store.export() }
                    .keyboardShortcut("e")
                    .disabled(!store.canExport)
                Button("Normalize Normals…") { store.normalizeNormal() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!store.canNormalize)
                Divider()
                Button("Clear All") { store.clear() }
                    .disabled(store.inputs.isEmpty)
            }
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
