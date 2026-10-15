import SwiftUI
import Domain

/// The session-type icon. The shape encodes the type; color (passed in) encodes
/// status only. Drawn on a 16 x 16 grid and scaled to `size`.
struct SessionTypeIcon: View {
    let type: SessionType
    let size: CGFloat
    let color: Color
    /// A missed session: a diagonal strike across the icon.
    var isStruck = false

    var body: some View {
        ZStack {
            if isStruck {
                MissedStrike()
                    .stroke(color, style: StrokeStyle(lineWidth: Theme.Size.iconStroke * size / Theme.Size.iconGrid, lineCap: .round))
            }
            SessionTypeStroke(type: type)
                .stroke(color, style: StrokeStyle(
                    lineWidth: Theme.Size.iconStroke * size / Theme.Size.iconGrid,
                    lineCap: .round,
                    lineJoin: .round
                ))
            SessionTypeDots(type: type)
                .fill(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The stroked part of each icon.
private struct SessionTypeStroke: Shape {
    let type: SessionType

    func path(in rect: CGRect) -> Path {
        let unit = rect.width / Theme.Size.iconGrid
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        switch type {
        case .easy:
            // Circle r 5 at (8, 8).
            path.addEllipse(in: CGRect(x: rect.minX + 3 * unit, y: rect.minY + 3 * unit, width: 10 * unit, height: 10 * unit))
        case .tempo:
            // M3 12 L13 4 M13 4 H9 M13 4 V8.
            path.move(to: point(3, 12)); path.addLine(to: point(13, 4))
            path.move(to: point(13, 4)); path.addLine(to: point(9, 4))
            path.move(to: point(13, 4)); path.addLine(to: point(13, 8))
        case .threshold:
            // M2 11 H6 V5 H10 V11 H14.
            path.addLines([point(2, 11), point(6, 11), point(6, 5), point(10, 5), point(10, 11), point(14, 11)])
        case .intervals:
            // M1 9 H4 L5.5 3 L8.5 13 L10 7 H15.
            path.addLines([point(1, 9), point(4, 9), point(5.5, 3), point(8.5, 13), point(10, 7), point(15, 7)])
        case .long:
            // M2 8 H14.
            path.move(to: point(2, 8)); path.addLine(to: point(14, 8))
        }
        return path
    }
}

/// M2 14 L14 2: bottom-left to top-right, across the whole icon.
private struct MissedStrike: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / Theme.Size.iconGrid
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 2 * unit, y: rect.minY + 14 * unit))
        path.addLine(to: CGPoint(x: rect.minX + 14 * unit, y: rect.minY + 2 * unit))
        return path
    }
}

/// The filled part: the long run's end dots, r 1.4 at (2, 8) and (14, 8).
private struct SessionTypeDots: Shape {
    let type: SessionType

    func path(in rect: CGRect) -> Path {
        guard type == .long else { return Path() }
        let unit = rect.width / Theme.Size.iconGrid
        let radius = Theme.Size.iconDot * unit
        var path = Path()
        for x in [CGFloat(2), 14] {
            let center = CGPoint(x: rect.minX + x * unit, y: rect.minY + 8 * unit)
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        return path
    }
}

extension SessionStatus {
    /// Icon color by status. Ratings come later, so completed is neutral, not green.
    var iconColor: Color {
        switch self {
        case .completed: Theme.Palette.text
        case .missed: Theme.Palette.missedIcon
        case .notRecorded: Theme.Palette.mutedText
        case .today: Theme.Palette.accent
        case .upcoming: Theme.Palette.upcomingIcon
        }
    }

    /// Status chip text color; the fill is the same color at 13%.
    var chipColor: Color {
        switch self {
        case .completed, .today: Theme.Palette.text
        case .notRecorded, .upcoming: Theme.Palette.softText
        case .missed: Theme.Palette.missedAction
        }
    }

    /// Missed sessions draw their icon struck through.
    var isStruck: Bool { self == .missed }
}
