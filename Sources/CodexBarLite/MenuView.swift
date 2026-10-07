import AppKit
import CodexBarLiteCore
import SwiftUI

struct MenuView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("CodexBar Lite", systemImage: "chart.bar.fill")
                    .font(.headline)
                Spacer()
                if self.model.refresh.isRefreshing { ProgressView().controlSize(.small) }
            }
            if self.model.isDemo {
                Text("演示模式 · 模拟额度").font(.caption).foregroundStyle(.orange)
            }
            if !self.model.configuration.accounts.isEmpty {
                Picker("账号", selection: Binding(
                    get: { self.model.configuration.selectedID },
                    set: { if let id = $0 { self.model.select(id) } }))
                {
                    ForEach(self.model.configuration.accounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                .labelsHidden()
                .accessibilityLabel("查看账号")
            }
            if let status = self.model.status {
                if let snapshot = status.snapshot {
                    HStack {
                        Text(snapshot.email ?? self.model.selected?.name ?? "Codex")
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text((snapshot.plan ?? "Codex").capitalized)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(snapshot.windows) { window in
                                    QuotaView(window: window, now: context.date)
                                }
                            }
                        }
                        .frame(maxHeight: 320)
                    }
                    .opacity(status.error == nil ? 1 : 0.5)
                    Text("更新于 \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = status.error {
                    Text(error).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    if status.snapshot != nil {
                        Text("上方为上次成功获取的数据").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if status.snapshot == nil, status.error == nil {
                    Text("正在获取额度…").foregroundStyle(.secondary)
                }
            } else {
                Text(self.model.configuration.accounts.isEmpty
                    ? "添加 Codex 账号，查看剩余额度和重置时间。" : "等待刷新…")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button { self.model.refreshNow() } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(self.model.refresh.isRefreshing || self.model.configuration.accounts.isEmpty)
                Spacer()
                Button("设置") {
                    self.openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("退出") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(20)
        .frame(width: 360)
    }
}

private struct QuotaView: View {
    let window: QuotaWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(self.window.title).font(.callout.weight(.medium))
                Spacer()
                Text("剩余 \(self.window.roundedRemaining)%").monospacedDigit()
            }
            ProgressView(value: self.window.remainingPercent, total: 100)
                .tint(self.window.remainingPercent <= 10 ? .orange : .teal)
            HStack {
                Text(self.window.resetLabel(now: self.now))
                Spacer()
                if let date = self.window.resetsAt {
                    Text(date.formatted(.dateTime.month().day().hour().minute()))
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
