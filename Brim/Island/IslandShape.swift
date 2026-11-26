import SwiftUI

/// The island silhouette. Flush with the bezel on top. Open, its top corners flare into concave
/// shoulders (cubic, so they leave the bezel tangentially) and its bottom corners are continuous.
/// Docked to a side it grows out of that edge the same way: flared where it leaves the bezel, and
/// rounded as far as its depth allows on the outside, so even the closed sliver reads as a pill.
nonisolated struct IslandShape: Shape {
    var bottomRadius: CGFloat
    var shoulder: CGFloat
    var edge: IslandEdge = .top

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, shoulder) }
        set { bottomRadius = newValue.first; shoulder = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        switch edge {
        case .top:
            return topPath(in: rect)
        case .left:
            // Draw it hanging from the top, then mirror across the diagonal: top becomes left.
            let local = sidePath(in: CGRect(x: 0, y: 0, width: rect.height, height: rect.width))
            return local.applying(CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: rect.minX, ty: rect.minY))
        case .right:
            let local = sidePath(in: CGRect(x: 0, y: 0, width: rect.height, height: rect.width))
            return local.applying(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: rect.maxX, ty: rect.minY))
        }
    }

    /// The docked silhouette, drawn hanging from the top. Unlike the notch's, its outer corners may be as
    /// deep as the whole shape, so a few points of depth still end in a full round.
    private func sidePath(in rect: CGRect) -> Path {
        let inset = min(shoulder, rect.width / 4)
        let depth = min(shoulder, rect.height * 0.4)
        let left = rect.minX + inset, right = rect.maxX - inset
        let radius = max(0, min(bottomRadius, rect.height - depth, (right - left) / 2))
        let hook: CGFloat = 0.58

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(to: CGPoint(x: right, y: rect.minY + depth),
                      control1: CGPoint(x: rect.maxX - inset * hook, y: rect.minY),
                      control2: CGPoint(x: right, y: rect.minY + depth * (1 - hook)))
        path.addArc(tangent1End: CGPoint(x: right, y: rect.maxY), tangent2End: CGPoint(x: left, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: left, y: rect.maxY), tangent2End: CGPoint(x: left, y: rect.minY), radius: radius)
        path.addLine(to: CGPoint(x: left, y: rect.minY + depth))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                      control1: CGPoint(x: left, y: rect.minY + depth * (1 - hook)),
                      control2: CGPoint(x: rect.minX + inset * hook, y: rect.minY))
        path.closeSubpath()
        return path
    }

    private func topPath(in rect: CGRect) -> Path {
        let inset = min(shoulder, rect.width / 4)
        let depth = min(shoulder, rect.height / 2)
        let body = CGRect(x: rect.minX + inset, y: rect.minY, width: rect.width - inset * 2, height: rect.height)
        let radius = min(bottomRadius, body.width / 2, body.height / 2)

        var path = UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: radius,
            bottomTrailingRadius: radius, topTrailingRadius: 0, style: .continuous
        ).path(in: body)

        guard inset > 0.5, depth > 0.5 else { return path }
        let hook: CGFloat = 0.58
        var shoulders = Path()
        shoulders.move(to: CGPoint(x: rect.minX, y: rect.minY))
        shoulders.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        shoulders.addCurve(to: CGPoint(x: body.maxX, y: rect.minY + depth),
                           control1: CGPoint(x: rect.maxX - inset * hook, y: rect.minY),
                           control2: CGPoint(x: body.maxX, y: rect.minY + depth * (1 - hook)))
        shoulders.addLine(to: CGPoint(x: body.minX, y: rect.minY + depth))
        shoulders.addCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                           control1: CGPoint(x: body.minX, y: rect.minY + depth * (1 - hook)),
                           control2: CGPoint(x: rect.minX + inset * hook, y: rect.minY))
        shoulders.closeSubpath()
        path.addPath(shoulders)
        return path
    }
}

/// Motion tokens. No inline curves elsewhere: every motion in Brim names one of these.
/// Critically damped throughout (Apple's default); the island never wobbles.
enum Motion {
    static let open = Animation.smooth(duration: 0.34)
    static let close = Animation.smooth(duration: 0.28)
    /// Wings sliding out beside the notch, and size changes inside an open island.
    static let resize = Animation.smooth(duration: 0.30)
    /// Content arriving inside a still container.
    static let contentIn = Animation.smooth(duration: 0.20)
    /// Content leaving: gone before the shape starts to shrink around it.
    static let contentOut = Animation.easeOut(duration: 0.12)
    /// Content swapping in place (tabs, rows).
    static let swap = Animation.smooth(duration: 0.18)
    /// Press and toggle feedback.
    static let tap = Animation.smooth(duration: 0.16)
    /// Reduce Motion: a short fade everywhere.
    static let reduced = Animation.easeOut(duration: 0.12)
}
