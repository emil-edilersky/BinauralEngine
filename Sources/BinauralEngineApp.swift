import SwiftUI
import AppKit

/// Main application entry point for BinauralEngine.
///
/// A menu bar-only macOS app that generates pure binaural beats.
/// Runs entirely in the menu bar with no dock icon.
@main
struct BinauralEngineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.appState)
        } label: {
            Image(systemName: appDelegate.appState.isPlaying ? "waveform.circle.fill" : "waveform.circle")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Application delegate managing lifecycle and initialization.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.initialize()
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.cleanup()
    }
}
