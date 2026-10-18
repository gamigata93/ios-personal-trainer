import SwiftUI
import Domain

/// The strength-session icon: a dumbbell on the 16 x 16 grid, in the same
/// stroke as the run icons. Color encodes status only.
struct StrengthIcon: View {
    let size: CGFloat
    let color: Color
    var isStruck = false

    var body: some View {
        ZStack {
            DumbbellStroke()
                .stroke(color, style: StrokeStyle(lineWidth: Theme.Size.iconStroke * size / Theme.Size.iconGrid, lineCap: .round))
            if isStruck {
                StrengthStrike()
                    .stroke(color, style: StrokeStyle(lineWidth: Theme.Size.iconStroke * size / Theme.Size.iconGrid, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension StrengthIcon {
    /// The icon drawn the way its status looks (color and strike).
    init(size: CGFloat, presentation: SessionStatusPresentation) {
        self.init(size: size, color: presentation.iconColor, isStruck: presentation.iconDecoration == .strike)
    }
}

/// M4 8 H12, plates at x 4 and 12 (y 4 to 12), ends at x 1.5 and 14.5 (y 6 to 10).
private struct DumbbellStroke: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / Theme.Size.iconGrid
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        path.move(to: point(4, 8)); path.addLine(to: point(12, 8))
        for x in [CGFloat(4), 12] {
            path.move(to: point(x, 4)); path.addLine(to: point(x, 12))
        }
        for x in [CGFloat(1.5), 14.5] {
            path.move(to: point(x, 6)); path.addLine(to: point(x, 10))
        }
        return path
    }
}

private struct StrengthStrike: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / Theme.Size.iconGrid
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 2 * unit, y: rect.minY + 14 * unit))
        path.addLine(to: CGPoint(x: rect.minX + 14 * unit, y: rect.minY + 2 * unit))
        return path
    }
}

/// The small dumbbell in a strip or calendar cell that also has a run.
struct StrengthBadge: View {
    let status: SessionStatus
    var color: Color?

    var body: some View {
        StrengthIcon(size: Theme.Size.strengthBadge, color: color ?? SessionStatusPresentation.presentation(status).iconColor)
            .padding(Theme.Size.strengthBadgePadding)
            .background(Theme.Palette.innerCard, in: Circle())
            .accessibilityHidden(true)
    }
}
