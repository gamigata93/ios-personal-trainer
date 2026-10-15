import SwiftUI
import Domain

/// Standard normal curve over plus and minus 3 sigma with the user's share filled.
/// The marker sits at Probit(betterThan / 100), clamped so it stays readable.
struct BellCurveScale: View {
    let betterThan: Double
    let bubble: String

    private var markerSigma: Double {
        let clampedShare = min(max(betterThan, 1), 99) / 100
        let z = Probit.z(clampedShare) ?? 0
        return min(max(z, -Theme.Size.markerSigmaLimit), Theme.Size.markerSigmaLimit)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.compact) {
            GeometryReader { geometry in
                let size = geometry.size
                let marker = point(atSigma: markerSigma, in: size)

                ZStack(alignment: .topLeading) {
                    area(in: size).fill(Theme.Palette.curveFill)
                    area(in: size)
                        .fill(Theme.Palette.accent.opacity(Theme.Opacity.curveAccent))
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: marker.x)
                        }
                    outline(in: size)
                        .stroke(Theme.Palette.curveOutline, lineWidth: Theme.Size.curveStroke)

                    Path { path in
                        path.move(to: marker)
                        path.addLine(to: CGPoint(x: marker.x, y: size.height))
                    }
                    .stroke(Theme.Palette.accent, style: StrokeStyle(lineWidth: Theme.Size.curveStroke, dash: Theme.Size.markerDash))

                    Circle()
                        .fill(Theme.Palette.accent.opacity(Theme.Opacity.markerHalo))
                        .frame(width: Theme.Size.markerHalo, height: Theme.Size.markerHalo)
                        .position(marker)
                    Circle()
                        .fill(Theme.Palette.accent)
                        .frame(width: Theme.Size.markerDot, height: Theme.Size.markerDot)
                        .position(marker)

                    MarkerBubble(text: bubble)
                        .fixedSize()
                        .alignmentGuide(.leading) { bubbleSize in
                            let rightOfMarker = marker.x + Theme.Size.bubbleGap
                            let fitsRight = rightOfMarker + bubbleSize.width <= size.width
                            return -(fitsRight ? rightOfMarker : marker.x - Theme.Size.bubbleGap - bubbleSize.width)
                        }
                        .alignmentGuide(.top) { _ in
                            -max(0, marker.y - Theme.Size.bubbleHeight - Theme.Size.bubbleGap)
                        }
                }
            }
            .frame(height: Theme.Size.curveHeight)

            AxisLabels()
        }
    }

    // MARK: Geometry

    private func point(atSigma sigma: Double, in size: CGSize) -> CGPoint {
        let range = Theme.Size.curveSigmaRange
        let x = (sigma + range) / (2 * range) * size.width
        let density = exp(-sigma * sigma / 2)
        let usable = size.height - Theme.Size.curvePeakInset
        return CGPoint(x: x, y: size.height - density * usable)
    }

    private func curvePoints(in size: CGSize) -> [CGPoint] {
        let range = Theme.Size.curveSigmaRange
        let steps = 120
        return (0...steps).map { step in
            point(atSigma: -range + 2 * range * Double(step) / Double(steps), in: size)
        }
    }

    private func area(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLines(curvePoints(in: size))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
    }

    /// The curve plus a flat baseline.
    private func outline(in size: CGSize) -> Path {
        Path { path in
            path.addLines(curvePoints(in: size))
            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
        }
    }
}

/// Five equal bands, filled up to the user's share, right is better.
struct SegmentScale: View {
    let betterThan: Double
    let bubble: String

    private var fraction: Double { min(max(betterThan, 0), 100) / 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let markerX = fraction * width
                ZStack(alignment: .topLeading) {
                    MarkerBubble(text: bubble)
                        .fixedSize()
                        .alignmentGuide(.leading) { bubbleSize in
                            -min(max(0, markerX - bubbleSize.width / 2), width - bubbleSize.width)
                        }
                    segments(width: width)
                        .offset(y: Theme.Size.bubbleHeight + Theme.Size.bubbleGap)
                    Circle()
                        .fill(Theme.Palette.accent)
                        .overlay { Circle().strokeBorder(Theme.Palette.background, lineWidth: Theme.Size.curveStroke) }
                        .frame(width: Theme.Size.segmentMarker, height: Theme.Size.segmentMarker)
                        .position(x: markerX, y: Theme.Size.bubbleHeight + Theme.Size.bubbleGap + Theme.Size.segmentHeight / 2)
                }
            }
            .frame(height: Theme.Size.bubbleHeight + Theme.Size.bubbleGap + Theme.Size.segmentHeight)

            AxisLabels()
        }
    }

    private func segments(width: CGFloat) -> some View {
        let count = Theme.Size.segmentCount
        let gaps = Theme.Size.segmentGap * CGFloat(count - 1)
        let segmentWidth = (width - gaps) / CGFloat(count)
        return HStack(spacing: Theme.Size.segmentGap) {
            ForEach(0..<count, id: \.self) { index in
                let filled = min(max(fraction * Double(count) - Double(index), 0), 1)
                Capsule()
                    .fill(Theme.Palette.curveFill)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.Palette.accent)
                            .frame(width: segmentWidth * filled)
                    }
                    .clipShape(Capsule())
                    .frame(width: segmentWidth, height: Theme.Size.segmentHeight)
            }
        }
    }
}

/// The white "You · value" pill.
private struct MarkerBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typography.bubble)
            .foregroundStyle(Theme.Palette.onAccent)
            .padding(.horizontal, Theme.Spacing.bubbleHorizontal)
            .frame(height: Theme.Size.bubbleHeight)
            .background(Theme.Palette.bubble, in: Capsule())
    }
}

/// Low / Average / Excellent under a scale.
private struct AxisLabels: View {
    var body: some View {
        HStack {
            Text("Low")
            Spacer()
            Text("Average")
            Spacer()
            Text("Excellent")
        }
        .font(Theme.Typography.axisLabel)
        .foregroundStyle(Theme.Palette.mutedText)
    }
}
