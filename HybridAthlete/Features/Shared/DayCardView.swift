import SwiftUI
import Domain
import Application

/// The card for the selected day, shared by Home and Calendar so both look and
/// behave the same. A session day has an arrow that opens its detail; rest days
/// and race day have none.
struct DayCardView: View {
    let card: DayCard
    /// A rest day with a strength session reads "No run" instead of "Nothing scheduled".
    var hasStrength = false
    let onOpenSession: (String) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.selectedCardGap) {
            thumbnail
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if case .session(let session) = card {
                Button {
                    onOpenSession(session.sessionID)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(Theme.Typography.arrowGlyph)
                        .foregroundStyle(Theme.Palette.text)
                        .frame(width: Theme.Size.arrowButton, height: Theme.Size.arrowButton)
                        .overlay { Circle().strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth) }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(session.name)")
                .accessibilityIdentifier("sessionDetail")
            }
        }
        .padding(Theme.Spacing.selectedCardPadding)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dayCard")
    }

    private var thumbnail: some View {
        Group {
            switch card {
            case .session(let session):
                SessionTypeIcon(type: session.type, size: Theme.Size.thumbnailIcon, presentation: .presentation(session.status))
            case .rest:
                Image(systemName: "moon").font(Theme.Typography.thumbnailGlyph).foregroundStyle(Theme.Palette.mutedText)
            case .race:
                Image(systemName: "flag.fill").font(Theme.Typography.thumbnailGlyph).foregroundStyle(Theme.Palette.accent)
            }
        }
        .frame(width: Theme.Size.thumbnail, height: Theme.Size.thumbnail)
        .background(Theme.Palette.thumbnail, in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                .strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch card {
        case .session(let session):
            Text(session.name)
                .font(Theme.Typography.sessionName)
                .foregroundStyle(Theme.Palette.text)
                .accessibilityIdentifier("dayCard.name")
            Text(session.meta)
                .font(Theme.Typography.sessionMeta)
                .foregroundStyle(Theme.Palette.mutedText)
            FlowLayout(spacing: Theme.Spacing.chipRow, lineSpacing: Theme.Spacing.chipRow) {
                StatusChip(status: session.status)
                if let movedFrom = session.movedFrom {
                    MovedChip(text: movedFrom)
                }
            }
            .padding(.top, Theme.Spacing.tight)
        case .rest:
            Text(hasStrength ? "No run" : "Rest day")
                .font(Theme.Typography.sessionName)
                .foregroundStyle(Theme.Palette.text)
                .accessibilityIdentifier("dayCard.name")
            Text(hasStrength ? "Strength only." : "Nothing scheduled. Recover well.")
                .font(Theme.Typography.sessionMeta)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        case .race(let title):
            Text("Race day")
                .font(Theme.Typography.sessionName)
                .foregroundStyle(Theme.Palette.text)
                .accessibilityIdentifier("dayCard.name")
            Text(title)
                .font(Theme.Typography.sessionMeta)
                .foregroundStyle(Theme.Palette.accent)
        }
    }
}

/// "Moved from Mon 26 Oct": a neutral outline chip on a session an edit moved.
struct MovedChip: View {
    let text: String
    var identifier = "dayCard.moved"

    var body: some View {
        Text(text)
            .font(Theme.Typography.movedChip)
            .foregroundStyle(Theme.Palette.softText)
            .padding(.vertical, Theme.Spacing.statusChipVertical)
            .padding(.horizontal, Theme.Spacing.statusChipHorizontal)
            .overlay { Capsule().strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth) }
            .accessibilityIdentifier(identifier)
    }
}

/// "Completed", "Today", ...: text, color and fill from the status presentation.
struct StatusChip: View {
    let status: SessionStatus
    var identifier = "dayCard.status"

    var body: some View {
        let look = SessionStatusPresentation.presentation(status)
        HStack(spacing: Theme.Spacing.tight) {
            if look.showsCheckBadge {
                Image(systemName: "checkmark").font(Theme.Typography.statusChip)
            }
            Text(look.chipText).font(Theme.Typography.statusChip)
        }
        .foregroundStyle(look.chipColor)
        .padding(.vertical, Theme.Spacing.statusChipVertical)
        .padding(.horizontal, Theme.Spacing.statusChipHorizontal)
        .background(look.chipFill, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
