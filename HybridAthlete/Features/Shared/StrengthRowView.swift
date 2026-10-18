import SwiftUI
import Domain
import Application

/// The selected day's strength session, under the day card (Home and Calendar).
/// The arrow opens the strength detail.
struct StrengthRowView: View {
    let card: StrengthCard
    let onOpen: (String) -> Void

    var body: some View {
        Button {
            onOpen(card.sessionID)
        } label: {
            HStack(spacing: Theme.Spacing.selectedCardGap) {
                StrengthIcon(size: Theme.Size.strengthRowIcon, presentation: .presentation(card.status))
                    .frame(width: Theme.Size.thumbnail, height: Theme.Size.thumbnail)
                    .background(Theme.Palette.thumbnail, in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                            .strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth)
                    }
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(card.name)
                        .font(Theme.Typography.sessionName)
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(card.meta)
                        .font(Theme.Typography.sessionMeta)
                        .foregroundStyle(Theme.Palette.mutedText)
                    StatusChip(status: card.status, identifier: "strengthRow.status")
                        .padding(.top, Theme.Spacing.tight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(Theme.Typography.arrowGlyph)
                    .foregroundStyle(Theme.Palette.text)
                    .frame(width: Theme.Size.arrowButton, height: Theme.Size.arrowButton)
                    .overlay { Circle().strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth) }
            }
            .padding(Theme.Spacing.selectedCardPadding)
            .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.name), \(card.meta), \(card.statusText.lowercased())")
        .accessibilityHint("Opens the strength session")
        .accessibilityIdentifier("strengthRow")
    }
}
