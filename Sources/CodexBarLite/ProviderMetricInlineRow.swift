// Upstream settings metric row (MIT); provider-independent model bridge.
import SwiftUI

struct ProviderMetricInlineRow: View {
    let metric: UsageMetric
    let title: String
    let progressColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let statusText = self.metric.statusText {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(self.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                let presentation = self.metric.linePresentation(title: self.title)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(presentation.titleText)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    if let resetText = presentation.resetText {
                        Text(resetText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                UsageProgressBar(
                    percent: self.metric.percent,
                    tint: self.progressColor,
                    accessibilityLabel: self.metric.percentStyle.accessibilityLabel,
                    pacePercent: self.metric.pacePercent,
                    paceOnTop: self.metric.paceOnTop,
                    warningMarkerPercents: self.metric.warningMarkerPercents,
                    workdayMarkerPercents: self.metric.workdayMarkerPercents,
                    workdayTickAppearance: self.metric.workdayTickAppearance)
                    .frame(maxWidth: .infinity)

                if let metaText = presentation.metaText {
                    Text(metaText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let detail = self.metric.detailText, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
