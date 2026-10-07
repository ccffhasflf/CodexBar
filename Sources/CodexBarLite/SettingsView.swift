import AppKit
import CodexBarLiteCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var removal: Account?
    @State private var renaming: Account?
    @State private var newName = ""

    var body: some View {
        Form {
            Section {
                Text("CodexBar Lite").font(.title2.weight(.semibold))
                Text("额度、重置时间与多账号。")
                    .foregroundStyle(.secondary)
            }
            Section("账号") {
                if self.model.configuration.accounts.isEmpty {
                    Text("还没有账号").foregroundStyle(.secondary)
                }
                ForEach(self.model.configuration.accounts) { account in
                    self.accountRow(account)
                }
                .disabled(self.model.isEditingAccounts || self.model.login.isRunning)
                HStack {
                    Button("添加账号…") { self.model.addAccount() }
                    Menu("关联现有登录") {
                        Button("默认 Codex 登录") {
                            let path = ProcessInfo.processInfo.environment["CODEX_HOME"]
                            let home = path.map { URL(fileURLWithPath: $0) }
                                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
                            self.model.link(home: home)
                        }
                        Button("选择 Codex 登录目录…") { self.chooseHome() }
                    }
                }
                .disabled(self.model.login.isRunning || self.model.isEditingAccounts || self.model.isDemo)
                Text("切换只影响 Lite 查看哪个账号。关联的现有登录为只读；过期后请在原 Codex 中重新登录。")
                    .font(.caption).foregroundStyle(.secondary)
                if self.model.login.isRunning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("请在浏览器中完成登录…")
                        Spacer()
                        if let url = self.model.login.authorizationURL {
                            Link("打开登录页面", destination: url)
                        }
                        Button("取消") { self.model.login.cancel() }
                    }
                }
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
                HStack {
                    Text("Codex 登录工具")
                    Spacer()
                    Text(LoginCoordinator.executable(configured: self.model.configuration.cliPath)?.lastPathComponent
                        ?? "未找到")
                        .foregroundStyle(.secondary)
                    Button("选择…") { self.chooseCLI() }
                    if !self.model.configuration.cliPath.isEmpty {
                        Button("自动") { self.model.setCLI("") }
                    }
                }
                Text("添加独立账号需要本机 Codex CLI；登录完成后，额度查询直接连接 Codex 接口。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let notice = self.model.notice {
                Section {
                    Text(notice).foregroundStyle(.orange).textSelection(.enabled)
                    Button("关闭提示") { self.model.notice = nil }
                }
            }
            Section {
                Text("0.1.0 · 基于 CodexBar · MIT License")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 580)
        .confirmationDialog(
            "移除账号？",
            isPresented: Binding(
                get: { self.removal != nil },
                set: { if !$0 { self.removal = nil } }),
            presenting: self.removal)
        { account in
            Button("移除", role: .destructive) { Task { await self.model.remove(account) } }
        } message: { account in
            Text(account.isManaged ? "将删除 Lite 保存的这个账号的登录信息。" : "将取消关联，原 Codex 登录文件保持不变。")
        }
        .alert("重命名账号", isPresented: Binding(
                get: { self.renaming != nil }, set: { if !$0 { self.renaming = nil } }))
        {
            TextField("名称", text: self.$newName)
            Button("保存") {
                if let account = self.renaming { self.model.rename(account, to: self.newName) }
            }
            Button("取消", role: .cancel) {}
            }
    }

    private func accountRow(_ account: Account) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name).lineLimit(1)
                Text(account.isManaged ? "独立登录" : "关联登录 · 只读")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = self.model.refresh.statuses[account.id]?.error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if self.model.configuration.selectedID == account.id {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal)
            } else {
                Button("查看") { self.model.select(account.id) }
            }
            Menu {
                Button("重命名…") { self.newName = account.name; self.renaming = account }
                if account.isManaged {
                    Button("重新登录…") { self.model.addAccount(replacing: account) }
                }
                Button("移除…", role: .destructive) { self.removal = account }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton)
                .fixedSize()
        }
    }

    private func chooseHome() {
        let panel = NSOpenPanel()
        panel.title = "选择包含 auth.json 的 Codex 目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { self.model.link(home: url) }
    }

    private func chooseCLI() {
        let panel = NSOpenPanel()
        panel.title = "选择 Codex 可执行文件"
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url { self.model.setCLI(url.path) }
    }
}
