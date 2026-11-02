import SwiftUI

/// Cat lovers mode: a cat in every scene, each up to something of its own. The timing lives in
/// `CatStory`; this draws it.
extension SceneLife {
    /// Horizontal position of a fraction across the scene, measured from the side a visit starts on.
    static func sceneX(_ across: Double, in rect: CGRect, facing: CGFloat) -> CGFloat {
        let offset = rect.width * CGFloat(across)
        return facing > 0 ? rect.minX + offset : rect.maxX - offset
    }

    static func paintCat(
        in context: inout GraphicsContext, frame: CatFrame, rect: CGRect, ground: CGFloat, size: CGFloat,
        facing: CGFloat, time: TimeInterval
    ) {
        let point = CGPoint(x: sceneX(frame.across, in: rect, facing: facing), y: ground - CGFloat(frame.lift) * size)
        critter(in: &context, at: point, facing: frame.looksBack ? -facing : facing) {
            if frame.pose == .sunbathe {
                sunbathingCat(in: &$0, size: size, time: time)
            } else {
                cat(in: &$0, size: size, time: time, pose: frame.pose)
            }
        }
    }

    static func cat(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval, pose: CatPose = .walk) {
        let fur = Color(red: 0.93, green: 0.6, blue: 0.27)
        let dark = Color(red: 0.75, green: 0.42, blue: 0.16)
        let step: Double =
            switch pose {
            case .walk: time * 9
            case .stalk: time * 3
            case .sprint: time * 16
            case .float: time * 2.5
            default: 0
            }
        let bob = pose == .walk || pose == .sprint ? CGFloat(abs(sin(step))) * size * 0.02 : 0
        // Crouching brings the body down close to the ground.
        let isLow = pose == .stalk || pose == .crouch || pose == .wiggle
        let drop = isLow ? size * 0.13 : 0
        // The wiggle before a pounce: the rear end shimmies.
        let shimmy = pose == .wiggle ? CGFloat(sin(time * 28)) * size * 0.025 : 0
        // Legs: front and back pairs swing in opposition.
        let legs: [(x: CGFloat, phase: Double, isFront: Bool)] = [
            (0.28, 0, true), (0.18, .pi, true), (-0.28, .pi, false), (-0.38, 0, false),
        ]
        for (x, phase, isFront) in legs {
            let hip = CGPoint(x: x * size + (isFront ? 0 : shimmy), y: -size * 0.3 + drop)
            let foot: CGPoint
            switch pose {
            case .walk:
                foot = CGPoint(x: hip.x + CGFloat(sin(step + phase)) * size * 0.07, y: 0)
            case .stalk:
                foot = CGPoint(x: hip.x + CGFloat(sin(step + phase)) * size * 0.05, y: 0)
            case .sprint:
                // A gallop: both front legs reach forward as both back legs push off, then gather.
                let reach = CGFloat(sin(step + phase * 0.15)) * size * 0.17
                foot = CGPoint(x: hip.x + (isFront ? reach : -reach), y: -max(reach, 0) * 0.3)
            case .leap:
                foot =
                    isFront
                    ? CGPoint(x: hip.x + size * 0.3, y: hip.y - size * 0.02)
                    : CGPoint(x: hip.x - size * 0.3, y: hip.y + size * 0.08)
            case .float:
                let paddle = CGFloat(sin(step + phase)) * size * 0.05
                foot = CGPoint(x: hip.x + (isFront ? size * 0.14 : -size * 0.14) + paddle, y: size * 0.02)
            case .stand, .crouch, .wiggle, .sunbathe:
                foot = CGPoint(x: hip.x, y: 0)
            }
            var leg = Path()
            leg.move(to: hip)
            leg.addLine(to: foot)
            context.stroke(leg, with: .color(dark), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
        }
        // Tail: curling and swishing, or held low and twitching when hunting, or streaming
        // out behind at speed.
        let tailTip: CGPoint
        let tailBend: CGPoint
        switch pose {
        case .stalk, .crouch, .wiggle:
            tailTip = CGPoint(
                x: -size * 0.88 + shimmy, y: -size * 0.4 + drop + CGFloat(sin(time * 7)) * size * 0.04)
            tailBend = CGPoint(x: -size * 0.68 + shimmy, y: -size * 0.36 + drop)
        case .sprint, .leap:
            tailTip = CGPoint(x: -size * 0.92, y: -size * 0.58 - bob)
            tailBend = CGPoint(x: -size * 0.7, y: -size * 0.46 - bob)
        case .walk, .stand, .float, .sunbathe:
            tailTip = CGPoint(x: -size * 0.62 + CGFloat(sin(time * 3)) * size * 0.06, y: -size * 0.85)
            tailBend = CGPoint(x: -size * 0.75, y: -size * 0.45)
        }
        var tail = Path()
        tail.move(to: CGPoint(x: -size * 0.45 + shimmy, y: -size * 0.42 - bob + drop))
        tail.addQuadCurve(to: tailTip, control: tailBend)
        context.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
        // Body and head.
        let top = -size * 0.58 - bob + drop
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.5, y: top, width: size, height: size * 0.36)), with: .color(fur))
        for stripe in [-0.25, -0.05, 0.15] as [CGFloat] {
            context.fill(
                Path(
                    roundedRect: CGRect(x: stripe * size, y: top, width: size * 0.06, height: size * 0.14),
                    cornerRadius: 2),
                with: .color(dark))
        }
        // Neck joins the front of the body to the head, which overlaps the body slightly. Hunting,
        // the head is held low and forward.
        let reach = isLow ? size * 0.04 : 0
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: size * 0.26 + reach * 0.5, y: -size * 0.62 - bob + drop * 0.9, width: size * 0.24,
                    height: size * 0.26)),
            with: .color(fur))
        let head = CGPoint(x: size * 0.43 + reach, y: -size * 0.63 - bob + drop * 0.85)
        let headRadius = size * 0.17
        for ear in [-1.0, 1.0] as [CGFloat] {
            var triangle = Path()
            triangle.move(to: CGPoint(x: head.x + ear * headRadius * 0.85, y: head.y - headRadius * 0.4))
            triangle.addLine(to: CGPoint(x: head.x + ear * headRadius * 0.6, y: head.y - headRadius * 1.35))
            triangle.addLine(to: CGPoint(x: head.x + ear * headRadius * 0.05, y: head.y - headRadius * 0.8))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(fur))
        }
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: head.x - headRadius, y: head.y - headRadius, width: headRadius * 2, height: headRadius * 1.9)),
            with: .color(fur))
        // Blinks every few seconds, but never while hunting.
        let isHunting = isLow || pose == .leap || pose == .sprint
        let blink = !isHunting && time.truncatingRemainder(dividingBy: 3.7) < 0.15
        for eye in [-0.35, 0.4] as [CGFloat] {
            let eyeRect = CGRect(
                x: head.x + eye * headRadius - size * 0.02, y: head.y - size * 0.03, width: size * 0.04,
                height: blink ? size * 0.008 : size * 0.05)
            context.fill(Path(ellipseIn: eyeRect), with: .color(.black))
        }
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: head.x + headRadius * 0.7, y: head.y + size * 0.02, width: size * 0.04, height: size * 0.03)),
            with: .color(Color(red: 0.9, green: 0.45, blue: 0.5)))
    }
}
