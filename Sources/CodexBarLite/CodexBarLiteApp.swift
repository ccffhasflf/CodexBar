import AppKit
import SwiftUI

@main
struct CodexBarLiteApp: App {
    @NSApplicationDelegateAdaptor(LiteAppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        do {
            let demo = CommandLine.arguments.contains("--demo")
            _model = try State(initialValue: AppModel(demo: demo))
        } catch {
            let alert = NSAlert()
            alert.messageText = "CodexBar Lite 无法加载配置"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            exit(1)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: self.model)
                .onAppear { self.delegate.model = self.model }
        } label: {
            Text(self.model.menuTitle)
                .monospacedDigit()
                .task {
                    self.delegate.model = self.model
                    self.model.start()
                }
        }
        .menuBarExtraStyle(.window)

        Window("CodexBar Lite 设置", id: "settings") {
            SettingsView(model: self.model)
        }
        .defaultSize(width: 560, height: 540)
        .windowResizability(.contentSize)
    }
}

@MainActor
final class LiteAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let identifier = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty { NSApp.terminate(nil) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { self.model?.stop() }
}
