import SwiftUI

extension ScenePainter {
    /// A castle hall: stone walls, banners, torch sconces, flagstones and a long red carpet.
    /// The torch flames live in the animated layer.
    static func greatHall(in context: inout GraphicsContext, rect: CGRect) {
        let horizon = rect.minY + rect.height * 0.64
        // Stone blocks, staggered, each a slightly different grey.
        var random = NoiseSource(seed: 17)
        let stoneHeight = max(rect.height * 0.065, 14)
        let stoneWidth = stoneHeight * 1.9
        var row = 0
        var y = rect.minY
        while y < horizon {
            var x = rect.minX - (row.isMultiple(of: 2) ? 0 : stoneWidth / 2)
            while x < rect.maxX {
                let tone = Double(random.value(in: -0.06...0.06))
                let stone = CGRect(x: x + 1.5, y: y + 1.5, width: stoneWidth - 3, height: stoneHeight - 3)
                context.fill(
                    Path(roundedRect: stone, cornerRadius: 3),
                    with: .color(Color(red: 0.45 + tone, green: 0.43 + tone, blue: 0.42 + tone)))
                x += stoneWidth
            }
            y += stoneHeight
            row += 1
        }
        context.fill(
            Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: horizon - rect.minY)),
            with: .linearGradient(
                Gradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.2)]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: horizon)))

        // Banners.
        for fraction in [0.25, 0.75] {
            let width = rect.width * 0.2
            let top = rect.minY + rect.height * 0.06
            let x = rect.minX + rect.width * fraction - width / 2
            var banner = Path()
            banner.move(to: CGPoint(x: x, y: top))
            banner.addLine(to: CGPoint(x: x + width, y: top))
            banner.addLine(to: CGPoint(x: x + width, y: top + rect.height * 0.3))
            banner.addLine(to: CGPoint(x: x + width / 2, y: top + rect.height * 0.25))
            banner.addLine(to: CGPoint(x: x, y: top + rect.height * 0.3))
            banner.closeSubpath()
            context.fill(banner, with: .color(Color(red: 0.62, green: 0.1, blue: 0.12)))
            context.stroke(banner, with: .color(Color(red: 0.9, green: 0.72, blue: 0.3)), lineWidth: 2)
            let emblem = width * 0.36
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: x + width / 2 - emblem / 2, y: top + rect.height * 0.09, width: emblem, height: emblem)),
                with: .color(Color(red: 0.9, green: 0.72, blue: 0.3)))
            context.fill(
                Path(CGRect(x: x - 4, y: top - 3, width: width + 8, height: 4)), with: .color(Color(white: 0.2)))
        }

        // Torch sconces (the flames are animated).
        for point in SceneLife.torchPositions(in: rect) {
            context.fill(
                Path(
                    roundedRect: CGRect(
                        x: point.x - rect.width * 0.02, y: point.y, width: rect.width * 0.04, height: rect.height * 0.07
                    ),
                    cornerRadius: 2), with: .color(Color(white: 0.18)))
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: point.x - rect.width * 0.4, y: point.y - rect.width * 0.4, width: rect.width * 0.8,
                        height: rect.width * 0.8)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 1, green: 0.65, blue: 0.25).opacity(0.35), .clear]), center: point,
                    startRadius: 0, endRadius: rect.width * 0.4))
        }

        // Flagstone floor and the carpet runner.
        let floor = CGRect(x: rect.minX, y: horizon, width: rect.width, height: rect.maxY - horizon)
        context.fill(
            Path(floor),
            with: .linearGradient(
                Gradient(colors: [Color(white: 0.28), Color(white: 0.4)]),
                startPoint: CGPoint(x: floor.midX, y: floor.minY),
                endPoint: CGPoint(x: floor.midX, y: floor.maxY)))
        for index in 1..<5 {
            let t = CGFloat(index) / 5
            let lineY = horizon + floor.height * t * t
            context.fill(
                Path(CGRect(x: rect.minX, y: lineY, width: rect.width, height: 1.5)), with: .color(.black.opacity(0.3)))
        }
        var carpet = Path()
        carpet.move(to: CGPoint(x: rect.midX - rect.width * 0.08, y: horizon))
        carpet.addLine(to: CGPoint(x: rect.midX + rect.width * 0.08, y: horizon))
        carpet.addLine(to: CGPoint(x: rect.midX + rect.width * 0.32, y: rect.maxY))
        carpet.addLine(to: CGPoint(x: rect.midX - rect.width * 0.32, y: rect.maxY))
        carpet.closeSubpath()
        context.fill(carpet, with: .color(Color(red: 0.55, green: 0.08, blue: 0.1)))
        context.stroke(carpet, with: .color(Color(red: 0.9, green: 0.72, blue: 0.3).opacity(0.8)), lineWidth: 2)
    }
}

extension SceneLife {
    static func torchPositions(in rect: CGRect) -> [CGPoint] {
        [0.08, 0.92].map { CGPoint(x: rect.minX + rect.width * $0, y: rect.minY + rect.height * 0.3) }
    }

    static func greatHall(
        in context: inout GraphicsContext, rect: CGRect, time: TimeInterval, catLovers: Bool
    ) {
        for (index, point) in torchPositions(in: rect).enumerated() {
            flame(in: &context, at: point, size: rect.width * 0.07, time: time + Double(index) * 1.7)
        }
        // A cat guard on patrol, at the back of the hall.
        if catLovers {
            catOnPatrol(in: &context, rect: rect, time: time)
        }
        // A small knight on patrol.
        if let visit = visit(time: time, period: 13, duration: 7, salt: 2) {
            let size = rect.height * 0.28
            let x = visit.x(in: rect, margin: size)
            critter(in: &context, at: CGPoint(x: x, y: rect.minY + rect.height * 0.9), facing: visit.facing) {
                knight(in: &$0, size: size, time: time)
            }
        }
        // A bat flutters through the rafters.
        if let visit = visit(time: time, period: 9, duration: 3, salt: 3) {
            let size = rect.width * 0.14
            let x = visit.x(in: rect, margin: size)
            let y = rect.minY + rect.height * (0.12 + 0.15 * visit.lane) + sin(time * 5) * rect.height * 0.02
            critter(in: &context, at: CGPoint(x: x, y: y), facing: visit.facing) {
                bat(in: &$0, size: size, time: time)
            }
        }
    }

    private static func knight(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        let steel = Color(white: 0.72)
        let step = time * 7
        let bob = CGFloat(abs(sin(step))) * size * 0.025
        for phase in [0.0, Double.pi] {
            var leg = Path()
            leg.move(to: CGPoint(x: 0, y: -size * 0.35))
            leg.addLine(to: CGPoint(x: CGFloat(sin(step + phase)) * size * 0.1, y: 0))
            context.stroke(
                leg, with: .color(Color(white: 0.55)), style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
        }
        context.fill(
            Path(
                roundedRect: CGRect(x: -size * 0.14, y: -size * 0.68 - bob, width: size * 0.28, height: size * 0.36),
                cornerRadius: size * 0.05),
            with: .linearGradient(
                Gradient(colors: [Color(white: 0.9), steel, Color(white: 0.5)]),
                startPoint: CGPoint(x: -size * 0.14, y: 0),
                endPoint: CGPoint(x: size * 0.14, y: 0)))
        // Helmet with a visor slit and a red plume.
        let helmet = CGRect(x: -size * 0.12, y: -size * 0.92 - bob, width: size * 0.24, height: size * 0.25)
        context.fill(Path(roundedRect: helmet, cornerRadius: size * 0.08), with: .color(steel))
        context.fill(
            Path(
                CGRect(
                    x: helmet.minX + size * 0.08, y: helmet.midY - size * 0.015, width: size * 0.14, height: size * 0.03
                )),
            with: .color(.black.opacity(0.8)))
        var plume = Path()
        plume.move(to: CGPoint(x: 0, y: helmet.minY))
        plume.addQuadCurve(
            to: CGPoint(x: -size * 0.2, y: helmet.minY + size * 0.05 + CGFloat(sin(step)) * size * 0.02),
            control: CGPoint(x: -size * 0.05, y: helmet.minY - size * 0.15))
        context.stroke(
            plume, with: .color(Color(red: 0.8, green: 0.12, blue: 0.12)),
            style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
        // Shield in front.
        let shield = CGRect(x: size * 0.04, y: -size * 0.66 - bob, width: size * 0.22, height: size * 0.28)
        context.fill(
            Path(roundedRect: shield, cornerRadius: size * 0.06), with: .color(Color(red: 0.6, green: 0.1, blue: 0.12)))
        context.fill(
            Path(
                CGRect(
                    x: shield.midX - size * 0.015, y: shield.minY + size * 0.03, width: size * 0.03,
                    height: shield.height - size * 0.06)), with: .color(Color(red: 0.95, green: 0.78, blue: 0.3)))
        context.fill(
            Path(
                CGRect(
                    x: shield.minX + size * 0.03, y: shield.minY + size * 0.09, width: shield.width - size * 0.06,
                    height: size * 0.03)), with: .color(Color(red: 0.95, green: 0.78, blue: 0.3)))
    }

    private static func bat(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        let flap = CGFloat(sin(time * 22))
        let color = Color(red: 0.18, green: 0.12, blue: 0.22)
        for side in [-1.0, 1.0] as [CGFloat] {
            var wing = Path()
            wing.move(to: CGPoint(x: 0, y: 0))
            wing.addLine(to: CGPoint(x: side * size * 0.5, y: -size * 0.25 * flap))
            wing.addQuadCurve(
                to: CGPoint(x: side * size * 0.3, y: size * 0.05),
                control: CGPoint(x: side * size * 0.45, y: size * 0.1))
            wing.addQuadCurve(
                to: CGPoint(x: side * size * 0.1, y: size * 0.08), control: CGPoint(x: side * size * 0.2, y: 0))
            wing.closeSubpath()
            context.fill(wing, with: .color(color))
        }
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.08, y: -size * 0.08, width: size * 0.16, height: size * 0.2)),
            with: .color(color))
        for eye in [-0.03, 0.03] as [CGFloat] {
            context.fill(
                Path(ellipseIn: CGRect(x: eye * size - 1.5, y: -size * 0.03, width: 3, height: 3)),
                with: .color(Color(red: 1, green: 0.85, blue: 0.3)))
        }
    }

    private static func flame(in context: inout GraphicsContext, at point: CGPoint, size: CGFloat, time: TimeInterval) {
        // Two overlapping tongues, each flickering at its own pace.
        let flicker = CGFloat(0.85 + 0.15 * sin(time * 13) * sin(time * 7.3))
        let lean = CGFloat(sin(time * 5.1)) * size * 0.12
        for (scale, color) in [
            (1.0, Color(red: 1, green: 0.45, blue: 0.1)), (0.6, Color(red: 1, green: 0.85, blue: 0.35)),
        ] as [(CGFloat, Color)] {
            let height = size * 1.6 * flicker * scale
            let width = size * 0.7 * scale
            var tongue = Path()
            tongue.move(to: CGPoint(x: point.x - width / 2, y: point.y))
            tongue.addQuadCurve(
                to: CGPoint(x: point.x + lean, y: point.y - height),
                control: CGPoint(x: point.x - width * 0.6, y: point.y - height * 0.5))
            tongue.addQuadCurve(
                to: CGPoint(x: point.x + width / 2, y: point.y),
                control: CGPoint(x: point.x + width * 0.6, y: point.y - height * 0.5))
            tongue.closeSubpath()
            context.fill(tongue, with: .color(color))
        }
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - size * 2, y: point.y - size * 2.5, width: size * 4, height: size * 4)),
            with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.6, blue: 0.2).opacity(0.25 * Double(flicker)), .clear]),
                center: CGPoint(x: point.x, y: point.y - size * 0.6), startRadius: 0, endRadius: size * 2))
    }

    // MARK: Cat

    /// In the great hall: a guard on two legs, pike and kettle hat, patrolling at the back.
    static func catOnPatrol(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval) {
        guard let visit = Self.visit(time: time, period: 19, duration: 13, salt: 20) else { return }
        let size = rect.height * 0.17
        let point = CGPoint(x: visit.x(in: rect, margin: size * 0.6), y: rect.minY + rect.height * 0.7)
        critter(in: &context, at: point, facing: visit.facing) {
            guardCat(in: &$0, size: size, time: time)
        }
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
}
