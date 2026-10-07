import AppKit
import CodexBarLiteCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Text("CodexBar Lite").font(.title2.weight(.semibold))
                Text("跟随当前 Codex 登录，显示额度与重置时间。")
                    .foregroundStyle(.secondary)
            }
            Section("当前账号") {
                Text(self.model.status?.snapshot?.email ?? "等待读取当前登录")
                    .textSelection(.enabled)
                if let error = self.model.status?.error {
                    Text(error).font(.callout).foregroundStyle(.orange)
                }
                Text("在 Codex 中登录或切换后，这里会自动更新。登录过期时请在 Codex 中重新登录。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("登录来源") {
                Text(self.model.currentHome.appendingPathComponent("auth.json").path)
                    .font(.caption).textSelection(.enabled)
                HStack {
                    Button("选择目录…") { self.chooseHome() }
                    if self.model.configuration.codexHome != nil {
                        Button("恢复默认") { self.model.setHome(nil) }
                    }
                }
                .disabled(self.model.isDemo)
                Text("默认读取 CODEX_HOME 或 ~/.codex。只读使用当前登录，不保存账号副本，也不修改登录文件。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("基本设置") {
                Picker("自动刷新", selection: Binding(
                    get: { self.model.configuration.refreshMinutes }, set: { self.model.setInterval($0) }))
                {
                    ForEach([1, 5, 15, 30], id: \.self) { Text("每 \($0) 分钟").tag($0) }
                }
                Toggle("开机启动", isOn: Binding(
                    get: { self.model.launchAtLogin }, set: { self.model.setLaunchAtLogin($0) }))
                    .disabled(self.model.isDemo)
            }
            if let notice = self.model.notice {
                Section {
                    Text(notice).foregroundStyle(.orange).textSelection(.enabled)
                    Button("关闭提示") { self.model.notice = nil }
                }
            }
            Section {
                Text("0.2.0 · 基于 CodexBar · MIT License")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
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
