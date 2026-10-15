import SwiftUI

/// Shown while the plan is built, and if building fails.
struct GeneratingView: View {
    let viewModel: GeneratingViewModel

    var body: some View {
        VStack(spacing: Theme.Spacing.cardStack) {
            Spacer()
            switch viewModel.phase {
            case .working:
                BuildingSpinner()
                    .padding(.bottom, Theme.Spacing.cardStack)
                Text(viewModel.title)
                    .font(Theme.Typography.compactScreenTitle)
                    .foregroundStyle(Theme.Palette.text)
                    .accessibilityIdentifier("generating.title")
                Text(viewModel.subtitle)
                    .font(Theme.Typography.subtitle)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .multilineTextAlignment(.center)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(Theme.Typography.headerGlyph)
                    .foregroundStyle(Theme.Palette.statusAmber)
                    .accessibilityHidden(true)
                Text("Your plan wasn't built")
                    .font(Theme.Typography.compactScreenTitle)
                    .foregroundStyle(Theme.Palette.text)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(Theme.Typography.subtitle)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("generating.error")
                VStack(spacing: Theme.Spacing.betweenButtons) {
                    Button("Try again") { Task { await viewModel.retry() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("generating.retry")
                    Button("Back to setup") { viewModel.backToSetup() }
                        .buttonStyle(OutlineButtonStyle())
                        .accessibilityIdentifier("generating.back")
                }
                .padding(.top, Theme.Spacing.compact)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.screenSide)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.background.ignoresSafeArea())
        .task { await viewModel.start() }
    }
}

/// The large accent arc from the "Building plan" mockup.
private struct BuildingSpinner: View {
    @State private var isSpinning = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Palette.cardBorder, lineWidth: Theme.Size.buildingSpinnerStroke)
            Circle()
                .trim(from: 0, to: Theme.Size.spinnerArc)
                .stroke(Theme.Palette.accent, style: StrokeStyle(lineWidth: Theme.Size.buildingSpinnerStroke, lineCap: .round))
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(.linear(duration: Theme.Motion.spinnerRevolution).repeatForever(autoreverses: false), value: isSpinning)
        }
        .frame(width: Theme.Size.buildingSpinner, height: Theme.Size.buildingSpinner)
        .onAppear { isSpinning = true }
        .accessibilityHidden(true)
    }
}
