import SwiftUI

/// What you see through the doorway. Each scene paints itself into the door opening.
enum ScenePainter {
    static func paint(_ scene: InsideScene, in context: inout GraphicsContext, rect: CGRect) {
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            switch scene {
            case .livingRoom: livingRoom(in: &layer, rect: rect)
            case .greatHall: greatHall(in: &layer, rect: rect)
            case .beach: beach(in: &layer, rect: rect)
            case .forest: forest(in: &layer, rect: rect)
            case .space: space(in: &layer, rect: rect)
            case .brickWall: brickWall(in: &layer, rect: rect)
            }
        }
    }

    /// A castle hall: stone walls, banners, torch sconces, flagstones and a long red carpet.
    /// The torch flames live in the animated layer.
    private static func greatHall(in context: inout GraphicsContext, rect: CGRect) {
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

    /// Sky, sea, a sun, and sand with ripples, shells and a starfish.
    private static func beach(in context: inout GraphicsContext, rect: CGRect) {
        let horizon = rect.minY + rect.height * 0.5
        let shore = rect.minY + rect.height * 0.66
        context.fill(
            Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: horizon - rect.minY)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.36, green: 0.66, blue: 0.93), Color(red: 0.78, green: 0.9, blue: 0.97)]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: horizon)))
        let sun = rect.width * 0.18
        let sunCenter = CGPoint(x: rect.minX + rect.width * 0.7, y: rect.minY + rect.height * 0.18)
        context.fill(
            Path(ellipseIn: CGRect(x: sunCenter.x - sun, y: sunCenter.y - sun, width: sun * 2, height: sun * 2)),
            with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.7).opacity(0.7), .clear]), center: sunCenter,
                startRadius: 0, endRadius: sun))
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: sunCenter.x - sun / 3, y: sunCenter.y - sun / 3, width: sun / 1.5, height: sun / 1.5)),
            with: .color(Color(red: 1, green: 0.9, blue: 0.5)))
        // Clouds drift by in the animated layer (`SceneLife`).
        context.fill(
            Path(CGRect(x: rect.minX, y: horizon, width: rect.width, height: shore - horizon)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.1, green: 0.42, blue: 0.62), Color(red: 0.25, green: 0.66, blue: 0.75)]),
                startPoint: CGPoint(x: rect.midX, y: horizon), endPoint: CGPoint(x: rect.midX, y: shore)))
        context.fill(
            Path(CGRect(x: rect.minX, y: shore, width: rect.width, height: rect.maxY - shore)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.95, green: 0.86, blue: 0.66), Color(red: 0.88, green: 0.74, blue: 0.52)]
                ),
                startPoint: CGPoint(x: rect.midX, y: shore), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        var foam = Path()
        foam.move(to: CGPoint(x: rect.minX, y: shore))
        foam.addQuadCurve(to: CGPoint(x: rect.maxX, y: shore + 6), control: CGPoint(x: rect.midX, y: shore + 14))
        context.stroke(foam, with: .color(.white.opacity(0.8)), lineWidth: 3)

        // Wet sand along the waterline, ripples, speckles, then shells and a starfish.
        context.fill(
            Path(CGRect(x: rect.minX, y: shore, width: rect.width, height: (rect.maxY - shore) * 0.18)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.78, green: 0.66, blue: 0.48).opacity(0.7), .clear]),
                startPoint: CGPoint(x: rect.midX, y: shore),
                endPoint: CGPoint(x: rect.midX, y: shore + (rect.maxY - shore) * 0.18)))
        var random = NoiseSource(seed: 61)
        for index in 0..<6 {
            let y = shore + (rect.maxY - shore) * (0.28 + 0.12 * CGFloat(index))
            var ripple = Path()
            ripple.move(to: CGPoint(x: rect.minX, y: y))
            var x = rect.minX
            while x < rect.maxX {
                let span = rect.width * CGFloat(random.value(in: 0.12...0.22))
                ripple.addQuadCurve(
                    to: CGPoint(x: x + span, y: y + CGFloat(random.value(in: -3...3))),
                    control: CGPoint(x: x + span / 2, y: y - 4))
                x += span
            }
            context.stroke(ripple, with: .color(Color(red: 0.72, green: 0.58, blue: 0.4).opacity(0.35)), lineWidth: 1.2)
        }
        for _ in 0..<260 {
            let point = CGPoint(
                x: rect.minX + CGFloat(random.unit()) * rect.width,
                y: shore + 4 + CGFloat(random.unit()) * (rect.maxY - shore - 4))
            let grain = 0.8 + CGFloat(random.unit()) * 1.4
            let light = random.unit() < 0.5
            context.fill(
                Path(ellipseIn: CGRect(x: point.x, y: point.y, width: grain, height: grain)),
                with: .color(light ? .white.opacity(0.5) : Color(red: 0.6, green: 0.46, blue: 0.3).opacity(0.5)))
        }
        let sand = rect.maxY - shore
        scallop(
            in: &context, at: CGPoint(x: rect.minX + rect.width * 0.22, y: shore + sand * 0.62),
            size: rect.width * 0.09,
            color: Color(red: 0.98, green: 0.78, blue: 0.72), tilt: -12)
        scallop(
            in: &context, at: CGPoint(x: rect.minX + rect.width * 0.7, y: shore + sand * 0.82), size: rect.width * 0.07,
            color: Color(red: 0.98, green: 0.92, blue: 0.82), tilt: 18)
        spiralShell(
            in: &context, at: CGPoint(x: rect.minX + rect.width * 0.48, y: shore + sand * 0.5), size: rect.width * 0.06)
        starfish(
            in: &context, at: CGPoint(x: rect.minX + rect.width * 0.84, y: shore + sand * 0.45), size: rect.width * 0.08
        )
    }

    private static func scallop(
        in context: inout GraphicsContext, at point: CGPoint, size: CGFloat, color: Color, tilt: Double
    ) {
        context.drawLayer { layer in
            layer.translateBy(x: point.x, y: point.y)
            layer.rotate(by: .degrees(tilt))
            layer.addFilter(.shadow(color: .black.opacity(0.2), radius: 1.5, x: 1, y: 1.5))
            var fan = Path()
            fan.move(to: CGPoint(x: 0, y: size * 0.4))
            fan.addArc(
                center: CGPoint(x: 0, y: size * 0.4), radius: size * 0.6, startAngle: .degrees(200),
                endAngle: .degrees(340), clockwise: false)
            fan.closeSubpath()
            layer.fill(fan, with: .color(color))
            for rib in 0..<6 {
                let angle = Angle.degrees(205 + Double(rib) * 26)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size * 0.4))
                line.addLine(
                    to: CGPoint(x: cos(angle.radians) * size * 0.58, y: size * 0.4 + sin(angle.radians) * size * 0.58))
                layer.stroke(line, with: .color(color.mix(with: .brown, by: 0.35)), lineWidth: 1)
            }
            layer.fill(
                Path(
                    roundedRect: CGRect(x: -size * 0.1, y: size * 0.33, width: size * 0.2, height: size * 0.12),
                    cornerRadius: 2),
                with: .color(color.mix(with: .brown, by: 0.2)))
        }
    }

    private static func spiralShell(in context: inout GraphicsContext, at point: CGPoint, size: CGFloat) {
        context.drawLayer { layer in
            layer.translateBy(x: point.x, y: point.y)
            layer.addFilter(.shadow(color: .black.opacity(0.2), radius: 1.5, x: 1, y: 1.5))
            layer.fill(
                Path(ellipseIn: CGRect(x: -size / 2, y: -size * 0.4, width: size, height: size * 0.8)),
                with: .color(Color(red: 0.93, green: 0.82, blue: 0.66)))
            var spiral = Path()
            var angle = 0.0
            var radius = size * 0.38
            spiral.move(to: CGPoint(x: radius, y: 0))
            while radius > 1.5 {
                angle += 0.3
                radius *= 0.95
                spiral.addLine(to: CGPoint(x: cos(angle) * radius, y: sin(angle) * radius * 0.8))
            }
            layer.stroke(spiral, with: .color(Color(red: 0.62, green: 0.45, blue: 0.3)), lineWidth: 1.2)
        }
    }

    private static func starfish(in context: inout GraphicsContext, at point: CGPoint, size: CGFloat) {
        var star = Path()
        for index in 0..<10 {
            let angle = Double(index) / 10 * .pi * 2 - .pi / 2 + 0.3
            let radius = index.isMultiple(of: 2) ? size * 0.5 : size * 0.2
            let corner = CGPoint(x: point.x + cos(angle) * radius, y: point.y + sin(angle) * radius * 0.7)
            if index == 0 { star.move(to: corner) } else { star.addLine(to: corner) }
        }
        star.closeSubpath()
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.2), radius: 1.5, x: 1, y: 1.5))
            layer.fill(star, with: .color(Color(red: 0.95, green: 0.55, blue: 0.3)))
        }
        context.stroke(
            star, with: .color(Color(red: 0.8, green: 0.38, blue: 0.2)),
            style: StrokeStyle(lineWidth: 1, lineJoin: .round))
    }

    /// A low wooden cabinet on short legs, two doors, and a vase of flowers on top.
    private static func cabinet(in context: inout GraphicsContext, rect: CGRect, floor: CGFloat) {
        let width = rect.width * 0.28
        let height = rect.height * 0.11
        let body = CGRect(
            x: rect.minX + rect.width * 0.05, y: floor + rect.height * 0.01 - height, width: width,
            height: height * 0.86)
        let wood = Color(red: 0.55, green: 0.35, blue: 0.2)
        // Legs.
        for x in [body.minX + width * 0.06, body.maxX - width * 0.1] {
            context.fill(
                Path(CGRect(x: x, y: body.maxY, width: width * 0.04, height: height * 0.14)),
                with: .color(wood.mix(with: .black, by: 0.35)))
        }
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: 3))
            layer.fill(Path(roundedRect: body, cornerRadius: 3), with: .color(wood))
        }
        // Top board, doors and knobs.
        context.fill(
            Path(
                roundedRect: CGRect(x: body.minX - 3, y: body.minY - 3, width: body.width + 6, height: 5),
                cornerRadius: 2),
            with: .color(wood.mix(with: .white, by: 0.12)))
        for index in 0..<2 {
            let door = CGRect(
                x: body.minX + width * (0.06 + 0.46 * CGFloat(index)), y: body.minY + height * 0.12,
                width: width * 0.42,
                height: body.height - height * 0.24)
            context.stroke(Path(roundedRect: door, cornerRadius: 2), with: .color(.black.opacity(0.3)), lineWidth: 1.5)
            let knob = CGPoint(x: index == 0 ? door.maxX - width * 0.05 : door.minX + width * 0.05, y: door.midY)
            context.fill(
                Path(ellipseIn: CGRect(x: knob.x - 2.5, y: knob.y - 2.5, width: 5, height: 5)),
                with: .color(Color(red: 0.85, green: 0.7, blue: 0.4)))
        }

        // Vase.
        let vaseWidth = width * 0.22
        let vaseBottom = body.minY - 3
        let vaseX = body.midX
        var vase = Path()
        vase.move(to: CGPoint(x: vaseX - vaseWidth * 0.3, y: vaseBottom))
        vase.addQuadCurve(
            to: CGPoint(x: vaseX - vaseWidth * 0.18, y: vaseBottom - vaseWidth * 1.1),
            control: CGPoint(x: vaseX - vaseWidth * 0.75, y: vaseBottom - vaseWidth * 0.5))
        vase.addLine(to: CGPoint(x: vaseX + vaseWidth * 0.18, y: vaseBottom - vaseWidth * 1.1))
        vase.addQuadCurve(
            to: CGPoint(x: vaseX + vaseWidth * 0.3, y: vaseBottom),
            control: CGPoint(x: vaseX + vaseWidth * 0.75, y: vaseBottom - vaseWidth * 0.5))
        vase.closeSubpath()
        // Flowers: stems fanning out of the vase, leaves, then the blooms.
        let mouth = CGPoint(x: vaseX, y: vaseBottom - vaseWidth * 1.05)
        let blooms: [(dx: CGFloat, dy: CGFloat, color: Color)] = [
            (-0.55, 1.5, Color(red: 0.95, green: 0.45, blue: 0.55)),
            (-0.15, 1.95, Color(red: 0.98, green: 0.82, blue: 0.3)),
            (0.25, 1.75, Color(red: 0.9, green: 0.3, blue: 0.3)),
            (0.6, 1.35, Color(red: 0.98, green: 0.65, blue: 0.75)),
            (0.05, 1.3, Color(red: 0.75, green: 0.55, blue: 0.95)),
        ]
        for bloom in blooms {
            let head = CGPoint(x: mouth.x + bloom.dx * vaseWidth, y: mouth.y - bloom.dy * vaseWidth)
            var stem = Path()
            stem.move(to: mouth)
            stem.addQuadCurve(
                to: head,
                control: CGPoint(x: mouth.x + bloom.dx * vaseWidth * 0.3, y: mouth.y - bloom.dy * vaseWidth * 0.6))
            context.stroke(stem, with: .color(Color(red: 0.3, green: 0.5, blue: 0.25)), lineWidth: 1.5)
        }
        for side in [-1.0, 1.0] as [CGFloat] {
            var leaf = Path()
            leaf.move(to: mouth)
            leaf.addQuadCurve(
                to: CGPoint(x: mouth.x + side * vaseWidth * 0.8, y: mouth.y - vaseWidth * 0.5),
                control: CGPoint(x: mouth.x + side * vaseWidth * 0.2, y: mouth.y - vaseWidth * 0.7))
            leaf.addQuadCurve(
                to: mouth, control: CGPoint(x: mouth.x + side * vaseWidth * 0.6, y: mouth.y - vaseWidth * 0.1))
            context.fill(leaf, with: .color(Color(red: 0.32, green: 0.55, blue: 0.27)))
        }
        for bloom in blooms {
            let head = CGPoint(x: mouth.x + bloom.dx * vaseWidth, y: mouth.y - bloom.dy * vaseWidth)
            let petal = vaseWidth * 0.17
            for index in 0..<5 {
                let angle = Double(index) / 5 * .pi * 2
                let center = CGPoint(x: head.x + cos(angle) * petal * 0.9, y: head.y + sin(angle) * petal * 0.9)
                context.fill(
                    Path(
                        ellipseIn: CGRect(x: center.x - petal, y: center.y - petal, width: petal * 2, height: petal * 2)
                    ), with: .color(bloom.color))
            }
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: head.x - petal * 0.7, y: head.y - petal * 0.7, width: petal * 1.4, height: petal * 1.4)),
                with: .color(Color(red: 1, green: 0.9, blue: 0.45)))
        }
        context.fill(
            vase,
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.3, green: 0.5, blue: 0.75), Color(red: 0.18, green: 0.32, blue: 0.55)]),
                startPoint: CGPoint(x: vaseX - vaseWidth / 2, y: 0), endPoint: CGPoint(x: vaseX + vaseWidth / 2, y: 0)))
        var shine = Path()
        shine.move(to: CGPoint(x: vaseX - vaseWidth * 0.32, y: vaseBottom - vaseWidth * 0.75))
        shine.addQuadCurve(
            to: CGPoint(x: vaseX - vaseWidth * 0.3, y: vaseBottom - vaseWidth * 0.2),
            control: CGPoint(x: vaseX - vaseWidth * 0.45, y: vaseBottom - vaseWidth * 0.45))
        context.stroke(shine, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    /// A winding path leading into a glowing passage through a pine forest at golden hour.
    ///
    /// Painted back to front with atmospheric perspective: hazy far pines, a mist band, mid groves
    /// framing the passage, sunlit ground and path, foreground trunks under a leafy canopy, then
    /// sunbeams and big bushes.
    private static func forest(in context: inout GraphicsContext, rect: CGRect) {
        let horizon = rect.minY + rect.height * 0.6
        let sun = ForestLayout.passage(in: rect)
        var random = NoiseSource(seed: 21)

        // Sky and the low sun glowing at the end of the passage.
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.99, green: 0.88, blue: 0.68), Color(red: 0.98, green: 0.74, blue: 0.5),
                    Color(red: 0.95, green: 0.62, blue: 0.42),
                ]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: horizon)))
        context.fill(
            Path(rect),
            with: .radialGradient(
                Gradient(colors: [
                    Color(red: 1, green: 0.98, blue: 0.86), Color(red: 1, green: 0.9, blue: 0.66).opacity(0.6), .clear,
                ]),
                center: CGPoint(x: sun.x, y: sun.y - rect.height * 0.04), startRadius: 0, endRadius: rect.width * 0.45))

        // Far pines, pale with haze, and a mist band at their feet.
        pineRow(
            in: &context, rect: rect, base: horizon, color: Color(red: 0.72, green: 0.66, blue: 0.56),
            heights: 0.16...0.26, width: 0.08, spacing: 0.45...0.7, gap: nil, random: &random)
        mist(in: &context, rect: rect, y: horizon, height: rect.height * 0.08, opacity: 0.7)
        pineRow(
            in: &context, rect: rect, base: horizon + rect.height * 0.015,
            color: Color(red: 0.55, green: 0.56, blue: 0.45),
            heights: 0.22...0.32, width: 0.1, spacing: 0.5...0.75, gap: (sun.x, rect.width * 0.08), random: &random)
        mist(in: &context, rect: rect, y: horizon + rect.height * 0.02, height: rect.height * 0.06, opacity: 0.5)

        // Sunlit ground: warm near the passage, cooler and darker toward you.
        let ground = CGRect(x: rect.minX, y: horizon, width: rect.width, height: rect.maxY - horizon)
        context.fill(
            Path(ground),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.62, green: 0.62, blue: 0.3), Color(red: 0.36, green: 0.5, blue: 0.22),
                    Color(red: 0.2, green: 0.33, blue: 0.15),
                ]),
                startPoint: CGPoint(x: rect.midX, y: ground.minY), endPoint: CGPoint(x: rect.midX, y: ground.maxY)))

        // Mid groves either side of the passage, darker and larger.
        pineRow(
            in: &context, rect: rect, base: horizon + rect.height * 0.05,
            color: Color(red: 0.25, green: 0.36, blue: 0.24),
            heights: 0.36...0.5, width: 0.15, spacing: 0.45...0.7, gap: (sun.x, rect.width * 0.17), random: &random)
        mist(in: &context, rect: rect, y: horizon + rect.height * 0.05, height: rect.height * 0.04, opacity: 0.25)

        // The winding path, brightest where it meets the light.
        let path = ForestLayout.pathOutline(in: rect)
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.6, green: 0.46, blue: 0.3), Color(red: 0.8, green: 0.66, blue: 0.46),
                    Color(red: 1, green: 0.92, blue: 0.74),
                ]),
                startPoint: CGPoint(x: rect.midX, y: rect.maxY), endPoint: sun))
        for _ in 0..<50 {
            let t = CGFloat(random.unit()) * 0.75
            let center = ForestLayout.pathPoint(at: t, in: rect)
            let pebble = (1.5 + CGFloat(random.unit()) * 2.5) * (1 - t)
            let offset = (CGFloat(random.unit()) - 0.5) * ForestLayout.pathWidth(at: t, in: rect) * 0.8
            context.fill(
                Path(ellipseIn: CGRect(x: center.x + offset, y: center.y, width: pebble * 1.5, height: pebble)),
                with: .color(Color(red: 0.45, green: 0.36, blue: 0.26).opacity(0.5)))
        }

        // Grass tufts everywhere except on the path; bigger toward you.
        for _ in 0..<170 {
            let point = CGPoint(
                x: rect.minX + CGFloat(random.unit()) * rect.width,
                y: horizon + rect.height * 0.04 + CGFloat(random.unit()) * (rect.maxY - horizon - rect.height * 0.04))
            guard !path.contains(point) else { continue }
            let depth = (point.y - horizon) / (rect.maxY - horizon)
            tuft(in: &context, at: point, size: 3 + depth * 9, light: random.unit() < 0.4)
        }

        // Sunbeams fanning out of the passage.
        context.drawLayer { light in
            light.blendMode = .screen
            for (angle, spread, strength) in [
                (-62.0, 7.0, 0.16), (-35.0, 5.0, 0.12), (-12.0, 6.0, 0.18), (14.0, 5.0, 0.12), (40.0, 7.0, 0.15),
                (64.0, 5.0, 0.1),
            ] {
                let length = rect.height * 1.1
                var beam = Path()
                beam.move(to: CGPoint(x: sun.x, y: sun.y - rect.height * 0.03))
                for side in [-1.0, 1.0] {
                    let a = (90 + angle + side * spread) * .pi / 180
                    beam.addLine(to: CGPoint(x: sun.x + cos(a) * length, y: sun.y + sin(a) * length))
                }
                beam.closeSubpath()
                light.fill(
                    beam,
                    with: .radialGradient(
                        Gradient(colors: [Color(red: 1, green: 0.92, blue: 0.7).opacity(strength), .clear]),
                        center: sun, startRadius: 0, endRadius: length))
            }
        }

        // Big bushes along the path, far ones first; the deer hides behind one of them.
        for bush in ForestLayout.bushes(in: rect).sorted(by: { $0.center.y < $1.center.y }) {
            ForestLayout.paintBush(bush, in: &context)
        }

        // Foreground trunks on the right, in front of the bushes, with roots, bark and a warm
        // rim on the side facing the light. The left side stays open.
        ForestLayout.paintTrunks(in: &context, rect: rect)

        // A leafy canopy arching over the passage.
        canopy(in: &context, rect: rect, random: &random)
    }

    /// A row of jagged pine silhouettes. `gap` leaves an opening (center x, half width).
    private static func pineRow(
        in context: inout GraphicsContext, rect: CGRect, base: CGFloat, color: Color, heights: ClosedRange<Float>,
        width: CGFloat, spacing: ClosedRange<Float>, gap: (CGFloat, CGFloat)?, random: inout NoiseSource
    ) {
        var x = rect.minX - rect.width * width
        while x < rect.maxX + rect.width * width {
            let treeWidth = rect.width * width * CGFloat(random.value(in: 0.8...1.2))
            let treeHeight = rect.height * CGFloat(random.value(in: heights))
            if let gap, abs(x - gap.0) < gap.1 + treeWidth * 0.3 {
                x += treeWidth * 0.5
                continue
            }
            let tree = pineSilhouette(
                base: CGPoint(x: x, y: base), width: treeWidth, height: treeHeight, random: &random)
            context.fill(tree, with: .color(color))
            // Light from the passage catches one side.
            context.drawLayer { layer in
                layer.clip(to: tree)
                layer.fill(
                    Path(rect),
                    with: .linearGradient(
                        Gradient(colors: [.clear, Color(red: 1, green: 0.85, blue: 0.6).opacity(0.18)]),
                        startPoint: CGPoint(x: x + (x < rect.midX ? -1 : 1) * treeWidth / 2, y: 0),
                        endPoint: CGPoint(x: x + (x < rect.midX ? 1 : -1) * treeWidth / 2, y: 0)))
            }
            x += treeWidth * CGFloat(random.value(in: spacing))
        }
    }

    /// A pine with ragged tiers of branches.
    private static func pineSilhouette(
        base: CGPoint, width: CGFloat, height: CGFloat, random: inout NoiseSource
    ) -> Path {
        let tiers = 7
        let top = CGPoint(x: base.x, y: base.y - height)
        var right: [CGPoint] = [top]
        var left: [CGPoint] = [top]
        for tier in 1...tiers {
            let fraction = CGFloat(tier) / CGFloat(tiers)
            let y = top.y + height * 0.9 * fraction
            let half = width / 2 * fraction * CGFloat(random.value(in: 0.85...1.1))
            let droop = height * 0.025
            right.append(CGPoint(x: base.x + half, y: y + droop))
            right.append(CGPoint(x: base.x + half * 0.55, y: y - height * 0.03))
            let leftHalf = width / 2 * fraction * CGFloat(random.value(in: 0.85...1.1))
            left.append(CGPoint(x: base.x - leftHalf, y: y + droop))
            left.append(CGPoint(x: base.x - leftHalf * 0.55, y: y - height * 0.03))
        }
        right.append(CGPoint(x: base.x + width * 0.05, y: base.y))
        left.append(CGPoint(x: base.x - width * 0.05, y: base.y))
        var path = Path()
        path.addLines(right + left.reversed())
        path.closeSubpath()
        return path
    }

    /// Haze lying in a band, fading up and down.
    private static func mist(
        in context: inout GraphicsContext, rect: CGRect, y: CGFloat, height: CGFloat, opacity: Double
    ) {
        let band = CGRect(x: rect.minX, y: y - height, width: rect.width, height: height * 2)
        context.fill(
            Path(band),
            with: .linearGradient(
                Gradient(colors: [.clear, Color(red: 1, green: 0.9, blue: 0.75).opacity(opacity), .clear]),
                startPoint: CGPoint(x: 0, y: band.minY), endPoint: CGPoint(x: 0, y: band.maxY)))
    }

    private static func tuft(in context: inout GraphicsContext, at point: CGPoint, size: CGFloat, light: Bool) {
        var blades = Path()
        for lean in [-0.5, -0.15, 0.2, 0.55] as [CGFloat] {
            blades.move(to: point)
            blades.addQuadCurve(
                to: CGPoint(x: point.x + lean * size, y: point.y - size),
                control: CGPoint(x: point.x + lean * size * 0.2, y: point.y - size * 0.6))
        }
        context.stroke(
            blades,
            with: .color(
                light
                    ? Color(red: 0.55, green: 0.66, blue: 0.3).opacity(0.8)
                    : Color(red: 0.14, green: 0.26, blue: 0.12).opacity(0.7)),
            style: StrokeStyle(lineWidth: max(1, size * 0.12), lineCap: .round))
    }

    /// A tree trunk tapering upward, flaring into roots, with bark and a rim of warm light.
    static func trunk(
        in context: inout GraphicsContext, centerX: CGFloat, width: CGFloat, top: CGFloat, base: CGFloat,
        lightX: CGFloat,
        random: inout NoiseSource
    ) {
        let topHalf = width * 0.38
        let half = width * 0.5
        var shape = Path()
        shape.move(to: CGPoint(x: centerX - topHalf, y: top))
        shape.addLine(to: CGPoint(x: centerX + topHalf, y: top))
        shape.addLine(to: CGPoint(x: centerX + half, y: base - width * 0.5))
        shape.addQuadCurve(
            to: CGPoint(x: centerX + half + width * 0.45, y: base),
            control: CGPoint(x: centerX + half, y: base - width * 0.1))
        shape.addLine(to: CGPoint(x: centerX - half - width * 0.45, y: base))
        shape.addQuadCurve(
            to: CGPoint(x: centerX - half, y: base - width * 0.5),
            control: CGPoint(x: centerX - half, y: base - width * 0.1))
        shape.closeSubpath()
        // Shadow on the ground.
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: centerX - width * 1.2, y: base - width * 0.12, width: width * 2.4, height: width * 0.3)),
            with: .color(.black.opacity(0.25)))
        let litFromRight = lightX > centerX
        context.fill(
            shape,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.13, green: 0.08, blue: 0.05), Color(red: 0.28, green: 0.18, blue: 0.11),
                    Color(red: 0.42, green: 0.27, blue: 0.15),
                ]),
                startPoint: CGPoint(x: centerX + (litFromRight ? -half : half), y: 0),
                endPoint: CGPoint(x: centerX + (litFromRight ? half : -half), y: 0)))
        context.drawLayer { bark in
            bark.clip(to: shape)
            for _ in 0..<Int(width / 4) {
                let x = centerX + CGFloat(random.bipolar()) * half
                var line = Path()
                var y = top
                line.move(to: CGPoint(x: x, y: y))
                while y < base {
                    y += 14
                    line.addLine(to: CGPoint(x: x + CGFloat(random.bipolar()) * 1.5, y: y))
                }
                bark.stroke(line, with: .color(.black.opacity(0.25)), lineWidth: 1 + CGFloat(random.unit()) * 1.5)
            }
            // Rim light on the passage side.
            let rimX = centerX + (litFromRight ? half : -half)
            bark.fill(
                Path(
                    CGRect(x: rimX - (litFromRight ? width * 0.12 : 0), y: top, width: width * 0.12, height: base - top)
                ),
                with: .linearGradient(
                    Gradient(colors: [.clear, Color(red: 1, green: 0.78, blue: 0.5).opacity(0.45)]),
                    startPoint: CGPoint(x: rimX - (litFromRight ? width * 0.12 : -width * 0.12), y: 0),
                    endPoint: CGPoint(x: rimX, y: 0)))
        }
    }

    /// Overlapping leaf clusters along an arch: deep at the sides, lifting over the passage, with
    /// lighter leaves where the light catches the underside.
    private static func canopy(in context: inout GraphicsContext, rect: CGRect, random: inout NoiseSource) {
        func archDepth(_ x: CGFloat) -> CGFloat {
            let u = (x - rect.minX) / rect.width
            let distance = abs(u - 0.53) / 0.53
            return rect.height * (0.04 + 0.3 * pow(distance, 1.6))
        }
        let darks = [
            Color(red: 0.1, green: 0.2, blue: 0.1), Color(red: 0.13, green: 0.25, blue: 0.12),
            Color(red: 0.16, green: 0.29, blue: 0.14),
        ]
        // The body of the canopy: everything above the arch, a little inside the leafy edge.
        var body = Path()
        body.move(to: CGPoint(x: rect.minX, y: rect.minY - 1))
        var edgeX = rect.minX
        while edgeX <= rect.maxX + 1 {
            body.addLine(to: CGPoint(x: edgeX, y: rect.minY + archDepth(edgeX) - rect.width * 0.07))
            edgeX += rect.width / 40
        }
        body.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - 1))
        body.closeSubpath()
        context.fill(body, with: .color(darks[0]))
        var x = rect.minX - rect.width * 0.05
        while x < rect.maxX + rect.width * 0.05 {
            let depth = archDepth(x)
            let radius = rect.width * CGFloat(random.value(in: 0.07...0.13))
            let y = rect.minY + depth - radius * CGFloat(random.value(in: 0.2...0.9))
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 1.8)),
                with: .color(darks[Int(random.unit() * 3) % 3]))
            x += radius * 0.9
        }
        // Lit leaves along the lower edge.
        for _ in 0..<70 {
            let x = rect.minX + CGFloat(random.unit()) * rect.width
            let edge = rect.minY + archDepth(x)
            let y = edge - CGFloat(random.unit()) * rect.height * 0.05
            let leaf = rect.width * CGFloat(random.value(in: 0.012...0.03))
            context.fill(
                Path(ellipseIn: CGRect(x: x - leaf, y: y - leaf * 0.6, width: leaf * 2, height: leaf * 1.2)),
                with: .color(Color(red: 0.4, green: 0.55, blue: 0.22).opacity(Double(random.value(in: 0.4...0.9)))))
        }
    }

    /// Stars, a ringed planet, a faint nebula and a distant spiral galaxy.
    private static func space(in context: inout GraphicsContext, rect: CGRect) {
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.02, green: 0.02, blue: 0.08), Color(red: 0.1, green: 0.05, blue: 0.2)]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        // Faint nebula haze: gradients over the whole sky, so they never show an edge.
        for (x, y, color) in [
            (0.75, 0.2, Color(red: 0.45, green: 0.25, blue: 0.7)),
            (0.2, 0.75, Color(red: 0.15, green: 0.35, blue: 0.6)),
        ] as [(CGFloat, CGFloat, Color)] {
            context.fill(
                Path(rect),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(0.22), color.opacity(0.08), .clear]),
                    center: CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y), startRadius: 0,
                    endRadius: rect.width * 0.6))
        }
        spiralGalaxy(
            in: &context, center: CGPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.27),
            size: rect.width * 0.26)
        var random = NoiseSource(seed: 5)
        for _ in 0..<160 {
            let point = CGPoint(
                x: rect.minX + CGFloat(random.unit()) * rect.width, y: rect.minY + CGFloat(random.unit()) * rect.height)
            let star = 0.6 + CGFloat(random.unit()) * 1.8
            context.fill(
                Path(ellipseIn: CGRect(x: point.x, y: point.y, width: star, height: star)),
                with: .color(.white.opacity(0.4 + 0.6 * Double(random.unit()))))
        }
        let planet = rect.width * 0.36
        let center = CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.62)
        let ring = CGRect(
            x: center.x - planet * 1.05, y: center.y - planet * 0.22, width: planet * 2.1, height: planet * 0.44)
        // Back half of the ring, planet, front half of the ring.
        context.drawLayer { layer in
            layer.clip(
                to: Path(
                    CGRect(x: ring.minX - 10, y: ring.minY - 10, width: ring.width + 20, height: ring.height / 2 + 10)))
            layer.stroke(
                Path(ellipseIn: ring), with: .color(Color(red: 0.9, green: 0.8, blue: 0.6).opacity(0.8)), lineWidth: 5)
        }
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - planet / 2, y: center.y - planet / 2, width: planet, height: planet)),
            with: .radialGradient(
                Gradient(colors: [
                    Color(red: 0.98, green: 0.72, blue: 0.45), Color(red: 0.65, green: 0.3, blue: 0.25),
                    Color(red: 0.2, green: 0.08, blue: 0.12),
                ]),
                center: CGPoint(x: center.x - planet * 0.2, y: center.y - planet * 0.2), startRadius: 0,
                endRadius: planet * 0.75))
        context.drawLayer { layer in
            layer.clip(
                to: Path(CGRect(x: ring.minX - 10, y: ring.midY, width: ring.width + 20, height: ring.height / 2 + 10)))
            layer.stroke(
                Path(ellipseIn: ring), with: .color(Color(red: 0.9, green: 0.8, blue: 0.6).opacity(0.9)), lineWidth: 5)
        }
    }

    /// A small spiral galaxy far away: a bright core and two arms of faint stars, tilted.
    private static func spiralGalaxy(in context: inout GraphicsContext, center: CGPoint, size: CGFloat) {
        context.drawLayer { layer in
            layer.translateBy(x: center.x, y: center.y)
            layer.rotate(by: .degrees(-28))
            layer.scaleBy(x: 1, y: 0.42)
            layer.fill(
                Path(ellipseIn: CGRect(x: -size, y: -size, width: size * 2, height: size * 2)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 0.75, green: 0.7, blue: 1).opacity(0.22), .clear]), center: .zero,
                    startRadius: 0, endRadius: size))
            var random = NoiseSource(seed: 77)
            for arm in 0..<2 {
                for step in 0..<110 {
                    let t = Double(step) / 110
                    let angle = Double(arm) * .pi + t * 3.6 * .pi / 2 + Double(random.bipolar()) * 0.25
                    let radius = size * CGFloat(0.08 + 0.85 * t) * CGFloat(1 + 0.12 * random.bipolar())
                    let star = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                    let dot = 1 + CGFloat(random.unit()) * 1.6
                    let tint =
                        random.unit() < 0.3
                        ? Color(red: 1, green: 0.8, blue: 0.9) : Color(red: 0.8, green: 0.88, blue: 1)
                    layer.fill(
                        Path(ellipseIn: CGRect(x: star.x - dot / 2, y: star.y - dot / 2, width: dot, height: dot)),
                        with: .color(tint.opacity(0.75 * (1 - t * 0.7))))
                }
            }
            layer.fill(
                Path(ellipseIn: CGRect(x: -size * 0.25, y: -size * 0.25, width: size * 0.5, height: size * 0.5)),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.95), Color(red: 1, green: 0.9, blue: 0.75).opacity(0.5), .clear]
                    ),
                    center: .zero, startRadius: 0, endRadius: size * 0.25))
        }
    }

    /// An old brick wall: shaded, textured bricks with chipped corners in recessed mortar, grime
    /// at the bottom, ivy climbing up from a corner and moss in the lower joints.
    private static func brickWall(in context: inout GraphicsContext, rect: CGRect) {
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

    private static func pine(
        in context: inout GraphicsContext, base: CGPoint, width: CGFloat, height: CGFloat, color: Color
    ) {
        context.fill(
            Path(
                CGRect(x: base.x - width * 0.05, y: base.y - height * 0.12, width: width * 0.1, height: height * 0.12)),
            with: .color(Color(red: 0.25, green: 0.17, blue: 0.1)))
        for tier in 0..<3 {
            let tierBottom = base.y - height * (0.03 + 0.25 * CGFloat(tier))
            let tierWidth = width * (1 - 0.25 * CGFloat(tier))
            var triangle = Path()
            triangle.move(to: CGPoint(x: base.x - tierWidth / 2, y: tierBottom))
            triangle.addLine(to: CGPoint(x: base.x + tierWidth / 2, y: tierBottom))
            triangle.addLine(to: CGPoint(x: base.x, y: tierBottom - height * 0.45))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(color))
        }
    }

    /// A warm little room: lamp, picture, floorboards, rug.
    private static func livingRoom(in context: inout GraphicsContext, rect: CGRect) {
        let horizon = rect.minY + rect.height * 0.66

        // Wall.
        let wall = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: horizon - rect.minY)
        context.fill(
            Path(wall),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.97, green: 0.89, blue: 0.72), Color(red: 0.88, green: 0.74, blue: 0.56)]
                ),
                startPoint: CGPoint(x: wall.midX, y: wall.minY), endPoint: CGPoint(x: wall.midX, y: wall.maxY)))

        // Floor: planks running away from you.
        let floor = CGRect(x: rect.minX, y: horizon, width: rect.width, height: rect.maxY - horizon)
        context.fill(
            Path(floor),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.45, green: 0.28, blue: 0.16), Color(red: 0.62, green: 0.40, blue: 0.23)]
                ),
                startPoint: CGPoint(x: floor.midX, y: floor.minY), endPoint: CGPoint(x: floor.midX, y: floor.maxY)))
        let vanishing = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.3)
        for index in -6...6 {
            let bottomX = rect.midX + CGFloat(index) * rect.width * 0.16
            let t = (horizon - vanishing.y) / (rect.maxY - vanishing.y)
            var seam = Path()
            seam.move(to: CGPoint(x: vanishing.x + (bottomX - vanishing.x) * t, y: horizon))
            seam.addLine(to: CGPoint(x: bottomX, y: rect.maxY))
            context.stroke(seam, with: .color(.black.opacity(0.18)), lineWidth: 1)
        }

        // Skirting board.
        context.fill(
            Path(
                CGRect(x: rect.minX, y: horizon - rect.height * 0.025, width: rect.width, height: rect.height * 0.025)),
            with: .color(Color(red: 0.95, green: 0.93, blue: 0.88)))

        // A small cabinet against the back wall, with a vase of flowers on top.
        cabinet(in: &context, rect: rect, floor: horizon)

        // Rug.
        let rug = CGRect(
            x: rect.midX - rect.width * 0.36, y: horizon + floor.height * 0.3, width: rect.width * 0.72,
            height: floor.height * 0.5)
        context.fill(Path(ellipseIn: rug), with: .color(Color(red: 0.58, green: 0.14, blue: 0.12)))
        context.stroke(
            Path(ellipseIn: rug.insetBy(dx: rug.width * 0.07, dy: rug.height * 0.14)),
            with: .color(Color(red: 0.93, green: 0.74, blue: 0.36).opacity(0.8)), lineWidth: 2)

        // Picture: a frame with hills and a sun.
        let pictureWidth = rect.width * 0.42
        let picture = CGRect(
            x: rect.midX - pictureWidth / 2, y: rect.minY + rect.height * 0.24, width: pictureWidth,
            height: pictureWidth * 0.72)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: 3))
            layer.fill(Path(picture), with: .color(Color(red: 0.32, green: 0.2, blue: 0.12)))
        }
        let canvas = picture.insetBy(dx: pictureWidth * 0.07, dy: pictureWidth * 0.07)
        context.fill(
            Path(canvas),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.55, green: 0.75, blue: 0.92), Color(red: 0.93, green: 0.86, blue: 0.7)]),
                startPoint: CGPoint(x: canvas.midX, y: canvas.minY), endPoint: CGPoint(x: canvas.midX, y: canvas.maxY)))
        let sun = canvas.width * 0.16
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: canvas.minX + canvas.width * 0.65, y: canvas.minY + canvas.height * 0.18, width: sun,
                    height: sun)), with: .color(Color(red: 1, green: 0.85, blue: 0.4)))
        var hills = Path()
        hills.move(to: CGPoint(x: canvas.minX, y: canvas.maxY))
        hills.addLine(to: CGPoint(x: canvas.minX, y: canvas.minY + canvas.height * 0.62))
        hills.addQuadCurve(
            to: CGPoint(x: canvas.midX, y: canvas.minY + canvas.height * 0.7),
            control: CGPoint(x: canvas.minX + canvas.width * 0.25, y: canvas.minY + canvas.height * 0.4))
        hills.addQuadCurve(
            to: CGPoint(x: canvas.maxX, y: canvas.minY + canvas.height * 0.58),
            control: CGPoint(x: canvas.minX + canvas.width * 0.8, y: canvas.minY + canvas.height * 0.45))
        hills.addLine(to: CGPoint(x: canvas.maxX, y: canvas.maxY))
        hills.closeSubpath()
        context.fill(hills, with: .color(Color(red: 0.36, green: 0.58, blue: 0.32)))

        // Pendant lamp and its glow.
        let lamp = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.1)
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: lamp.x - rect.width, y: lamp.y - rect.width, width: rect.width * 2, height: rect.width * 2)),
            with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.93, blue: 0.7).opacity(0.75), .clear]), center: lamp,
                startRadius: 0, endRadius: rect.width))
        // The lamp itself hangs in the animated layer (`SceneLife`), where it sways.
    }
}

/// A small picture of a scene, for the settings.
struct InsideSceneArt: View {
    let scene: InsideScene

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            ScenePainter.paint(scene, in: &context, rect: rect)
            SceneLife.paint(scene, in: &context, rect: rect, time: 0)
        }
    }
}

#Preview {
    HStack {
        ForEach(InsideScene.allCases) { scene in
            InsideSceneArt(scene: scene).frame(width: 120, height: 200)
        }
    }
}

/// Where things are in the forest, shared by the still scene and its animated life (the deer
/// pops up behind one of these bushes, so both layers must agree on where they are).
enum ForestLayout {
    struct Bush {
        let center: CGPoint
        let size: CGFloat
        let seed: UInt32
    }

    /// The bright opening the path leads into.
    static func passage(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * 0.55, y: rect.minY + rect.height * 0.6)
    }

    /// A point on the path's center line: `t` = 0 at the bottom edge, 1 at the passage.
    static func pathPoint(at t: CGFloat, in rect: CGRect) -> CGPoint {
        let end = passage(in: rect)
        let start = CGPoint(x: rect.minX + rect.width * 0.4, y: rect.maxY)
        // Perspective: the far part of the path crowds up near the horizon.
        let depth = 1 - pow(1 - t, 1.8)
        let wind = sin(t * .pi * 2.4) * rect.width * 0.17 * (1 - t)
        return CGPoint(x: start.x + (end.x - start.x) * t + wind, y: start.y + (end.y - start.y) * depth)
    }

    static func pathWidth(at t: CGFloat, in rect: CGRect) -> CGFloat {
        rect.width * (0.62 * pow(1 - t, 1.4) + 0.012)
    }

    /// The path as a shape, with slightly uneven (trodden) edges.
    static func pathOutline(in rect: CGRect) -> Path {
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        let steps = 48
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let center = pathPoint(at: t, in: rect)
            let half = pathWidth(at: t, in: rect) / 2
            let wobble = sin(t * 37) * half * 0.06
            left.append(CGPoint(x: center.x - half + wobble, y: center.y))
            right.append(CGPoint(x: center.x + half - wobble * 0.7, y: center.y))
        }
        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }

    static func bushes(in rect: CGRect) -> [Bush] {
        // (position along the path, side, size), all on the left: the first is the deer's bush.
        let spots: [(t: CGFloat, side: CGFloat, size: CGFloat)] = [
            (0.5, -1, 0.3), (0.66, -1, 0.14),
        ]
        return spots.enumerated().map { index, spot in
            let center = pathPoint(at: spot.t, in: rect)
            let size = rect.width * spot.size
            let x = center.x + spot.side * (pathWidth(at: spot.t, in: rect) / 2 + size * 0.38)
            return Bush(center: CGPoint(x: x, y: center.y), size: size, seed: UInt32(index + 3))
        }
    }

    /// The foreground trunks on the right. Seeded on their own, so the animated layer can redraw
    /// them exactly (a running deer passes behind them).
    static func paintTrunks(in context: inout GraphicsContext, rect: CGRect) {
        var random = NoiseSource(seed: 81)
        let sun = passage(in: rect)
        for (x, width, base) in [(0.86, 0.1, 0.88), (1.0, 0.15, 1.0)] as [(CGFloat, CGFloat, CGFloat)] {
            ScenePainter.trunk(
                in: &context, centerX: rect.minX + rect.width * x, width: rect.width * width,
                top: rect.minY, base: rect.minY + rect.height * base, lightX: sun.x, random: &random)
        }
    }

    /// The bush the deer hides behind.
    static func deerBush(in rect: CGRect) -> Bush { bushes(in: rect)[0] }

    /// `shadow` is off when repainting a bush over the still scene, which already has its shadow
    /// (painting it twice would darken it).
    static func paintBush(_ bush: Bush, in context: inout GraphicsContext, shadow: Bool = true) {
        var random = NoiseSource(seed: bush.seed)
        // Shadow on the ground, then dark inner leaves, then lit leaves on top.
        if shadow {
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: bush.center.x - bush.size * 0.55, y: bush.center.y - bush.size * 0.06,
                        width: bush.size * 1.1, height: bush.size * 0.18)),
                with: .color(.black.opacity(0.25)))
        }
        // A low clump filling out the bottom-left corner, so the leaves cover the shadow there.
        let clump = bush.size * 0.22
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: bush.center.x - bush.size * 0.34 - clump, y: bush.center.y - bush.size * 0.02 - clump,
                    width: clump * 2, height: clump * 1.8)),
            with: .color(Color(red: 0.11, green: 0.24, blue: 0.11)))
        let layers: [(Color, Int, ClosedRange<Float>, CGFloat)] = [
            (Color(red: 0.11, green: 0.24, blue: 0.11), 9, 0.2...0.3, 0),
            (Color(red: 0.18, green: 0.34, blue: 0.15), 8, 0.14...0.22, -0.05),
            (Color(red: 0.32, green: 0.5, blue: 0.22), 7, 0.07...0.12, -0.12),
        ]
        for (color, count, radii, lift) in layers {
            for _ in 0..<count {
                let dx = CGFloat(random.bipolar()) * bush.size * 0.42
                let dy = -CGFloat(random.unit()) * bush.size * 0.4 + lift * bush.size
                let radius = bush.size * CGFloat(random.value(in: radii))
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: bush.center.x + dx - radius, y: bush.center.y + dy - radius, width: radius * 2,
                            height: radius * 1.8)),
                    with: .color(color))
            }
        }
    }
}
