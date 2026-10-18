import SwiftUI
import Domain
import Application

/// A planned session, pushed over Home or Calendar with no tab bar. A completed
/// session shows its result tiles, the coach's note, splits, heart-rate zones and
/// plan vs actual (sections without data are hidden); the others show the plan.
struct SessionDetailView: View {
    let viewModel: SessionDetailViewModel
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.detailBlocks) {
                if let detail = viewModel.detail {
                    topRow(caption: detail.caption, date: detail.dateText)
                    if let breakdown = viewModel.breakdown {
                        titleBlock(detail, verdict: breakdown.verdict)
                        completed(breakdown)
                    } else {
                        titleBlock(detail, verdict: nil)
                        tiles(detail)
                        if let result = detail.result {
                            ResultCard(result: result)
                        }
                        if !detail.segments.isEmpty {
                            structure(detail.segments)
                        }
                        if let note = detail.note {
                            NoteCard(text: note)
                        }
                    }
                } else {
                    topRow(caption: "Session", date: nil)
                    Text("This session isn't in your plan anymore.")
                        .font(Theme.Typography.noticeBody)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sessionDetailMissing")
                }
            }
            .padding(.horizontal, Theme.Spacing.contentSide)
            .padding(.top, Theme.Spacing.contentTop)
            .padding(.bottom, Theme.Spacing.screenBottom)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.appear() }
    }

    /// Tiles, the coach's note, splits, zones, plan vs actual and the data footnote.
    @ViewBuilder
    private func completed(_ breakdown: WorkoutBreakdown) -> some View {
        WorkoutTilesView(tiles: breakdown.tiles)
        if let waiting = viewModel.analysisWaitingText {
            Text(waiting)
                .font(Theme.Typography.breakdownFootnote)
                .foregroundStyle(Theme.Palette.mutedText)
                .accessibilityIdentifier("analysisWaiting")
        }
        CoachNoteCardView(viewModel: viewModel)
        if viewModel.feedback != nil {
            FeedbackCardView(text: viewModel.feedbackText, onEdit: viewModel.editFeedback)
                .task(id: viewModel.isFeedbackOpen) { await viewModel.loadFeedback() }
        }
        if !breakdown.splits.isEmpty {
            SplitsCardView(breakdown: breakdown)
        }
        if !breakdown.zones.isEmpty {
            ZonesCardView(zones: breakdown.zones)
        }
        if !breakdown.blocks.isEmpty {
            PlanVsActualCardView(blocks: breakdown.blocks)
        }
        Text(breakdown.footnote)
            .font(Theme.Typography.breakdownFootnote)
            .foregroundStyle(Theme.Palette.mutedText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("workoutFootnote")
    }

    // MARK: Parts

    private func topRow(caption: String, date: String?) -> some View {
        HStack(spacing: Theme.Spacing.detailBackToTitle) {
            SquareChevronButton(direction: .left, label: "Back", identifier: "sessionDetailBack", action: onBack)
            VStack(alignment: .leading, spacing: Theme.Spacing.tight / 2) {
                Text(caption)
                    .font(Theme.Typography.detailCaption)
                    .foregroundStyle(Theme.Palette.mutedText)
                if let date {
                    Text(date)
                        .font(Theme.Typography.detailDate)
                        .foregroundStyle(Theme.Palette.text)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func titleBlock(_ detail: SessionDetailOverview, verdict: WorkoutVerdict?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            Text(detail.name)
                .font(Theme.Typography.detailTitle)
                .lineSpacing(Theme.Typography.detailTitleLineSpacing)
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("sessionDetailTitle")
            if let movedFrom = detail.movedFrom {
                MovedChip(text: movedFrom, identifier: "sessionDetailMoved")
            }
            FlowLayout(spacing: Theme.Spacing.chipRow, lineSpacing: Theme.Spacing.chipRow) {
                HStack(spacing: Theme.Spacing.tight + 2) {
                    SessionTypeIcon(type: detail.type, size: Theme.Size.chipIcon, presentation: .presentation(detail.status))
                    Text(detail.typeName).font(Theme.Typography.typeChip)
                }
                .foregroundStyle(Theme.Palette.softText)
                .padding(.horizontal, Theme.Spacing.detailChipHorizontal)
                .padding(.vertical, Theme.Spacing.detailChipVertical)
                .overlay { Capsule().strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth) }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("sessionDetailType")
                StatusChip(status: detail.status, identifier: "sessionDetailStatus")
                if let verdict {
                    NeutralChip(text: verdict.chipText, identifier: "sessionDetailVerdict")
                }
            }
            Text(detail.weekPhaseLine)
                .font(Theme.Typography.weekPhaseLine)
                .foregroundStyle(Theme.Palette.mutedText)
                .accessibilityIdentifier("sessionDetailWeek")
        }
    }

    private func tiles(_ detail: SessionDetailOverview) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.statTiles) {
            StatTile(label: "Distance", value: detail.distance, valueFont: Theme.Typography.tileValue, spoken: detail.distanceAccessibilityLabel)
            StatTile(
                label: "Est. time",
                value: detail.estimatedTime,
                valueFont: Theme.Typography.tileValue,
                spoken: "Estimated time \(detail.estimatedTime == "\u{2014}" ? "unknown" : detail.estimatedTime)"
            )
            StatTile(label: "Effort", value: detail.effort, valueFont: Theme.Typography.tileEffort, spoken: "Effort \(detail.effort)", lines: 2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func structure(_ segments: [SessionDetailOverview.Segment]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.segmentCards) {
            Text("Structure")
                .font(Theme.Typography.structureTitle)
                .foregroundStyle(Theme.Palette.text)
                .accessibilityAddTraits(.isHeader)
            ForEach(segments) { SegmentCard(segment: $0) }
        }
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    let valueFont: Font
    let spoken: String
    var lines = 1

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight + 2) {
            Text(label)
                .font(Theme.Typography.tileLabel)
                .foregroundStyle(Theme.Palette.mutedText)
            Text(value)
                .font(valueFont)
                .foregroundStyle(Theme.Palette.text)
                .lineLimit(lines)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.Spacing.statTilePadding)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.statTile, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.statTile, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// What the runs say: the matched run, or why none counted. No colors for the
/// delta: ratings come later.
private struct ResultCard: View {
    let result: SessionDetailOverview.Result

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            switch result {
            case .completed(let distance, let duration, let pace, let plannedLine):
                Text("Your run")
                    .font(Theme.Typography.resultCaption)
                    .tracking(Theme.Typography.captionTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.mutedText)
                FlowLayout(spacing: Theme.Spacing.legendItemsGap, lineSpacing: Theme.Spacing.tight) {
                    ForEach([distance, duration, pace].compactMap { $0 }, id: \.self) { value in
                        Text(value)
                            .font(Theme.Typography.resultValue)
                            .foregroundStyle(Theme.Palette.text)
                    }
                }
                Text(plannedLine)
                    .font(Theme.Typography.resultLine)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            case .missed:
                Text("Marked as missed")
                    .font(Theme.Typography.resultEmptyTitle)
                    .foregroundStyle(Theme.Palette.text)
                Text("You marked this session as missed. You can move it forward from the calendar.")
                    .font(Theme.Typography.resultLine)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            case .notRecorded(let text):
                Text("No run found for this day")
                    .font(Theme.Typography.resultEmptyTitle)
                    .foregroundStyle(Theme.Palette.text)
                Text(text)
                    .font(Theme.Typography.resultLine)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.resultPadding)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sessionDetailResult")
    }
}

private struct SegmentCard: View {
    let segment: SessionDetailOverview.Segment

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.segmentGap) {
            Text("\(segment.number)")
                .font(Theme.Typography.segmentNumber)
                .foregroundStyle(Theme.Palette.onAccent)
                .frame(width: Theme.Size.segmentNumber, height: Theme.Size.segmentNumber)
                .background(Theme.Palette.accent, in: Circle())
            VStack(alignment: .leading, spacing: Theme.Spacing.tight / 2) {
                Text(segment.label)
                    .font(Theme.Typography.segmentLabel)
                    .foregroundStyle(Theme.Palette.text)
                Text(segment.detail)
                    .font(Theme.Typography.segmentDetail)
                    .lineSpacing(Theme.Typography.segmentDetailLineSpacing)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let distance = segment.distance {
                Text(distance)
                    .font(Theme.Typography.segmentChip)
                    .foregroundStyle(Theme.Palette.softText)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, Theme.Spacing.detailChipHorizontal)
                    .padding(.vertical, Theme.Spacing.detailChipVertical)
                    .overlay { Capsule().strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth) }
            }
        }
        .padding(Theme.Spacing.segmentPadding)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.segmentCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.segmentCard, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segment.accessibilityLabel)
        .accessibilityIdentifier("sessionSegment-\(segment.number)")
    }
}

/// Only when the session has a note, e.g. a terrain note.
private struct NoteCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            Text("Note")
                .font(Theme.Typography.noteCaption)
                .tracking(Theme.Typography.captionTracking)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.accent)
            Text(text)
                .font(Theme.Typography.noteText)
                .lineSpacing(Theme.Typography.noteLineSpacing)
                .foregroundStyle(Theme.Palette.noteText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.notePadding)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sessionDetailNote")
    }
}

/// "Your feedback": the answer to the after-workout check, with Edit (or Add).
private struct FeedbackCardView: View {
    let text: String?
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.compact) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("Your feedback")
                    .font(Theme.Typography.coachCaption)
                    .tracking(Theme.Typography.captionTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityAddTraits(.isHeader)
                Text(text ?? "Not given yet.")
                    .font(Theme.Typography.sessionMeta)
                    .foregroundStyle(text == nil ? Theme.Palette.mutedText : Theme.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("feedbackCardText")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(text == nil ? "Add" : "Edit", action: onEdit)
                .buttonStyle(OutlineButtonStyle())
                .accessibilityIdentifier("feedbackCardEdit")
        }
        .padding(Theme.Spacing.selectedCardPadding)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feedbackCard")
    }
}
