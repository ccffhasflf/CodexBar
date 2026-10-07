import AppKit
import Observation
import SwiftUI

/// The same native menu + hosted usage-card structure as upstream, with one provider.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let item: NSStatusItem
    private let menu = NSMenu()
    private var settingsWindow: NSWindow?
    private let selection = SettingsSelection()
    private var stopped = false
    private var menuOpen = false

    init(model: AppModel) {
        self.model = model
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        self.menu.delegate = self
        self.menu.autoenablesItems = false
        self.menu.addItem(NSMenuItem(title: "Codex", action: nil, keyEquivalent: ""))
        self.item.menu = self.menu
        self.observeStatus()
        self.installApplicationMenu()
    }

    private func observeStatus() {
        guard !self.stopped else { return }
        withObservationTracking {
            let snapshot = self.model.status?.snapshot
            self.item.button?.image = CodexStatusIcon.make(
                windows: snapshot?.windows ?? [], stale: self.model.status?.error != nil)
            self.item.button?.toolTip = self.model.menuTitle
            self.item.button?.setAccessibilityLabel(self.model.menuTitle)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeStatus() }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        self.menuOpen = true
        menu.appearance = NSApp.effectiveAppearance
        menu.removeAllItems()
        let hosting = NSHostingView(rootView: MenuView(model: self.model))
        hosting.setFrameSize(hosting.fittingSize)
        let card = NSMenuItem()
        card.view = hosting
        menu.addItem(card)
        menu.addItem(.separator())
        self.addAction("刷新", action: #selector(self.refresh), key: "r", image: "arrow.clockwise")
        self.addAction("设置…", action: #selector(self.showSettings), key: ",", image: "gearshape")
        self.addAction("关于 CodexBar Lite", action: #selector(self.showAbout), image: "info.circle")
        self.addAction("退出", action: #selector(self.quit), key: "q", image: "xmark.rectangle")
    }

    func menuDidClose(_ menu: NSMenu) {
        self.menuOpen = false
        // Release the hosted card and its TimelineView when the menu is closed.
        DispatchQueue.main.async { [weak self, weak menu] in
            guard let self, let menu, !self.stopped, !self.menuOpen else { return }
            menu.items.first?.view = nil
        }
    }

    private func addAction(_ title: String, action: Selector, key: String = "", image: String) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        entry.image = NSImage(systemSymbolName: image, accessibilityDescription: nil)
        self.menu.addItem(entry)
    }

    @objc private func refresh() { self.model.refreshNow() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showAbout() {
        self.selection.pane = .about
        self.showSettings()
    }

    @objc func showSettings() {
        if self.settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: SettingsPane.windowWidth, height: SettingsPane.windowHeight),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: self.model, selection: self.selection))
            window.setFrameAutosaveName("LiteSettings")
            window.center()
            self.settingsWindow = window
        }
        guard let window = self.settingsWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowStageBehavior.present(window)
    }

    private func installApplicationMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        let settings = NSMenuItem(title: "设置…", action: #selector(self.showSettings), keyEquivalent: ",")
        settings.target = self
        app.addItem(settings)
        app.addItem(.separator())
        let quit = NSMenuItem(title: "退出 CodexBar Lite", action: #selector(self.quit), keyEquivalent: "q")
        quit.target = self
        app.addItem(quit)
        appItem.submenu = app
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    func stop() {
        self.stopped = true
        self.menu.cancelTracking()
        self.menu.removeAllItems()
        NSStatusBar.system.removeStatusItem(self.item)
        self.settingsWindow?.close()
    }
}
