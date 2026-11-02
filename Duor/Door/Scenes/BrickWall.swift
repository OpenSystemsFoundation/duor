import SwiftUI

extension ScenePainter {
    /// An old brick wall: shaded, textured bricks with chipped corners in recessed mortar, grime
    /// at the bottom, ivy climbing up from a corner and moss in the lower joints.
    static func brickWall(in context: inout GraphicsContext, rect: CGRect) {
        context.fill(Path(rect), with: .color(Color(red: 0.6, green: 0.57, blue: 0.52)))
        var random = NoiseSource(seed: 3)
        let brickHeight = max(rect.width * 0.085, 12)
        let brickWidth = brickHeight * 2.3
        let mortar: CGFloat = 3.5
        var row = 0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX - (row.isMultiple(of: 2) ? 0 : brickWidth / 2)
            while x < rect.maxX {
                brick(
                    in: &context,
                    rect: CGRect(
                        x: x + mortar / 2, y: y + mortar / 2, width: brickWidth - mortar, height: brickHeight - mortar),
                    random: &random)
                x += brickWidth
            }
            y += brickHeight
            row += 1
        }
        // Grime rising from the ground and a little soot from above.
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [
                    .black.opacity(0.18), .clear, .clear, Color(red: 0.2, green: 0.18, blue: 0.1).opacity(0.35),
                ]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))

        // Moss along the lowest joints.
        for _ in 0..<60 {
            let point = CGPoint(
                x: rect.minX + CGFloat(random.unit()) * rect.width,
                y: rect.maxY - CGFloat(random.unit()) * rect.height * 0.22)
            let size = CGFloat(random.value(in: 2...6))
            context.fill(
                Path(ellipseIn: CGRect(x: point.x, y: point.y, width: size * 1.6, height: size)),
                with: .color(Color(red: 0.32, green: 0.48, blue: 0.2).opacity(Double(random.value(in: 0.5...0.9)))))
        }

        // Ivy climbing from the bottom-left corner, and a strand hanging from the top right.
        ivy(
            in: &context,
            from: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.maxY),
            through: [
                CGPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY - rect.height * 0.3),
                CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.55),
                CGPoint(x: rect.minX + rect.width * 0.32, y: rect.maxY - rect.height * 0.78),
            ], leafSize: rect.width * 0.085, random: &random)
        ivy(
            in: &context,
            from: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.maxY),
            through: [
                CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.15),
                CGPoint(x: rect.minX + rect.width * 0.55, y: rect.maxY - rect.height * 0.32),
            ], leafSize: rect.width * 0.075, random: &random)
        ivy(
            in: &context,
            from: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY),
            through: [
                CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.minY + rect.height * 0.18),
                CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY + rect.height * 0.32),
            ], leafSize: rect.width * 0.07, random: &random)
    }

    private static func brick(in context: inout GraphicsContext, rect: CGRect, random: inout NoiseSource) {
        // Reds and browns, the odd darker over-fired one.
        let burnt = random.unit() < 0.12
        let tone = Double(random.value(in: -0.07...0.07))
        let base =
            burnt
            ? Color(red: 0.42 + tone, green: 0.2 + tone * 0.5, blue: 0.15)
            : Color(red: 0.7 + tone, green: 0.33 + tone * 0.7, blue: 0.24 + tone * 0.4)
        let shape = Path(roundedRect: rect, cornerRadius: 2)
        context.fill(
            shape,
            with: .linearGradient(
                Gradient(colors: [base.mix(with: .white, by: 0.12), base, base.mix(with: .black, by: 0.18)]),
                startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        // Pitted texture.
        for _ in 0..<Int(rect.width * rect.height / 90) {
            let point = CGPoint(
                x: rect.minX + CGFloat(random.unit()) * rect.width, y: rect.minY + CGFloat(random.unit()) * rect.height)
            let size = 0.8 + CGFloat(random.unit()) * 1.4
            context.fill(
                Path(ellipseIn: CGRect(x: point.x, y: point.y, width: size, height: size)),
                with: .color((random.unit() < 0.5 ? Color.black : Color.white).opacity(0.12)))
        }
        // Recessed look: light on the top edge, shadow under it.
        context.fill(
            Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1.2)), with: .color(.white.opacity(0.18))
        )
        context.fill(
            Path(CGRect(x: rect.minX, y: rect.maxY - 1.8, width: rect.width, height: 1.8)),
            with: .color(.black.opacity(0.28)))
        // Now and then a chipped corner.
        if random.unit() < 0.15 {
            let chip = rect.height * CGFloat(random.value(in: 0.2...0.4))
            var corner = Path()
            let left = random.unit() < 0.5
            let x = left ? rect.minX : rect.maxX
            corner.move(to: CGPoint(x: x, y: rect.minY))
            corner.addLine(to: CGPoint(x: x + (left ? chip : -chip), y: rect.minY))
            corner.addLine(to: CGPoint(x: x, y: rect.minY + chip))
            corner.closeSubpath()
            context.fill(corner, with: .color(Color(red: 0.6, green: 0.57, blue: 0.52)))
        }
    }

    /// A vine through the given points, with leaves along it.
    private static func ivy(
        in context: inout GraphicsContext, from start: CGPoint, through points: [CGPoint], leafSize: CGFloat,
        random: inout NoiseSource
    ) {
        var stem = Path()
        stem.move(to: start)
        var previous = start
        var samples: [CGPoint] = []
        for point in points {
            let control = CGPoint(
                x: (previous.x + point.x) / 2 + CGFloat(random.bipolar()) * leafSize * 2, y: (previous.y + point.y) / 2)
            stem.addQuadCurve(to: point, control: control)
            for step in 1...6 {
                let t = CGFloat(step) / 6
                let a = CGPoint(
                    x: previous.x + (control.x - previous.x) * t, y: previous.y + (control.y - previous.y) * t)
                let b = CGPoint(x: control.x + (point.x - control.x) * t, y: control.y + (point.y - control.y) * t)
                samples.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
            previous = point
        }
        context.stroke(
            stem, with: .color(Color(red: 0.3, green: 0.25, blue: 0.15)),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        let greens = [
            Color(red: 0.22, green: 0.45, blue: 0.18), Color(red: 0.3, green: 0.55, blue: 0.22),
            Color(red: 0.18, green: 0.36, blue: 0.15),
        ]
        for (index, point) in samples.enumerated() {
            for side in [-1.0, 1.0] where random.unit() < 0.8 {
                let size =
                    leafSize * CGFloat(random.value(in: 0.6...1.1))
                    * (1 - CGFloat(index) / CGFloat(samples.count) * 0.4)
                let angle = Angle.degrees(
                    Double(side) * Double(random.value(in: 40...80)) + Double(random.bipolar()) * 20 - 90)
                context.drawLayer { leaf in
                    leaf.translateBy(x: point.x, y: point.y)
                    leaf.rotate(by: angle)
                    var shape = Path()
                    shape.move(to: .zero)
                    shape.addQuadCurve(to: CGPoint(x: size, y: 0), control: CGPoint(x: size * 0.4, y: -size * 0.5))
                    shape.addQuadCurve(to: .zero, control: CGPoint(x: size * 0.4, y: size * 0.5))
                    leaf.fill(shape, with: .color(greens[Int(random.unit() * 3) % 3]))
                    var vein = Path()
                    vein.move(to: .zero)
                    vein.addLine(to: CGPoint(x: size * 0.85, y: 0))
                    leaf.stroke(vein, with: .color(.black.opacity(0.2)), lineWidth: 0.8)
                }
            }
        }
    }
}

extension SceneLife {
    static func brickWall(
        in context: inout GraphicsContext, rect: CGRect, time: TimeInterval, catLovers: Bool
    ) {
        // A spider lowers itself down to say hi, then climbs back up.
        if let visit = visit(time: time, period: 12, duration: 6, salt: 12) {
            let size = rect.width * 0.08
            let x = rect.minX + rect.width * (0.15 + 0.7 * visit.lane)
            let drop = sin(visit.progress * .pi) * rect.height * 0.35
            let body = CGPoint(x: x, y: rect.minY + drop)
            // The thread runs into the middle of the body, so it's always attached.
            var thread = Path()
            thread.move(to: CGPoint(x: x, y: rect.minY))
            thread.addLine(to: body)
            context.stroke(thread, with: .color(.white.opacity(0.7)), lineWidth: 1)
            critter(in: &context, at: body, facing: 1) {
                spider(in: &$0, size: size, time: time)
            }
        }
        // A very determined snail.
        if let visit = visit(time: time, period: 34, duration: 30, salt: 13) {
            let size = rect.width * 0.14
            let x = visit.x(in: rect, margin: size)
            critter(in: &context, at: CGPoint(x: x, y: rect.maxY - 2), facing: visit.facing) {
                snail(in: &$0, size: size, time: time)
            }
        }
        // A cat chases a mouse, cartoon style. The mouse wins.
        if catLovers {
            catAtTheWall(in: &context, rect: rect, time: time)
        }
    }

    private static func spider(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        for side in [-1.0, 1.0] as [CGFloat] {
            for leg in 0..<4 {
                let angle = Double(leg) * 0.35 - 0.5 + sin(time * 4 + Double(leg)) * 0.1
                var line = Path()
                line.move(to: .zero)
                line.addQuadCurve(
                    to: CGPoint(x: side * size * 0.6, y: CGFloat(sin(angle)) * size * 0.6),
                    control: CGPoint(x: side * size * 0.35, y: -size * 0.3))
                context.stroke(line, with: .color(.black), lineWidth: 1.5)
            }
        }
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.22, y: -size * 0.22, width: size * 0.44, height: size * 0.44)),
            with: .color(Color(white: 0.1)))
        for eye in [-0.08, 0.08] as [CGFloat] {
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: eye * size - size * 0.05, y: -size * 0.05, width: size * 0.1, height: size * 0.1)),
                with: .color(.white))
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: eye * size - size * 0.02, y: -size * 0.02, width: size * 0.04, height: size * 0.04)),
                with: .color(.black))
        }
    }

    private static func snail(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        let stretch = CGFloat(sin(time * 2)) * size * 0.04
        let body = Color(red: 0.75, green: 0.68, blue: 0.5)
        context.fill(
            Path(
                roundedRect: CGRect(x: -size * 0.45, y: -size * 0.12, width: size * 0.9 + stretch, height: size * 0.12),
                cornerRadius: size * 0.06), with: .color(body))
        for eye in [0.0, 0.08] as [CGFloat] {
            var stalk = Path()
            stalk.move(to: CGPoint(x: size * 0.35 + stretch, y: -size * 0.1))
            stalk.addLine(to: CGPoint(x: size * (0.42 + eye) + stretch, y: -size * 0.3))
            context.stroke(stalk, with: .color(body), lineWidth: 2)
            context.fill(
                Path(ellipseIn: CGRect(x: size * (0.42 + eye) + stretch - 3, y: -size * 0.33, width: 6, height: 6)),
                with: .color(Color(white: 0.15)))
        }
        let shell = CGRect(x: -size * 0.35, y: -size * 0.55, width: size * 0.5, height: size * 0.48)
        context.fill(Path(ellipseIn: shell), with: .color(Color(red: 0.62, green: 0.38, blue: 0.22)))
        for ring in 1...3 {
            let inset = CGFloat(ring) * size * 0.06
            context.stroke(
                Path(ellipseIn: shell.insetBy(dx: inset, dy: inset)),
                with: .color(Color(red: 0.42, green: 0.24, blue: 0.13)), lineWidth: 1.5)
        }
    }

    // MARK: Cat

    /// At the brick wall: a cat chasing a mouse, cartoon style. The mouse wins.
    static func catAtTheWall(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval) {
        let duration = CatStory.pounceDuration
        guard let visit = Self.visit(time: time, period: 20, duration: duration, salt: 22) else { return }
        let t = visit.progress * duration
        let ground = rect.maxY - 1
        if let frame = CatStory.mouse(at: t) {
            let size = rect.width * 0.09
            let point = CGPoint(
                x: sceneX(frame.across, in: rect, facing: visit.facing), y: ground - CGFloat(frame.lift) * size)
            critter(in: &context, at: point, facing: frame.facesBack ? -visit.facing : visit.facing) {
                mouse(in: &$0, size: size, time: time, running: frame.running)
            }
        }
        if let frame = CatStory.pounce(at: t) {
            paintCat(
                in: &context, frame: frame, rect: rect, ground: ground, size: rect.width * 0.3, facing: visit.facing,
                time: time)
        }
    }

    /// A little grey mouse, running flat out, or standing with its nose twitching.
    private static func mouse(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval, running: Bool) {
        let grey = Color(white: 0.58)
        let pink = Color(red: 0.95, green: 0.65, blue: 0.68)
        let scurry = running ? CGFloat(sin(time * 40)) * size * 0.05 : 0
        let twitch = running ? 0 : CGFloat(sin(time * 30)) * size * 0.02
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
            Path(ellipseIn: CGRect(x: size * 0.52, y: -size * 0.26 + twitch, width: size * 0.07, height: size * 0.06)),
            with: .color(pink))
    }
}
