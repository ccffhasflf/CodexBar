import AppKit

@main
@MainActor
enum CodexBarLiteApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = LiteAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class LiteAppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty { NSApp.terminate(nil); return }
        }
        do {
            let model = try AppModel(demo: CommandLine.arguments.contains("--demo"))
            self.model = model
            self.controller = StatusItemController(model: model)
            model.start()
            if CommandLine.arguments.contains("--settings") { self.controller?.showSettings() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "CodexBar Lite 无法加载配置"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        self.controller?.stop()
        self.model?.stop()
    }
}
