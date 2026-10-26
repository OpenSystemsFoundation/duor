import SwiftUI

/// Cat lovers mode: a cat in every scene, each up to something of its own. The timing lives in
/// `CatStory`; this draws it.
extension SceneLife {
    static let catLoversKey = "catLovers"

    // MARK: Scenes

    /// On the beach: strolls in, sunbathes belly up for a good while, strolls off.
    static func catOnTheBeach(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval) {
        let duration = CatStory.sunbatherDuration
        guard let visit = Self.visit(time: time, period: 32, duration: duration, salt: 23) else { return }
        let spot = CatStory.sunbathingSpot(lane: Double(visit.lane))
        guard let frame = CatStory.sunbather(at: visit.progress * duration, spot: spot) else { return }
        paintCat(
            in: &context, frame: frame, rect: rect, ground: rect.minY + rect.height * 0.8, size: rect.width * 0.26,
            facing: visit.facing, time: time)
    }

    /// In the forest: the rabbit, and the cat stalking it. Replaces the plain rabbit.
    static func catChasingRabbit(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval) {
        guard let visit = Self.visit(time: time, period: 16, duration: CatStory.chaseDuration, salt: 8) else { return }
        let chase = CatStory.chase(at: visit.progress * CatStory.chaseDuration)
        if let across = chase.rabbit {
            let size = rect.width * 0.14
            let hop = CGFloat(abs(sin(time * 7 * chase.rabbitHop)) * min(chase.rabbitHop, 1)) * size * 0.35
            let point = CGPoint(
                x: sceneX(across, in: rect, facing: visit.facing), y: rect.minY + rect.height * 0.92 - hop)
            critter(in: &context, at: point, facing: visit.facing) {
                rabbit(in: &$0, size: size)
            }
        }
        if let frame = chase.cat {
            paintCat(
                in: &context, frame: frame, rect: rect, ground: rect.minY + rect.height * 0.95,
                size: rect.width * 0.22, facing: visit.facing, time: time)
        }
    }

    /// In the great hall: a guard on two legs, pike and kettle hat, patrolling at the back.
    static func catOnPatrol(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval) {
        guard let visit = Self.visit(time: time, period: 19, duration: 13, salt: 20) else { return }
        let size = rect.height * 0.17
        let point = CGPoint(x: visit.x(in: rect, margin: size * 0.6), y: rect.minY + rect.height * 0.7)
        critter(in: &context, at: point, facing: visit.facing) {
            guardCat(in: &$0, size: size, time: time)
        }
    }

    /// In space: a cat in a bubble helmet, slowly tumbling by.
    static func catInSpace(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval) {
        guard let visit = Self.visit(time: time, period: 29, duration: 18, salt: 21) else { return }
        let size = rect.width * 0.22
        let x = visit.x(in: rect, margin: size)
        let y = rect.minY + rect.height * (0.25 + 0.15 * visit.lane) + CGFloat(visit.progress) * rect.height * 0.12
        context.drawLayer { layer in
            layer.translateBy(x: x, y: y)
            layer.rotate(by: .radians(-time * 0.35 * Double(visit.facing)))
            layer.scaleBy(x: visit.facing, y: 1)
            // Tumble about the middle of the body, not the feet.
            layer.translateBy(x: 0, y: size * 0.45)
            spaceCat(in: &layer, size: size, time: time)
        }
    }

    /// At the brick wall: two mouse holes, a pounce on the wrong one, and a mouse getting away.
    static func catAtTheWall(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval) {
        for across in CatStory.mouseHoles {
            let bottom = CGPoint(x: rect.minX + rect.width * across, y: rect.maxY)
            mouseHole(in: &context, at: bottom, width: rect.width * 0.08)
        }
        let duration = CatStory.pounceDuration
        guard let visit = Self.visit(time: time, period: 20, duration: duration, salt: 22) else { return }
        let t = visit.progress * duration
        let ground = rect.maxY - 1
        if let across = CatStory.mouse(at: t) {
            // Runs the other way from the cat: back the way the cat came.
            critter(
                in: &context, at: CGPoint(x: sceneX(across, in: rect, facing: visit.facing), y: ground),
                facing: -visit.facing
            ) {
                mouse(in: &$0, size: rect.width * 0.09, time: time)
            }
        }
        if let frame = CatStory.pounce(at: t) {
            paintCat(
                in: &context, frame: frame, rect: rect, ground: ground, size: rect.width * 0.3, facing: visit.facing,
                time: time)
        }
    }

    // MARK: Helpers

    /// Horizontal position of a fraction across the scene, measured from the side a visit starts on.
    private static func sceneX(_ across: Double, in rect: CGRect, facing: CGFloat) -> CGFloat {
        let offset = rect.width * CGFloat(across)
        return facing > 0 ? rect.minX + offset : rect.maxX - offset
    }

    private static func paintCat(
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

    // MARK: Cats (origin at the feet, facing right)

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

    /// Flat on its back on the sand, paws in the air, eyes shut, now and then a big stretch.
    private static func sunbathingCat(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        let fur = Color(red: 0.93, green: 0.6, blue: 0.27)
        let dark = Color(red: 0.75, green: 0.42, blue: 0.16)
        let belly = Color(red: 0.99, green: 0.88, blue: 0.74)
        let pink = Color(red: 0.95, green: 0.6, blue: 0.62)
        let breath = CGFloat(sin(time * 1.6)) * size * 0.012
        let stretch = CGFloat(pow(max(0, sin(time * 0.6)), 8))
        // The tail lies on the sand, the tip flicking lazily.
        let flick = CGFloat(max(0, sin(time * 1.3))) * size * 0.06
        var tail = Path()
        tail.move(to: CGPoint(x: -size * 0.42, y: -size * 0.1))
        tail.addQuadCurve(
            to: CGPoint(x: -size * 0.82, y: -size * 0.04 - flick), control: CGPoint(x: -size * 0.64, y: 0))
        context.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
        // Legs up in the air, paws flopped over.
        for (x, lean) in [(0.24, 0.1), (0.12, 0.03), (-0.2, -0.03), (-0.32, -0.1)] as [(CGFloat, CGFloat)] {
            let hip = CGPoint(x: x * size, y: -size * 0.22)
            let knee = CGPoint(x: hip.x + lean * size, y: -size * 0.44 - stretch * size * 0.08)
            let flop = 1 - stretch
            let paw = CGPoint(
                x: knee.x + (x > 0 ? 1 : -1) * size * 0.05 * flop, y: knee.y + size * 0.03 * flop)
            var leg = Path()
            leg.move(to: hip)
            leg.addLine(to: knee)
            leg.addLine(to: paw)
            context.stroke(
                leg, with: .color(dark), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round, lineJoin: .round))
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: paw.x - size * 0.03, y: paw.y - size * 0.03, width: size * 0.06, height: size * 0.06)),
                with: .color(pink))
        }
        // Body on its back, pale belly to the sun, stripes along the side.
        let body = CGRect(x: -size * 0.46, y: -size * 0.32 - breath, width: size * 0.9, height: size * 0.3 + breath)
        context.fill(Path(ellipseIn: body), with: .color(fur))
        for stripe in [-0.22, -0.02, 0.18] as [CGFloat] {
            context.fill(
                Path(
                    roundedRect: CGRect(
                        x: stripe * size, y: body.maxY - size * 0.11, width: size * 0.06, height: size * 0.1),
                    cornerRadius: 2),
                with: .color(dark))
        }
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: -size * 0.34, y: body.minY + size * 0.01, width: size * 0.62, height: size * 0.14)),
            with: .color(belly))
        // Head upside down on the sand: ears pointing down, eyes shut in bliss.
        let head = CGPoint(x: size * 0.5, y: -size * 0.24)
        let radius = size * 0.17
        for ear in [-1.0, 1.0] as [CGFloat] {
            var triangle = Path()
            triangle.move(to: CGPoint(x: head.x + ear * radius * 0.85, y: head.y + radius * 0.4))
            triangle.addLine(to: CGPoint(x: head.x + ear * radius * 0.6, y: head.y + radius * 1.35))
            triangle.addLine(to: CGPoint(x: head.x + ear * radius * 0.05, y: head.y + radius * 0.8))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(fur))
        }
        let face = CGRect(x: head.x - radius, y: head.y - radius * 0.9, width: radius * 2, height: radius * 1.9)
        context.fill(Path(ellipseIn: face), with: .color(fur))
        for eye in [-0.35, 0.4] as [CGFloat] {
            let center = CGPoint(x: head.x + eye * radius, y: head.y + size * 0.02)
            var lid = Path()
            lid.move(to: CGPoint(x: center.x - size * 0.025, y: center.y))
            lid.addQuadCurve(
                to: CGPoint(x: center.x + size * 0.025, y: center.y),
                control: CGPoint(x: center.x, y: center.y + size * 0.025))
            context.stroke(lid, with: .color(.black), style: StrokeStyle(lineWidth: size * 0.012, lineCap: .round))
        }
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: head.x + radius * 0.7, y: head.y - size * 0.05, width: size * 0.04, height: size * 0.03)),
            with: .color(Color(red: 0.9, green: 0.45, blue: 0.5)))
    }

    /// Standing on its hind legs, marching, with a pike, a red tabard and a steel kettle hat.
    private static func guardCat(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        let fur = Color(red: 0.93, green: 0.6, blue: 0.27)
        let dark = Color(red: 0.75, green: 0.42, blue: 0.16)
        let steel = Color(white: 0.72)
        let red = Color(red: 0.6, green: 0.1, blue: 0.12)
        let gold = Color(red: 0.95, green: 0.78, blue: 0.3)
        let step = time * 6
        let bob = CGFloat(abs(sin(step))) * size * 0.02
        // Tail behind, swishing.
        var tail = Path()
        tail.move(to: CGPoint(x: -size * 0.1, y: -size * 0.36 - bob))
        tail.addQuadCurve(
            to: CGPoint(x: -size * 0.32 + CGFloat(sin(time * 2.5)) * size * 0.04, y: -size * 0.62 - bob),
            control: CGPoint(x: -size * 0.34, y: -size * 0.3 - bob))
        context.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
        // Two hind legs, marching.
        for phase in [0.0, Double.pi] {
            var leg = Path()
            leg.move(to: CGPoint(x: 0, y: -size * 0.32))
            leg.addLine(to: CGPoint(x: CGFloat(sin(step + phase)) * size * 0.1, y: 0))
            context.stroke(leg, with: .color(dark), style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
        }
        // The free arm swings along.
        var backArm = Path()
        backArm.move(to: CGPoint(x: -size * 0.06, y: -size * 0.62 - bob))
        backArm.addLine(to: CGPoint(x: -size * 0.08 - CGFloat(sin(step)) * size * 0.06, y: -size * 0.42 - bob))
        context.stroke(backArm, with: .color(dark), style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round))
        // Upright body in a tabard with a gold belt.
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.14, y: -size * 0.74 - bob, width: size * 0.28, height: size * 0.46)),
            with: .color(fur))
        context.fill(
            Path(
                roundedRect: CGRect(x: -size * 0.11, y: -size * 0.68 - bob, width: size * 0.22, height: size * 0.36),
                cornerRadius: size * 0.04),
            with: .color(red))
        context.fill(
            Path(CGRect(x: -size * 0.11, y: -size * 0.5 - bob, width: size * 0.22, height: size * 0.035)),
            with: .color(gold))
        // The pike, held upright and carried along.
        let shaftX = size * 0.2
        var shaft = Path()
        shaft.move(to: CGPoint(x: shaftX, y: -size * 0.02 - bob))
        shaft.addLine(to: CGPoint(x: shaftX, y: -size * 1.45 - bob))
        context.stroke(
            shaft, with: .color(Color(red: 0.45, green: 0.3, blue: 0.16)),
            style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
        let tip = CGPoint(x: shaftX, y: -size * 1.66 - bob)
        let socket = CGPoint(x: shaftX, y: -size * 1.43 - bob)
        let widest = -size * 1.5 - bob
        var point = Path()
        point.move(to: tip)
        point.addQuadCurve(to: socket, control: CGPoint(x: shaftX + size * 0.07, y: widest))
        point.addQuadCurve(to: tip, control: CGPoint(x: shaftX - size * 0.07, y: widest))
        context.fill(point, with: .color(steel))
        context.fill(
            Path(CGRect(x: shaftX - size * 0.025, y: -size * 1.46 - bob, width: size * 0.05, height: size * 0.03)),
            with: .color(Color(white: 0.4)))
        // Head, ears poking out from under the hat.
        let head = CGPoint(x: size * 0.03, y: -size * 0.84 - bob)
        let radius = size * 0.14
        for ear in [-1.0, 1.0] as [CGFloat] {
            var triangle = Path()
            triangle.move(to: CGPoint(x: head.x + ear * radius * 0.7, y: head.y - radius * 0.45))
            triangle.addLine(to: CGPoint(x: head.x + ear * radius * 1.3, y: head.y - radius * 0.75))
            triangle.addLine(to: CGPoint(x: head.x + ear * radius * 0.9, y: head.y - radius * 0.05))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(fur))
        }
        context.fill(
            Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 1.9)),
            with: .color(fur))
        // Kettle hat: a steel dome with a wide brim.
        let dome = CGRect(x: head.x - radius * 0.95, y: head.y - radius * 1.55, width: radius * 1.9, height: radius)
        context.fill(
            Path(
                roundedRect: dome,
                cornerRadii: RectangleCornerRadii(
                    topLeading: radius * 0.95, bottomLeading: 0, bottomTrailing: 0, topTrailing: radius * 0.95)),
            with: .linearGradient(
                Gradient(colors: [Color(white: 0.88), steel, Color(white: 0.5)]),
                startPoint: CGPoint(x: dome.minX, y: 0), endPoint: CGPoint(x: dome.maxX, y: 0)))
        context.fill(
            Path(
                roundedRect: CGRect(
                    x: head.x - size * 0.21, y: dome.maxY - size * 0.02, width: size * 0.42, height: size * 0.04),
                cornerRadius: size * 0.02),
            with: .color(Color(white: 0.55)))
        // Eyes front, always alert (but still a cat: a blink now and then).
        let blink = time.truncatingRemainder(dividingBy: 4.1) < 0.15
        for eye in [0.0, 0.55] as [CGFloat] {
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: head.x + eye * radius - size * 0.018, y: head.y - size * 0.02, width: size * 0.036,
                        height: blink ? size * 0.008 : size * 0.045)),
                with: .color(.black))
        }
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: head.x + radius * 0.75, y: head.y + size * 0.03, width: size * 0.035, height: size * 0.025)),
            with: .color(Color(red: 0.9, green: 0.45, blue: 0.5)))
        // The front paw grips the pike.
        var arm = Path()
        arm.move(to: CGPoint(x: size * 0.05, y: -size * 0.62 - bob))
        arm.addQuadCurve(
            to: CGPoint(x: shaftX, y: -size * 0.62 - bob), control: CGPoint(x: size * 0.12, y: -size * 0.54 - bob))
        context.stroke(arm, with: .color(fur), style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round))
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: shaftX - size * 0.04, y: -size * 0.66 - bob, width: size * 0.08, height: size * 0.08)),
            with: .color(fur))
    }

    /// A weightless cat with an air tank and a bubble helmet, paws paddling at nothing.
    private static func spaceCat(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        context.fill(
            Path(
                roundedRect: CGRect(x: -size * 0.3, y: -size * 0.68, width: size * 0.34, height: size * 0.12),
                cornerRadius: size * 0.05),
            with: .color(Color(white: 0.82)))
        cat(in: &context, size: size, time: time, pose: .float)
        let head = CGPoint(x: size * 0.43, y: -size * 0.66)
        let radius = size * 0.26
        context.fill(
            Path(
                roundedRect: CGRect(
                    x: head.x - radius * 0.55, y: head.y + radius * 0.8, width: radius * 1.1, height: size * 0.06),
                cornerRadius: size * 0.03),
            with: .color(Color(white: 0.75)))
        let bubble = Path(
            ellipseIn: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2))
        context.fill(bubble, with: .color(Color(red: 0.7, green: 0.85, blue: 1).opacity(0.22)))
        context.stroke(bubble, with: .color(.white.opacity(0.85)), lineWidth: size * 0.025)
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: head.x - radius * 0.6, y: head.y - radius * 0.75, width: radius * 0.35, height: radius * 0.22)),
            with: .color(.white.opacity(0.7)))
    }

    /// A little grey mouse, running flat out.
    private static func mouse(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        let grey = Color(white: 0.58)
        let pink = Color(red: 0.95, green: 0.65, blue: 0.68)
        let scurry = CGFloat(sin(time * 40)) * size * 0.05
        var tail = Path()
        tail.move(to: CGPoint(x: -size * 0.4, y: -size * 0.12))
        tail.addQuadCurve(
            to: CGPoint(x: -size * 0.95, y: -size * 0.06 + scurry), control: CGPoint(x: -size * 0.7, y: -size * 0.3))
        context.stroke(tail, with: .color(pink), style: StrokeStyle(lineWidth: size * 0.04, lineCap: .round))
        for (x, sign) in [(0.12, 1.0), (-0.22, -1.0)] as [(CGFloat, CGFloat)] {
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: x * size + sign * scurry, y: -size * 0.07, width: size * 0.14, height: size * 0.07)),
                with: .color(pink))
        }
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.45, y: -size * 0.4, width: size * 0.8, height: size * 0.36)),
            with: .color(grey))
        context.fill(
            Path(ellipseIn: CGRect(x: size * 0.2, y: -size * 0.36, width: size * 0.36, height: size * 0.26)),
            with: .color(grey))
        context.fill(
            Path(ellipseIn: CGRect(x: size * 0.1, y: -size * 0.58, width: size * 0.24, height: size * 0.26)),
            with: .color(grey))
        context.fill(
            Path(ellipseIn: CGRect(x: size * 0.15, y: -size * 0.53, width: size * 0.14, height: size * 0.16)),
            with: .color(pink))
        context.fill(
            Path(ellipseIn: CGRect(x: size * 0.36, y: -size * 0.3, width: size * 0.06, height: size * 0.06)),
            with: .color(.black))
        context.fill(
            Path(ellipseIn: CGRect(x: size * 0.52, y: -size * 0.26, width: size * 0.07, height: size * 0.06)),
            with: .color(pink))
    }

    /// An arched hole at the foot of the wall. `bottom` is the middle of its base.
    private static func mouseHole(in context: inout GraphicsContext, at bottom: CGPoint, width: CGFloat) {
        let hole = Path(
            roundedRect: CGRect(x: bottom.x - width / 2, y: bottom.y - width * 0.75, width: width, height: width),
            cornerRadius: width / 2)
        context.fill(hole, with: .color(Color(white: 0.06)))
        context.stroke(hole, with: .color(.black.opacity(0.4)), lineWidth: 2)
    }
}
