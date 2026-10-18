import SwiftUI
import Domain
import Application

/// Home's "Suggested change" after feedback: the reason, each changed day
/// before and after, and Apply or Keep plan. Then "Plan updated" with Undo.
struct SuggestionCardView: View {
    let store: FeedbackStore

    var body: some View {
        switch store.suggestion {
        case .none:
            if store.showsSevereMessage { severeOnly }
        case .checking:
            card {
                caption
                Text("Checking your plan…")
                    .font(Theme.Typography.sessionMeta)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityIdentifier("suggestionChecking")
            }
        case .pending(let stored):
            card {
                caption
                Text(stored.adjustment.reason)
                    .font(Theme.Typography.sessionName)
                    .foregroundStyle(Theme.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("suggestionReason")
                ForEach(stored.adjustment.changes, id: \.date) { change in
                    VStack(alignment: .leading, spacing: Theme.Spacing.tight / 2) {
                        Text(HomeFormat.shortDate(change.date))
                            .font(Theme.Typography.sessionMeta)
                            .foregroundStyle(Theme.Palette.mutedText)
                        Text(change.before).strikethrough()
                            .font(Theme.Typography.sessionMeta)
                            .foregroundStyle(Theme.Palette.mutedText)
                        Text(change.after)
                            .font(Theme.Typography.sessionMeta)
                            .foregroundStyle(Theme.Palette.text)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(change.line.replacingOccurrences(of: "\u{2192}", with: "becomes"))
                    .accessibilityIdentifier("suggestionChange-\(change.date)")
                }
                if store.showsSevereMessage { severeLine }
                Text("Suggested by \(stored.adjustment.writtenBy) after: \(stored.adjustment.triggerLine).")
                    .font(Theme.Typography.coachFooter)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Spacing.chipRow) {
                    Button("Apply") { Task { await store.apply() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("suggestionApply")
                    Button("Keep plan") { Task { await store.dismiss() } }
                        .buttonStyle(OutlineButtonStyle())
                        .accessibilityIdentifier("suggestionKeep")
                }
            }
        case .applied:
            card {
                HStack {
                    Text("Plan updated.")
                        .font(Theme.Typography.sessionName)
                        .foregroundStyle(Theme.Palette.text)
                        .accessibilityIdentifier("suggestionApplied")
                    Spacer(minLength: 0)
                    Button("Undo") { Task { await store.undo() } }
                        .buttonStyle(OutlineButtonStyle())
                        .accessibilityIdentifier("suggestionUndo")
                    Button("Dismiss") { store.clearMessage() }
                        .buttonStyle(OutlineButtonStyle())
                }
            }
        case .failed:
            card {
                Text("Couldn't apply that change. Your plan is unchanged.")
                    .font(Theme.Typography.sessionMeta)
                    .foregroundStyle(Theme.Palette.softText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Dismiss") { store.clearMessage() }
                    .buttonStyle(OutlineButtonStyle())
            }
        }
    }

    private var caption: some View {
        Text("Suggested change")
            .font(Theme.Typography.coachCaption)
            .tracking(Theme.Typography.captionTracking)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Palette.accent)
            .accessibilityAddTraits(.isHeader)
    }

    private var severeLine: some View {
        Text(FeedbackRules.severePainMessage)
            .font(Theme.Typography.sessionMeta)
            .foregroundStyle(Theme.Palette.statusAmber)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("suggestionSevere")
    }

    private var severeOnly: some View {
        card {
            severeLine
            Button("Dismiss") { store.clearMessage() }
                .buttonStyle(OutlineButtonStyle())
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            content()
        }
        .padding(Theme.Spacing.coachNotePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.accentLine, lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("suggestionCard")
    }
}
