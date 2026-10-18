import SwiftUI
import Observation
import Domain
import Application

/// One strength session from the shared plan and workouts stores.
@MainActor
@Observable
final class StrengthDetailViewModel {
    let sessionID: String
    private let plans: ActivePlanStore
    private let runs: CompletedRunsStore
    private let getStrengthDetail: GetStrengthDetail

    init(sessionID: String, plans: ActivePlanStore, runs: CompletedRunsStore, getStrengthDetail: GetStrengthDetail) {
        self.sessionID = sessionID
        self.plans = plans
        self.runs = runs
        self.getStrengthDetail = getStrengthDetail
    }

    var detail: StrengthDetail? {
        plans.plan.flatMap { getStrengthDetail.execute(plan: $0, workouts: runs.result, sessionID: sessionID) }
    }
}

/// The strength session: focus and variant, minutes, the phase's load cue, and
/// its exercises with dose, equipment and a how-to line. Read-only.
struct StrengthDetailView: View {
    let viewModel: StrengthDetailViewModel
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.detailBlocks) {
                HStack(spacing: Theme.Spacing.detailBackToTitle) {
                    SquareChevronButton(direction: .left, label: "Back", identifier: "strengthDetailBack", action: onBack)
                    Text(viewModel.detail?.caption ?? "Strength")
                        .font(Theme.Typography.detailCaption)
                        .foregroundStyle(Theme.Palette.mutedText)
                }
                if let detail = viewModel.detail {
                    header(detail)
                    ForEach(detail.exercises) { exercise in
                        ExerciseCard(exercise: exercise)
                    }
                } else {
                    Text("This session isn't in your plan anymore.")
                        .font(Theme.Typography.noticeBody)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .accessibilityIdentifier("strengthDetailMissing")
                }
            }
            .padding(.horizontal, Theme.Spacing.contentSide)
            .padding(.top, Theme.Spacing.contentTop)
            .padding(.bottom, Theme.Spacing.screenBottom)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func header(_ detail: StrengthDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            Text(detail.title)
                .font(Theme.Typography.detailTitle)
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("strengthDetailTitle")
            FlowLayout(spacing: Theme.Spacing.chipRow, lineSpacing: Theme.Spacing.chipRow) {
                StatusChip(status: detail.status, identifier: "strengthDetailStatus")
                NeutralChip(text: detail.minutes, identifier: "strengthDetailMinutes")
            }
            Text(detail.effort)
                .font(Theme.Typography.weekPhaseLine)
                .foregroundStyle(Theme.Palette.softText)
                .fixedSize(horizontal: false, vertical: true)
            if let done = detail.doneLine {
                Text(done)
                    .font(Theme.Typography.weekPhaseLine)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityIdentifier("strengthDetailDone")
            }
        }
    }
}

private struct ExerciseCard: View {
    let exercise: StrengthDetail.Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name)
                    .font(Theme.Typography.sessionName)
                    .foregroundStyle(Theme.Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(exercise.dose)
                    .font(Theme.Typography.sessionMeta)
                    .foregroundStyle(Theme.Palette.accent)
            }
            Text(exercise.howTo)
                .font(Theme.Typography.sessionMeta)
                .foregroundStyle(Theme.Palette.softText)
                .fixedSize(horizontal: false, vertical: true)
            Text(exercise.equipment)
                .font(Theme.Typography.sessionMeta)
                .foregroundStyle(Theme.Palette.mutedText)
        }
        .padding(Theme.Spacing.selectedCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.smallTile, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.smallTile, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("strengthExercise-\(exercise.position)")
    }
}
