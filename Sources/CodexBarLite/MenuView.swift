// Codex-only adaptation of upstream UsageMenuCardView / MetricRow (MIT).
import AppKit
import CodexBarLiteCore
import SwiftUI

struct MenuView: View {
    @Bindable var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 0) {
                self.header
                if let snapshot = self.model.status?.snapshot {
                    Divider()
                        .padding(.top, UsageMenuCardLayout.headerContentSpacing)
                        .padding(.bottom, UsageMenuCardLayout.postHeaderDividerContentSpacing)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot.windows) { window in
                            QuotaView(window: window, now: context.date)
                        }
                    }
                    .opacity(self.model.status?.error == nil ? 1 : 0.5)
                }
            }
            .padding(.horizontal, UsageMenuCardLayout.horizontalPadding)
            .padding(.vertical, UsageMenuCardLayout.sectionTopPadding)
            .frame(width: 310, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: UsageMenuCardLayout.headerLineSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: UsageMenuCardLayout.headerColumnSpacing) {
                Text("Codex").font(.headline).fontWeight(.semibold)
                    .lineLimit(1).layoutPriority(1)
                Spacer()
                Text(self.model.status?.snapshot?.email ?? "当前登录")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            HStack(alignment: .firstTextBaseline, spacing: UsageMenuCardLayout.headerColumnSpacing) {
                Text(self.subtitle)
                    .font(.footnote)
                    .foregroundStyle(self.model.status?.error == nil ? Color.secondary : Color.red)
                    .lineLimit(self.model.status?.error == nil ? 1 : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer()
                if let plan = self.model.status?.snapshot?.plan {
                    Text(CodexPlanFormatting.displayName(plan) ?? plan).font(.footnote).foregroundStyle(.secondary)
                        .lineLimit(1).layoutPriority(2)
                }
            }
            if self.model.status?.error != nil, self.model.status?.snapshot != nil {
                Text("上次成功获取的数据").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        if self.model.refresh.isRefreshing { return "正在刷新…" }
        if let error = self.model.status?.error { return error }
        guard let snapshot = self.model.status?.snapshot else { return "正在读取当前登录…" }
        if self.model.isDemo { return "演示 · 更新于 \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))" }
        return UsageFormatter.updatedString(from: snapshot.updatedAt)
    }
}

struct QuotaView: View {
    let window: QuotaWindow
    let now: Date

    var body: some View {
        let metric = QuotaPresentation.metric(window: self.window, now: self.now)
        MetricRow(
            metric: metric,
            layoutMetric: metric,
            title: metric.title,
            progressColor: Color(red: 73 / 255, green: 163 / 255, blue: 176 / 255))
            .help(self.window.resetsAt?.formatted(date: .abbreviated, time: .shortened) ?? "重置时间未知")
    }
}
