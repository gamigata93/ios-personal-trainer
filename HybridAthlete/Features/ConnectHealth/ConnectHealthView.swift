import SwiftUI

/// First launch only: explains what is read, then shows the Health permission sheet.
struct ConnectHealthView: View {
    let viewModel: ConnectHealthViewModel

    private struct Item: Identifiable {
        let icon: String
        let title: String
        let detail: String
        var id: String { title }
    }

    private let items = [
        Item(icon: "figure.run", title: "Workouts", detail: "Your runs, rides and sessions, from any app."),
        Item(icon: "heart", title: "VO2 max and heart rate", detail: "To place your fitness against people your age."),
        Item(icon: "moon", title: "Sleep and HRV", detail: "To spot the days you need an easier session."),
        Item(icon: "person", title: "Date of birth and sex", detail: "Only to choose the right comparison tables."),
    ]

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content
                    .padding(.horizontal, Theme.Spacing.screenSide)
                    .padding(.vertical, Theme.Spacing.screenTop)
                    // Centered when it fits; scrolls from the top when it does not.
                    .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.connectBlocks) {
                header
                list
                privacy
                VStack(spacing: Theme.Spacing.betweenButtons) {
                    Button("Allow Apple Health access") {
                        Task { await viewModel.allow() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.isRequesting)
                    .accessibilityIdentifier("connect.allow")

                    Text("iOS will ask you to confirm each type next. You can change this anytime in Settings, Health, Data Access & Devices.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    #if DEBUG
                    personaMenu
                    #endif
                }
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: Theme.Radius.logoTile, style: .continuous)
                .fill(Theme.Palette.card)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.logoTile, style: .continuous)
                        .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
                }
                .overlay {
                    Image(systemName: "heart")
                        .font(Theme.Typography.headerGlyph)
                        .foregroundStyle(Theme.Palette.accent)
                }
                .frame(width: Theme.Size.logoTile, height: Theme.Size.logoTile)
                .accessibilityHidden(true)
                .padding(.bottom, Theme.Spacing.logoToTitle)

            Text("Connect Apple Health")
                .font(Theme.Typography.compactScreenTitle)
                .foregroundStyle(Theme.Palette.text)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, Theme.Spacing.titleToSubtitle)

            Text("Your coach builds your plan from the workouts and fitness data already in Health.")
                .font(Theme.Typography.subtitle)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(Theme.Palette.cardBorder).frame(height: Theme.Size.borderWidth)
                }
                HStack(spacing: Theme.Spacing.rowIconToLabel) {
                    Circle()
                        .strokeBorder(Theme.Palette.iconRing, lineWidth: Theme.Size.borderWidth)
                        .frame(width: Theme.Size.connectRowIcon, height: Theme.Size.connectRowIcon)
                        .overlay {
                            Image(systemName: item.icon)
                                .font(Theme.Typography.cardIconGlyph)
                                .foregroundStyle(Theme.Palette.softText)
                        }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                        Text(item.title)
                            .font(Theme.Typography.rowLabel)
                            .foregroundStyle(Theme.Palette.text)
                        Text(item.detail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Theme.Spacing.connectRowVertical)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, Theme.Spacing.cardInner)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
    }

    private var privacy: some View {
        Label {
            Text("Read-only: the app never writes to Health. Your data stays on your phone and your coach only ever sees summaries.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock")
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Palette.mutedText)
    }

    #if DEBUG
    /// Swaps Apple Health for a made-up persona. Compiled out of release builds.
    @ViewBuilder
    private var personaMenu: some View {
        if !viewModel.personaChoices.isEmpty {
            Menu {
                Button("Real Apple Health") { viewModel.choosePersona(nil) }
                ForEach(viewModel.personaChoices, id: \.self) { id in
                    Button(id) { viewModel.choosePersona(id) }
                }
            } label: {
                Text("Persona (debug)").frame(maxWidth: .infinity)
            }
            .buttonStyle(TextButtonStyle())
            .accessibilityIdentifier("connect.persona")
        }
    }
    #endif
}

#if DEBUG
#Preview {
    ConnectHealthView(viewModel: CompositionRoot.previewConnectHealthViewModel())
}
#endif
