// Sidebar, grouped forms and dimensions adapted from upstream PreferencesView (MIT).
import AppKit
import Observation
import SwiftUI

enum SettingsPane: String, Hashable {
    case general, codex, about

    static let windowWidth: CGFloat = 880
    static let windowHeight: CGFloat = 620
    static let windowMinWidth: CGFloat = 800
    static let windowMinHeight: CGFloat = 540
    static let sidebarWidth: CGFloat = 260
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarMaxWidth: CGFloat = 380
    static let detailMaxWidth: CGFloat = 780

    var title: String {
        switch self {
        case .general: "通用"
        case .codex: "Codex"
        case .about: "关于"
        }
    }
}

@MainActor
@Observable
final class SettingsSelection {
    var pane: SettingsPane = .general
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable var selection: SettingsSelection
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settingsSidebarWidth") private var sidebarWidth: Double = SettingsPane.sidebarWidth
    @State private var detailTitlebarInset: CGFloat = 0

    private static let providerIcon: NSImage = {
        let bundle = Bundle.main.url(forResource: "CodexBarLite_CodexBarLite", withExtension: "bundle")
            .flatMap { Bundle(url: $0) } ?? Bundle.module
        let image = bundle.url(forResource: "ProviderIcon-codex", withExtension: "svg")
            .flatMap { NSImage(contentsOf: $0) } ?? NSImage()
        image.isTemplate = true
        return image
    }()

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding<SettingsPane?>(
                get: { self.selection.pane }, set: { if let value = $0 { self.selection.pane = value } }))
            {
                Section {
                    self.sidebarRow(.general, image: "gearshape.fill", color: .gray)
                    self.sidebarRow(.about, image: "info.circle.fill", color: .green)
                }
                Section("服务商") {
                    HStack(spacing: 8) {
                        Image(nsImage: Self.providerIcon)
                            .resizable().scaledToFit().frame(width: 16, height: 16)
                        Text("Codex")
                    }
                    .tag(SettingsPane.codex)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .padding(.top, 16)
            .frame(width: min(max(self.sidebarWidth, SettingsPane.sidebarMinWidth), SettingsPane.sidebarMaxWidth))
            .background { SettingsSidebarMaterial().ignoresSafeArea() }
            Divider().ignoresSafeArea()
            self.detail
                .frame(maxWidth: SettingsPane.detailMaxWidth, maxHeight: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    SettingsDetailMaterial().ignoresSafeArea()
                        .overlay {
                            SettingsTitlebarInsetReader(inset: self.$detailTitlebarInset).frame(width: 0, height: 0)
                        }
                }
                .overlay(alignment: .top) {
                    SettingsDetailTitlebarCoverMaterial()
                        .frame(height: self.detailTitlebarInset).frame(maxWidth: .infinity)
                        .ignoresSafeArea(edges: .top).allowsHitTesting(false)
                }
                .overlay(alignment: .leading) {
                    SidebarResizeHandle(
                        width: self.$sidebarWidth,
                        minWidth: SettingsPane.sidebarMinWidth,
                        maxWidth: SettingsPane.sidebarMaxWidth)
                        .frame(width: SidebarResizeHandleView.grabWidth).ignoresSafeArea()
                }
        }
        .frame(
            minWidth: SettingsPane.windowMinWidth,
            idealWidth: SettingsPane.windowWidth,
            maxWidth: .infinity,
            minHeight: SettingsPane.windowMinHeight,
            idealHeight: SettingsPane.windowHeight,
            maxHeight: .infinity)
        .background {
            SettingsWindowAppearanceBridge(colorScheme: self.colorScheme, windowTitle: self.selection.pane.title)
                .allowsHitTesting(false)
        }
    }

    private func sidebarRow(_ pane: SettingsPane, image: String, color: Color) -> some View {
        HStack(spacing: 8) {
            if pane == .about, let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: 20, height: 20)
            } else {
                SettingsIconChip(systemImage: image, color: color)
            }
            Text(pane.title)
        }
        .tag(pane)
    }

    private var detail: some View {
        Form {
            switch self.selection.pane {
            case .general: self.general
            case .codex: self.codex
            case .about: self.about
            }
            if let notice = self.model.notice {
                Section {
                    Text(notice).foregroundStyle(.red)
                    Button("关闭提示") { self.model.notice = nil }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var general: some View {
        Section("系统") {
            Toggle("登录时启动", isOn: Binding(
                get: { self.model.launchAtLogin }, set: { self.model.setLaunchAtLogin($0) }))
                .disabled(self.model.isDemo)
        }
        Section("刷新") {
            Picker("刷新间隔", selection: Binding(
                get: { self.model.configuration.refreshMinutes }, set: { self.model.setInterval($0) }))
            {
                ForEach([1, 5, 15, 30], id: \.self) { Text("每 \($0) 分钟").tag($0) }
            }
        }
        if self.model.isDemo {
            Section { SettingsSectionFooter("演示模式使用模拟额度，不读取或修改登录文件。") }
        }
    }

    @ViewBuilder
    private var codex: some View {
        Section {
            LabeledContent("账号", value: self.model.status?.snapshot?.email ?? "等待读取当前登录")
            if let plan = self.model.status?.snapshot?.plan { LabeledContent("套餐", value: plan.capitalized) }
            if let error = self.model.status?.error { Text(error).foregroundStyle(.red) }
            if let snapshot = self.model.status?.snapshot {
                ForEach(snapshot.windows) { window in
                    QuotaView(window: window, now: Date())
                }
            }
            Button(self.model.refresh.isRefreshing ? "正在刷新…" : "刷新") { self.model.refreshNow() }
                .disabled(self.model.refresh.isRefreshing)
        } header: {
            Text("用量")
        }
        Section {
            LabeledContent("来源", value: "Codex 当前登录")
            LabeledContent("登录目录") {
                Text(self.model.currentHome.path).font(.caption).textSelection(.enabled)
            }
            HStack {
                Button("选择目录…") { self.chooseHome() }
                if self.model.configuration.codexHome != nil {
                    Button("恢复默认") { self.model.setHome(nil) }
                }
            }
            .disabled(self.model.isDemo)
        } header: {
            Text("认证")
        } footer: {
            SettingsSectionFooter("跟随 Codex 中的当前登录。登录过期时请在 Codex 中重新登录。")
        }
    }

    @ViewBuilder
    private var about: some View {
        Section {
            VStack(spacing: 10) {
                if let image = NSApplication.shared.applicationIconImage {
                    Image(nsImage: image).resizable().frame(width: 92, height: 92).cornerRadius(16)
                }
                Text("CodexBar Lite").font(.title.bold())
                Text("0.3.0").font(.subheadline).foregroundStyle(.secondary)
                Text("基于 CodexBar 的 Codex 专用精简版").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .listRowBackground(Color.clear)
        }
        Section("链接") {
            Link("源代码", destination: URL(string: "https://github.com/ccffhasflf/CodexBar")!)
            Link("原版 CodexBar", destination: URL(string: "https://github.com/steipete/CodexBar")!)
        }
        Section { SettingsSectionFooter("MIT License · Peter Steinberger 与 CodexBar 贡献者") }
    }

    private func chooseHome() {
        let panel = NSOpenPanel()
        panel.title = "选择包含当前 auth.json 的 Codex 目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { self.model.setHome(url) }
    }
}
