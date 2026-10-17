import SwiftUI
import Charts
import Domain
import Application

/// The result tiles of a completed run: a wrapping grid.
struct WorkoutTilesView: View {
    let tiles: [WorkoutBreakdown.Tile]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Size.tileMinWidth), spacing: Theme.Spacing.statTiles)], spacing: Theme.Spacing.statTiles) {
            ForEach(tiles) { tile in
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(tile.label)
                        .font(Theme.Typography.tileLabel)
                        .foregroundStyle(Theme.Palette.mutedText)
                    Text(tile.value)
                        .font(Theme.Typography.tileValue)
                        .foregroundStyle(Theme.Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let detail = tile.detail {
                        Text(detail)
                            .font(Theme.Typography.tileDetail)
                            .foregroundStyle(Theme.Palette.softText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Theme.Spacing.statTilePadding)
                .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.statTile, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.statTile, style: .continuous)
                        .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tile.spoken)
                .accessibilityIdentifier("workoutTile-\(tile.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workoutTiles")
    }
}

/// A titled breakdown card (radius 24, card fill, 1 pt border).
struct BreakdownCard<Content: View>: View {
    let title: String
    var trailing: String?
    let identifier: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.breakdownRows) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.Typography.breakdownTitle)
                    .foregroundStyle(Theme.Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Theme.Spacing.compact)
                if let trailing {
                    Text(trailing)
                        .font(Theme.Typography.breakdownFootnote)
                        .foregroundStyle(Theme.Palette.mutedText)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.breakdownCardPadding)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// Pace per km as bars (height proportional to speed, the partial last split
/// narrower), the pace above each bar, the average heart rate under it, and the
/// planned blocks over their km ranges.
struct SplitsCardView: View {
    let breakdown: WorkoutBreakdown

    var body: some View {
        BreakdownCard(title: "Splits", trailing: "Pace per km", identifier: "splitsChart") {
            Chart(breakdown.splits) { split in
                bar(split)
            }
            .chartXScale(domain: 0...max(breakdown.totalKm, 1))
            .chartYScale(domain: 0...((breakdown.splits.map(\.speed).max() ?? 1) * 1.15))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: Theme.Size.splitsChartHeight)
            .padding(.top, Theme.Spacing.compact)
            .padding(.bottom, Theme.Spacing.breakdownRows * 2)
            .accessibilityLabel(breakdown.splitsSummary ?? "Splits")
            .accessibilityChildren {
                ForEach(breakdown.splits) { Text($0.spoken) }
            }
            if !breakdown.blockSpans.isEmpty {
                BlockStrip(spans: breakdown.blockSpans, totalKm: breakdown.totalKm)
            }
        }
    }
}

extension SplitsCardView {
    /// One split: a bar from its km start to its end, the pace on top, the km and
    /// heart rate under it.
    @ChartContentBuilder
    func bar(_ split: WorkoutBreakdown.SplitBar) -> some ChartContent {
        let start = Double(split.index - 1)
        let end = start + split.km
        // A small inset on each side leaves a gap between neighbouring kilometres.
        let inset = min(0.11, split.km * 0.11)
        RectangleMark(
            xStart: .value("Start", start + inset), xEnd: .value("End", end - inset),
            yStart: .value("Base", 0), yEnd: .value("Speed", split.speed)
        )
            .foregroundStyle(Theme.Palette.splitBar)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.stageBar, style: .continuous))
            .annotation(position: .top, spacing: Theme.Spacing.splitBarGap) { paceLabel(split) }
            .annotation(position: .bottom, spacing: Theme.Spacing.splitBarGap) { underLabel(split) }
    }

    private func paceLabel(_ split: WorkoutBreakdown.SplitBar) -> some View {
        Text(split.paceText)
            .font(Theme.Typography.splitPace)
            .foregroundStyle(Theme.Palette.softText)
            .lineLimit(1)
            .fixedSize()
    }

    private func underLabel(_ split: WorkoutBreakdown.SplitBar) -> some View {
        VStack(spacing: 1) {
            Text(split.label)
                .font(Theme.Typography.splitIndex)
                .foregroundStyle(Theme.Palette.mutedText)
            if let hr = split.hrText {
                Text(hr)
                    .font(Theme.Typography.splitHr)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
        }
        .fixedSize()
    }
}

/// The planned blocks laid over the km axis.
private struct BlockStrip: View {
    let spans: [WorkoutBreakdown.BlockSpan]
    let totalKm: Double

    var body: some View {
        GeometryReader { geometry in
            ForEach(spans) { span in
                let scale = geometry.size.width / max(totalKm, 0.001)
                let width = max(0, (span.endKm - span.startKm) * scale - Theme.Spacing.splitBarGap)
                Text(span.label)
                    .font(Theme.Typography.blockStripLabel)
                    .foregroundStyle(Theme.Palette.softText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: width, height: Theme.Spacing.blockStripHeight)
                    .background(Theme.Palette.innerCard, in: Capsule())
                    .overlay { Capsule().strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth) }
                    .offset(x: span.startKm * scale)
            }
        }
        .frame(height: Theme.Spacing.blockStripHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Planned blocks: " + spans.map { "\($0.label) from km \(WorkoutFormat.kmMark($0.startKm)) to \(WorkoutFormat.kmMark($0.endKm))" }.joined(separator: ", "))
    }
}

/// Minutes per heart-rate zone, bars in a blue ramp; the session's target zones
/// are bracketed with the caption "Target".
struct ZonesCardView: View {
    let zones: [WorkoutBreakdown.ZoneRow]

    var body: some View {
        BreakdownCard(title: "Heart rate zones", identifier: "zonesCard") {
            VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                ForEach(zones) { row in
                    HStack(spacing: Theme.Spacing.compact) {
                        Text(row.name)
                            .font(Theme.Typography.zoneName)
                            .foregroundStyle(Theme.Palette.text)
                            .frame(width: Theme.Size.zoneNameWidth, alignment: .leading)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.Palette.zoneTrack)
                                Capsule()
                                    .fill(Theme.Palette.zoneRamp[row.zone - 1])
                                    .frame(width: max(row.share > 0 ? Theme.Spacing.zoneBarHeight : 0, geometry.size.width * row.share))
                            }
                        }
                        .frame(height: Theme.Spacing.zoneBarHeight)
                        Text(row.minutesText)
                            .font(Theme.Typography.zoneMinutes)
                            .foregroundStyle(Theme.Palette.softText)
                            .frame(width: Theme.Size.zoneMinutesWidth, alignment: .trailing)
                    }
                    .padding(.vertical, Theme.Spacing.tight)
                    .padding(.horizontal, Theme.Spacing.compact)
                    .overlay(alignment: .leading) {
                        if row.isTarget { TargetBracket(isFirst: isFirstTarget(row), isLast: isLastTarget(row)) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.spoken)
                }
                if zones.contains(where: \.isTarget) {
                    HStack(spacing: Theme.Spacing.tight) {
                        Rectangle().fill(Theme.Palette.softText).frame(width: Theme.Size.borderWidth * 2, height: Theme.Spacing.compact)
                        Text("Target")
                            .font(Theme.Typography.breakdownFootnote)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
    }

    private func isFirstTarget(_ row: WorkoutBreakdown.ZoneRow) -> Bool { !zones.contains { $0.isTarget && $0.zone == row.zone - 1 } }
    private func isLastTarget(_ row: WorkoutBreakdown.ZoneRow) -> Bool { !zones.contains { $0.isTarget && $0.zone == row.zone + 1 } }
}

/// A bracket line down the left of the target rows.
private struct TargetBracket: View {
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? Theme.Spacing.tight : 0,
            bottomLeadingRadius: isLast ? Theme.Spacing.tight : 0,
            style: .continuous
        )
        .strokeBorder(Theme.Palette.softText, lineWidth: Theme.Size.borderWidth * 2)
        .mask(alignment: .leading) { Rectangle().frame(width: Theme.Spacing.tight) }
        .frame(width: Theme.Spacing.tight * 2)
        .accessibilityHidden(true)
    }
}

/// One row per planned block: planned km, the actual pace, heart rate and zone,
/// and a neutral chip.
struct PlanVsActualCardView: View {
    let blocks: [WorkoutBreakdown.BlockRow]

    var body: some View {
        BreakdownCard(title: "Plan vs actual", identifier: "planVsActualCard") {
            VStack(alignment: .leading, spacing: Theme.Spacing.breakdownRows) {
                ForEach(blocks) { row in
                    HStack(alignment: .top, spacing: Theme.Spacing.compact) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.tight / 2) {
                            Text(row.label)
                                .font(Theme.Typography.blockLabel)
                                .foregroundStyle(Theme.Palette.text)
                            Text(row.plannedText)
                                .font(Theme.Typography.blockMeta)
                                .foregroundStyle(Theme.Palette.mutedText)
                            Text([row.paceText, row.hrText].compactMap { $0 }.joined(separator: " · "))
                                .font(Theme.Typography.blockMeta)
                                .foregroundStyle(Theme.Palette.softText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        NeutralChip(text: row.chip)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.spoken)
                    .accessibilityIdentifier("planVsActualRow-\(row.id)")
                }
                Text(WorkoutBreakdown.blocksFootnote)
                    .font(Theme.Typography.breakdownFootnote)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Soft text on a 13% fill: verdicts and block checks stay neutral until ratings exist.
struct NeutralChip: View {
    let text: String
    var identifier: String?

    var body: some View {
        Text(text)
            .font(Theme.Typography.verdictChip)
            .foregroundStyle(Theme.Palette.verdictChip)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, Theme.Spacing.statusChipVertical)
            .padding(.horizontal, Theme.Spacing.statusChipHorizontal)
            .background(Theme.Palette.verdictChip.opacity(Theme.Opacity.statusChipFill), in: Capsule())
            .accessibilityIdentifier(identifier ?? "neutralChip")
    }
}
