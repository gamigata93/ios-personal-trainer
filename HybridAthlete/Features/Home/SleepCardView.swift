import SwiftUI
import Domain
import Application

/// The full-width Sleep card. The section header, the locked notice and the
/// Settings hint live in `RecoverySection`.
struct SleepCardView: View {
    let card: SleepCard
    let onRetry: () -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.sleepCardPadding)
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
            loading
        case .overview(let overview):
            ready(overview)
        case .noData:
            empty(title: "No sleep data yet", text: nil)
        case .noRecent(let lastRecorded):
            empty(title: "No sleep in the last few days", text: lastRecorded)
        case .emptyOrNotAllowed:
            empty(title: "No sleep data found", text: nil)
        case .lockedNoCache:
            VStack(alignment: .leading, spacing: Theme.Spacing.sleepCardRows) {
                header(nightLabel: nil)
                note("Unlock your phone to read this.")
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sleepCard")
        case .failed:
            VStack(alignment: .leading, spacing: Theme.Spacing.sleepCardRows) {
                header(nightLabel: nil)
                Text("Couldn't read sleep data.")
                    .font(Theme.Typography.sleepEmptyText)
                    .foregroundStyle(Theme.Palette.mutedText)
                Button("Try again", action: onRetry)
                    .buttonStyle(OutlineButtonStyle())
                    .accessibilityIdentifier("sleepRetry")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sleepCard")
        }
    }

    // MARK: Ready

    private func ready(_ overview: SleepOverview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sleepCardRows) {
            header(nightLabel: overview.label)

            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(overview.durationText)
                    .font(Theme.Typography.sleepDuration)
                    .foregroundStyle(Theme.Palette.text)
                    .accessibilityIdentifier("sleepDuration")
                Text(overview.windowText)
                    .font(Theme.Typography.sleepWindow)
                    .foregroundStyle(Theme.Palette.mutedText)
            }

            if let comparison = overview.comparison, let delta = overview.deltaText, let caption = overview.comparisonCaption {
                deltaRow(trend: comparison.trend, delta: delta, caption: caption)
            }

            if overview.stages.isEmpty {
                note("Sleep stages need an Apple Watch with sleep tracking.")
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.sleepRowGap) {
                    StageBar(stages: overview.stages)
                    FlowLayout(spacing: Theme.Spacing.legendItems, lineSpacing: Theme.Spacing.legendLines) {
                        ForEach(overview.stages) { stage in
                            HStack(spacing: Theme.Spacing.legendDotToText) {
                                Circle().fill(stage.kind.color).frame(width: Theme.Size.legendDot, height: Theme.Size.legendDot)
                                Text(stage.name).font(Theme.Typography.legendName).foregroundStyle(Theme.Palette.text)
                                Text(stage.durationText).font(Theme.Typography.legendValue).foregroundStyle(Theme.Palette.mutedText)
                            }
                        }
                    }
                    Text("Stages are estimated by your Apple Watch.")
                        .font(Theme.Typography.stageNote)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(overview.accessibilityLabel)
        .accessibilityIdentifier("sleepCard")
    }

    private func deltaRow(trend: SleepTrend, delta: String, caption: String) -> some View {
        let color = trend.sleepDeltaColor
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.legendDotToText) {
            switch trend {
            case .up: Image(systemName: "chart.line.uptrend.xyaxis").font(Theme.Typography.trendGlyph).foregroundStyle(color)
            case .down: Image(systemName: "chart.line.downtrend.xyaxis").font(Theme.Typography.trendGlyph).foregroundStyle(color)
            case .neutral: EmptyView()
            }
            Text(delta)
                .font(Theme.Typography.sleepDelta)
                .foregroundStyle(color)
                .accessibilityIdentifier("sleepDelta")
            Text(caption)
                .font(Theme.Typography.sleepCaption)
                .foregroundStyle(Theme.Palette.mutedText)
        }
    }

    // MARK: Parts

    private func header(nightLabel: String?) -> some View {
        HStack(spacing: Theme.Spacing.compact) {
            Image(systemName: "moon")
                .font(Theme.Typography.sleepIconGlyph)
                .foregroundStyle(Theme.Palette.text)
                .frame(width: Theme.Size.sleepIcon, height: Theme.Size.sleepIcon)
                .overlay { Circle().strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth) }
            Text("Sleep")
                .font(Theme.Typography.sleepLabel)
                .foregroundStyle(Theme.Palette.mutedText)
            Spacer(minLength: Theme.Spacing.compact)
            if let nightLabel {
                Text(nightLabel)
                    .font(Theme.Typography.sleepNightLabel)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.sleepNote)
            .foregroundStyle(Theme.Palette.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static let tip = "Turn on Track Sleep with Apple Watch and wear it to bed for at least an hour."

    private func empty(title: String, text: String?) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.selectedCardGap) {
            Image(systemName: "moon")
                .font(Theme.Typography.thumbnailGlyph)
                .foregroundStyle(Theme.Palette.mutedText)
                .frame(width: Theme.Size.sleepEmptyTile, height: Theme.Size.sleepEmptyTile)
                .background(Theme.Palette.thumbnail, in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                        .strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth)
                }
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(title)
                    .font(Theme.Typography.sleepEmptyTitle)
                    .foregroundStyle(Theme.Palette.text)
                ForEach([text, Self.tip].compactMap { $0 }, id: \.self) { line in
                    Text(line)
                        .font(Theme.Typography.sleepEmptyText)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sleepCard")
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sleepCardRows) {
            header(nightLabel: nil)
            SkeletonBlock(width: Theme.Size.Skeleton.sleepNumber.width, height: Theme.Size.Skeleton.sleepNumber.height)
            SkeletonBlock(width: Theme.Size.Skeleton.sleepLineWidth, height: Theme.Size.Skeleton.textLine)
            SkeletonBlock(height: Theme.Size.stageBar, radius: Theme.Radius.stageBar)
            SkeletonBlock(width: Theme.Size.Skeleton.legendLine.width, height: Theme.Size.Skeleton.legendLine.height)
            SkeletonBlock(width: Theme.Size.Skeleton.legendShortLine.width, height: Theme.Size.Skeleton.legendShortLine.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
        .accessibilityIdentifier("sleepCard")
    }
}

/// Deep, core, REM and awake side by side, proportional to their minutes, with
/// 2 pt gaps and every stage at least 3 pt wide.
private struct StageBar: View {
    let stages: [SleepOverview.Stage]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: Theme.Spacing.stageGap) {
                ForEach(Array(zip(stages, widths(total: proxy.size.width))), id: \.0.id) { stage, width in
                    RoundedRectangle(cornerRadius: Theme.Radius.stageBar, style: .continuous)
                        .fill(stage.kind.color)
                        .frame(width: width)
                }
            }
        }
        .frame(height: Theme.Size.stageBar)
        .accessibilityHidden(true)
    }

    /// Proportional widths; stages under the minimum are raised to it and the
    /// rest shrink to make room.
    private func widths(total: CGFloat) -> [CGFloat] {
        let available = max(0, total - Theme.Spacing.stageGap * CGFloat(max(stages.count - 1, 0)))
        let minutes = CGFloat(stages.map(\.minutes).reduce(0, +))
        guard minutes > 0 else { return stages.map { _ in 0 } }
        let raw = stages.map { CGFloat($0.minutes) / minutes * available }
        let minimum = Theme.Size.minStageWidth
        let small = raw.filter { $0 < minimum }
        let largeTotal = raw.filter { $0 >= minimum }.reduce(0, +)
        let room = available - minimum * CGFloat(small.count)
        let scale = largeTotal > 0 ? room / largeTotal : 0
        return raw.map { $0 < minimum ? minimum : $0 * scale }
    }
}

/// Lays children out left to right and wraps to a new line when out of room.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

private extension SleepOverview.Stage.Kind {
    var color: Color {
        switch self {
        case .deep: Theme.Palette.StageColors.deep
        case .core: Theme.Palette.StageColors.core
        case .rem: Theme.Palette.StageColors.rem
        case .awake: Theme.Palette.StageColors.awake
        }
    }
}

extension MetricTrend {
    /// Delta colors only, never ratings.
    var sleepDeltaColor: Color {
        switch self {
        case .up: Theme.Palette.deltaUp
        case .down: Theme.Palette.deltaDown
        case .neutral: Theme.Palette.deltaNeutral
        }
    }
}
