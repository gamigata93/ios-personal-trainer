import SwiftUI
import Domain
import Application

/// The Recovery section: header with the updated time, the section-level
/// notices, the full-width Sleep card and two equal compact cards (HRV and
/// resting heart rate) side by side. The mockup's scrolling row of three
/// compact cards became a 2-up row because Sleep is already full width.
struct RecoverySection: View {
    let recovery: RecoveryOverview
    let onRetry: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.recoveryTitleToCard) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recovery")
                        .font(Theme.Typography.recoveryTitle)
                        .foregroundStyle(Theme.Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Theme.Spacing.compact)
                    if let updated = recovery.updatedLabel {
                        Text(updated)
                            .font(Theme.Typography.recoveryUpdated)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .accessibilityIdentifier("recoveryUpdated")
                    }
                }
                ForEach([recovery.lockedNotice, recovery.accessNotice].compactMap { $0 }, id: \.self) { notice in
                    Text(notice)
                        .font(Theme.Typography.recoveryNotice)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(notice == recovery.lockedNotice ? "recoveryLocked" : "recoveryAccess")
                }
            }
            SleepCardView(card: recovery.sleep, onRetry: onRetry)
            // Side by side, equal width; stacked at accessibility text sizes so nothing clips.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Theme.Spacing.recoveryCardsGap))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.recoveryCardsGap))
            layout {
                CompactRecoveryCard(metric: .hrv, card: recovery.hrv, onRetry: onRetry)
                CompactRecoveryCard(metric: .restingHr, card: recovery.restingHr, onRetry: onRetry)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One compact card: HRV or resting heart rate.
struct CompactRecoveryCard: View {
    enum Metric {
        case hrv, restingHr

        var title: String {
            switch self {
            case .hrv: "HRV"
            case .restingHr: "Resting HR"
            }
        }

        var spokenTitle: String {
            switch self {
            case .hrv: "Heart rate variability"
            case .restingHr: "Resting heart rate"
            }
        }

        /// Identifier prefix: "hrv" or "restingHr".
        var id: String {
            switch self {
            case .hrv: "hrv"
            case .restingHr: "restingHr"
            }
        }

        var emptyTitle: String {
            switch self {
            case .hrv: "No overnight HRV yet"
            case .restingHr: "No resting heart rate yet"
            }
        }

        var emptyText: String {
            switch self {
            case .hrv: "Needs an Apple Watch worn during sleep."
            case .restingHr: "Apple Watch measures it through the day."
            }
        }
    }

    let metric: Metric
    let card: RecoveryMetricCard
    let onRetry: () -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Theme.Spacing.compactCardPadding)
            .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch card.body {
        case .loading:
            VStack(alignment: .leading, spacing: Theme.Spacing.compactCardRows) {
                header
                SkeletonBlock(width: Theme.Size.Skeleton.compactValue.width, height: Theme.Size.Skeleton.compactValue.height)
                SkeletonBlock(width: Theme.Size.Skeleton.compactLineWidth, height: Theme.Size.Skeleton.compactLine)
                SkeletonBlock(width: Theme.Size.Skeleton.compactShortLineWidth, height: Theme.Size.Skeleton.compactLine)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
            .accessibilityIdentifier("\(metric.id)Card")
        case .overview(let overview):
            ready(overview)
        case .noData:
            message(metric.emptyTitle, metric.emptyText)
        case .noRecent(let last):
            message("None in the last few days", last)
        case .lockedNoCache:
            message("Phone locked", "Unlock your phone to read this.")
        case .failed:
            VStack(alignment: .leading, spacing: Theme.Spacing.compactCardRows) {
                header
                Text("Couldn't read")
                    .font(Theme.Typography.compactEmptyTitle)
                    .foregroundStyle(Theme.Palette.text)
                Button("Try again", action: onRetry)
                    .buttonStyle(OutlineButtonStyle())
                    .accessibilityLabel("Try again, \(metric.spokenTitle.lowercased())")
                    .accessibilityIdentifier("\(metric.id)Retry")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(metric.id)Card")
        }
    }

    private func ready(_ overview: RecoveryMetricOverview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compactCardRows) {
            header
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.tight) {
                    Text(overview.valueText)
                        .font(Theme.Typography.compactValue)
                        .foregroundStyle(Theme.Palette.text)
                        .accessibilityIdentifier("\(metric.id)Value")
                    Text(overview.unit)
                        .font(Theme.Typography.compactUnit)
                        .foregroundStyle(Theme.Palette.mutedText)
                }
                Text(overview.label)
                    .font(Theme.Typography.compactLabel)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
            if let comparison = overview.comparison, let delta = overview.deltaText, let caption = overview.caption {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    HStack(spacing: Theme.Spacing.legendDotToText) {
                        TrendGlyph(trend: comparison.trend, color: comparison.outcome.color)
                        Text(delta)
                            .font(Theme.Typography.compactDelta)
                            .foregroundStyle(comparison.outcome.color)
                            .accessibilityIdentifier("\(metric.id)Delta")
                    }
                    Text(caption)
                        .font(Theme.Typography.compactCaption)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(overview.accessibilityLabel)
        .accessibilityIdentifier("\(metric.id)Card")
    }

    private func message(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compactCardRows) {
            header
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(title)
                    .font(Theme.Typography.compactEmptyTitle)
                    .foregroundStyle(Theme.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(text)
                    .font(Theme.Typography.compactEmptyText)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.spokenTitle). \(title). \(text)")
        .accessibilityIdentifier("\(metric.id)Card")
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.compact) {
            icon
                .frame(width: Theme.Size.sleepIconGlyph, height: Theme.Size.sleepIconGlyph)
                .frame(width: Theme.Size.sleepIcon, height: Theme.Size.sleepIcon)
                .overlay { Circle().strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth) }
            Text(metric.title)
                .font(Theme.Typography.compactTitle)
                .foregroundStyle(Theme.Palette.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch metric {
        case .hrv:
            PulseShape()
                .stroke(Theme.Palette.text, style: StrokeStyle(lineWidth: Theme.Size.pulseStroke, lineCap: .round, lineJoin: .round))
        case .restingHr:
            Image(systemName: "heart")
                .font(Theme.Typography.sleepIconGlyph)
                .foregroundStyle(Theme.Palette.text)
        }
    }
}

/// Trending up or down by the numeric direction; nothing when neutral.
struct TrendGlyph: View {
    let trend: MetricTrend
    let color: Color

    var body: some View {
        switch trend {
        case .up:
            Image(systemName: "chart.line.uptrend.xyaxis").font(Theme.Typography.trendGlyph).foregroundStyle(color)
        case .down:
            Image(systemName: "chart.line.downtrend.xyaxis").font(Theme.Typography.trendGlyph).foregroundStyle(color)
        case .neutral:
            EmptyView()
        }
    }
}

/// The mockup's pulse line, "M3 12 h4 l2-6 4 12 2-6 h6" on a 24 x 24 grid.
struct PulseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: point(3, 12))
        path.addLine(to: point(7, 12))
        path.addLine(to: point(9, 6))
        path.addLine(to: point(13, 18))
        path.addLine(to: point(15, 12))
        path.addLine(to: point(21, 12))
        return path
    }
}

private extension MetricOutcome {
    /// Better, worse or about the same. Never a rating, never the accent.
    var color: Color {
        switch self {
        case .better: Theme.Palette.outcomeBetter
        case .worse: Theme.Palette.outcomeWorse
        case .neutral: Theme.Palette.outcomeNeutral
        }
    }
}
