import SwiftUI

/// A pulsing placeholder block. Holds still when Reduce Motion is on.
struct SkeletonBlock: View {
    var width: CGFloat?
    let height: CGFloat
    var radius: CGFloat = Theme.Radius.skeletonLine

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBright = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.Palette.skeleton)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .opacity(reduceMotion ? Theme.Opacity.skeletonStill : (isBright ? Theme.Opacity.skeletonHigh : Theme.Opacity.skeletonLow))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: Theme.Motion.skeletonPulse).repeatForever(autoreverses: true),
                value: isBright
            )
            .onAppear { isBright = true }
            .accessibilityElement()
            .accessibilityLabel("Loading")
    }
}

/// The VO2 max or resting-HR card while its section loads.
struct ScaleCardSkeleton: View {
    let number: CGSize
    let chip: CGSize
    let scaleHeight: CGFloat
    let showsStatRow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.cardStack) {
            HStack {
                SkeletonBlock(width: number.width, height: number.height)
                Spacer()
                SkeletonBlock(width: chip.width, height: chip.height, radius: chip.height / 2)
            }
            SkeletonBlock(height: scaleHeight)
            SkeletonBlock(height: Theme.Size.Skeleton.textLine)
            if showsStatRow {
                SkeletonBlock(height: Theme.Size.Skeleton.statRow, radius: Theme.Radius.smallTile)
            }
        }
        .padding(Theme.Spacing.cardInner)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// One record row while workouts load.
struct RecordRowSkeleton: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.rowIconToLabel) {
            SkeletonBlock(width: Theme.Size.distanceTile, height: Theme.Size.distanceTile, radius: Theme.Radius.smallTile)
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                SkeletonBlock(width: Theme.Size.Skeleton.recordTimeWidth, height: Theme.Size.Skeleton.recordTime)
                SkeletonBlock(width: Theme.Size.Skeleton.recordDetailWidth, height: Theme.Size.Skeleton.textLine)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.rowVertical)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// One plan card while workouts load.
struct PlanCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.betweenButtons) {
            HStack(spacing: Theme.Spacing.rowIconToLabel) {
                SkeletonBlock(width: Theme.Size.planBadge, height: Theme.Size.planBadge, radius: Theme.Radius.smallTile)
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    SkeletonBlock(width: Theme.Size.Skeleton.planTitleWidth, height: Theme.Size.Skeleton.planTitle)
                    SkeletonBlock(width: Theme.Size.Skeleton.planDetailWidth, height: Theme.Size.Skeleton.textLine)
                }
                Spacer(minLength: 0)
            }
            SkeletonBlock(height: Theme.Size.Skeleton.planReason)
        }
        .padding(Theme.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}
