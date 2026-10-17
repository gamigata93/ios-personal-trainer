import SwiftUI
import Domain

/// How a session status looks: the single source for Home's week strip, the
/// Calendar, the day card and Session detail. Pure values, no views.
struct SessionStatusPresentation: Equatable {
    enum IconDecoration: Equatable { case none, strike }
    enum CellBorder: Equatable { case solid, dashed }

    let iconColor: Color
    let iconDecoration: IconDecoration
    let cellBorder: CellBorder
    let showsCheckBadge: Bool
    let chipText: String
    let chipColor: Color
    /// The chip's background: the chip color at a low opacity.
    let chipFill: Color

    /// A rating only recolors the icon of a completed session; the badge stays.
    /// Every other status ignores it. Ratings do not exist yet, so callers pass nil.
    static func presentation(_ status: SessionStatus, rating: Rating? = nil) -> SessionStatusPresentation {
        let text = HomeFormat.statusText(status)
        switch status {
        case .completed:
            return SessionStatusPresentation(
                iconColor: rating?.color ?? Theme.Palette.completed,
                iconDecoration: .none,
                cellBorder: .solid,
                showsCheckBadge: true,
                chipText: text,
                chipColor: Theme.Palette.completed,
                chipFill: Theme.Palette.completedSoft
            )
        case .today:
            return plain(text, icon: Theme.Palette.accent, chip: Theme.Palette.text)
        case .upcoming:
            return plain(text, icon: Theme.Palette.upcomingIcon, chip: Theme.Palette.softText)
        case .notRecorded:
            return plain(text, icon: Theme.Palette.mutedText, chip: Theme.Palette.softText, border: .dashed)
        case .missed:
            return plain(text, icon: Theme.Palette.missedIcon, chip: Theme.Palette.missedAction, decoration: .strike)
        }
    }

    private static func plain(
        _ text: String, icon: Color, chip: Color, decoration: IconDecoration = .none, border: CellBorder = .solid
    ) -> SessionStatusPresentation {
        SessionStatusPresentation(
            iconColor: icon,
            iconDecoration: decoration,
            cellBorder: border,
            showsCheckBadge: false,
            chipText: text,
            chipColor: chip,
            chipFill: chip.opacity(Theme.Opacity.statusChipFill)
        )
    }
}

/// A completed session's rating. Only the presentation's parameter uses it for
/// now; ratings themselves are not built yet.
enum Rating: CaseIterable {
    case green, amber, red

    var color: Color {
        switch self {
        case .green: Theme.Palette.statusGreen
        case .amber: Theme.Palette.statusAmber
        case .red: Theme.Palette.statusRed
        }
    }
}

/// The small check badge on completed sessions: a filled circle with a check.
/// Decorative, hidden from VoiceOver (labels say "completed").
struct CheckBadge: View {
    let size: CGFloat
    var fill = Theme.Palette.completed
    var check = Theme.Palette.onAccent

    var body: some View {
        let scale = size / Theme.Size.checkBadge
        Circle()
            .fill(fill)
            .overlay {
                CheckGlyph()
                    .stroke(check, style: StrokeStyle(lineWidth: Theme.Size.checkGlyphStroke * scale, lineCap: .round, lineJoin: .round))
                    .frame(width: Theme.Size.checkGlyph * scale, height: Theme.Size.checkGlyph * scale)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A check mark on a 6 x 6 grid: M0.5 3.2 L2.3 5 L5.5 1.
private struct CheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 6
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 0.5 * unit, y: rect.minY + 3.2 * unit))
        path.addLine(to: CGPoint(x: rect.minX + 2.3 * unit, y: rect.minY + 5 * unit))
        path.addLine(to: CGPoint(x: rect.minX + 5.5 * unit, y: rect.minY + 1 * unit))
        return path
    }
}
