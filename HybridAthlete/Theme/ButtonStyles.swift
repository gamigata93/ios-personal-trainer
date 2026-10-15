import SwiftUI

/// Full-width accent button for a screen's main action.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.primaryButton)
            .foregroundStyle(Theme.Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.minTouchTarget)
            .padding(.vertical, Theme.Spacing.buttonVertical)
            .background(Theme.Palette.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .opacity(configuration.isPressed ? Theme.Opacity.pressedPrimary : 1)
    }
}

/// The accent button at the outline button's height, for rows of buttons.
struct CompactPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.secondaryButton)
            .foregroundStyle(Theme.Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.minTouchTarget)
            .background(Theme.Palette.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .opacity(configuration.isPressed ? Theme.Opacity.pressedPrimary : 1)
    }
}

/// Bordered button for secondary actions.
struct OutlineButtonStyle: ButtonStyle {
    var textColor: Color = Theme.Palette.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.secondaryButton)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.minTouchTarget)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .opacity(configuration.isPressed ? Theme.Opacity.pressedSecondary : 1)
    }
}

/// Plain text link-style button.
struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.textButton)
            .foregroundStyle(Theme.Palette.softText)
            .frame(minHeight: Theme.Size.minTouchTarget)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? Theme.Opacity.pressedText : 1)
    }
}
