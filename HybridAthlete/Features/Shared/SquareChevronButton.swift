import SwiftUI

/// A 46 pt square button with a stroked chevron: the month arrows and the
/// Session detail back button.
struct SquareChevronButton: View {
    enum Direction {
        case left, right
    }

    let direction: Direction
    let label: String
    let identifier: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChevronShape(direction: direction)
                .stroke(Theme.Palette.text, style: StrokeStyle(lineWidth: Theme.Size.chevronStroke, lineCap: .round, lineJoin: .round))
                .frame(width: Theme.Size.chevron, height: Theme.Size.chevron)
                .frame(width: Theme.Size.squareButton, height: Theme.Size.squareButton)
                .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.squareButton, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.squareButton, style: .continuous)
                        .strokeBorder(Theme.Palette.cardBorder, lineWidth: Theme.Size.borderWidth)
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.squareButton, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Theme.Opacity.disabledMonthButton)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// "M15 6 L9 12 L15 18" on a 24 x 24 grid, mirrored for the right chevron.
private struct ChevronShape: Shape {
    let direction: SquareChevronButton.Direction

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let x = direction == .left ? x : 24 - x
            return CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        path.addLines([point(15, 6), point(9, 12), point(15, 18)])
        return path
    }
}
