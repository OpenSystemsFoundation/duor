import SwiftUI

extension ScenePainter {
    /// Sky, sea, a sun, and sand with ripples, shells and a starfish.
    static func beach(in context: inout GraphicsContext, rect: CGRect) {
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
}

extension SceneLife {
    static func beach(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval, catLovers: Bool) {
        let horizon = rect.minY + rect.height * 0.5
        let shore = rect.minY + rect.height * 0.66
        // Clouds of different shapes, drifting slowly at their own speeds.
        for (index, (heightFraction, size, speed)) in [
            (0.08, 0.3, 4.0), (0.2, 0.2, 6.5), (0.33, 0.16, 3.0), (0.14, 0.24, 5.2),
        ].enumerated() {
            let width = rect.width * CGFloat(size)
            let travel = rect.width + width * 2
            let offset = CGFloat((time * speed + Double(index) * 137).truncatingRemainder(dividingBy: Double(travel)))
            let center = CGPoint(x: rect.minX - width + offset, y: rect.minY + rect.height * CGFloat(heightFraction))
            cloud(in: &context, center: center, width: width, seed: UInt32(index + 1))
        }
        // A sailboat drifting along the horizon.
        if let visit = visit(time: time, period: 24, duration: 20, salt: 4) {
            let size = rect.width * 0.14
            let x = visit.x(in: rect, margin: size)
            critter(in: &context, at: CGPoint(x: x, y: horizon + 2 + sin(time * 2) * 1.5), facing: visit.facing) {
                sailboat(in: &$0, size: size, time: time)
            }
        }
        // Rolling waves.
        for index in 0..<4 {
            let y = horizon + (shore - horizon) * (0.2 + 0.2 * CGFloat(index))
            let offset = CGFloat((time * (10 + Double(index) * 4)).truncatingRemainder(dividingBy: 24))
            var wave = Path()
            var x = rect.minX - 24 + offset
            wave.move(to: CGPoint(x: x, y: y))
            while x < rect.maxX {
                wave.addQuadCurve(to: CGPoint(x: x + 24, y: y), control: CGPoint(x: x + 12, y: y - 4))
                x += 24
            }
            context.stroke(wave, with: .color(.white.opacity(0.35)), lineWidth: 1.2)
        }
        // The foam line breathes in and out.
        let reach = CGFloat(4 + 4 * sin(time * 0.9))
        var foam = Path()
        foam.move(to: CGPoint(x: rect.minX, y: shore + reach * 0.5))
        foam.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: shore + reach), control: CGPoint(x: rect.midX, y: shore + 10 + reach))
        context.stroke(foam, with: .color(.white.opacity(0.7)), lineWidth: 3)
        // A seagull overhead.
        if let visit = visit(time: time, period: 8, duration: 4, salt: 5) {
            let size = rect.width * 0.13
            let x = visit.x(in: rect, margin: size)
            let y = rect.minY + rect.height * (0.08 + 0.2 * visit.lane) + sin(time * 2.5) * rect.height * 0.015
            critter(in: &context, at: CGPoint(x: x, y: y), facing: visit.facing) {
                seagull(in: &$0, size: size, time: time)
            }
        }
        // A dolphin leaps out of the sea and back in.
        if let visit = visit(time: time, period: 15, duration: 2, salt: 16) {
            let water = horizon + (shore - horizon) * (0.35 + 0.4 * visit.lane)
            let start = rect.minX + rect.width * (visit.facing > 0 ? 0.15 : 0.85)
            dolphin(
                in: &context, rect: rect, water: water, start: start, progress: visit.progress, facing: visit.facing,
                size: rect.width * 0.2)
        }
        // A shark fin cruising along, not in any hurry.
        if let visit = visit(time: time, period: 21, duration: 9, salt: 17) {
            let size = rect.width * 0.08
            let water = horizon + (shore - horizon) * (0.3 + 0.5 * visit.lane)
            let x = visit.x(in: rect, margin: size * 2)
            sharkFin(in: &context, at: CGPoint(x: x, y: water + sin(time * 2) * 1.2), size: size, facing: visit.facing)
        }
        // A cat comes to sunbathe.
        if catLovers {
            catOnTheBeach(in: &context, rect: rect, time: time)
        }
        // A crab scuttles sideways across the sand.
        if let visit = visit(time: time, period: 14, duration: 5, salt: 6) {
            let size = rect.width * 0.12
            let x = visit.x(in: rect, margin: size) + sin(time * 30) * 1.5
            critter(in: &context, at: CGPoint(x: x, y: rect.minY + rect.height * (0.86 + 0.08 * visit.lane)), facing: 1)
            {
                crab(in: &$0, size: size, time: time)
            }
        }
    }

    /// A puffy cloud built from a seeded handful of puffs, with a soft grey underside.
    private static func cloud(in context: inout GraphicsContext, center: CGPoint, width: CGFloat, seed: UInt32) {
        var random = NoiseSource(seed: seed &* 31)
        let puffs = 3 + Int(random.nextUInt() % 4)
        var shape = Path()
        for index in 0..<puffs {
            let t = CGFloat(index) / CGFloat(max(puffs - 1, 1)) - 0.5
            let radius = width * CGFloat(random.value(in: 0.16...0.3)) * (1 - abs(t) * 0.8)
            let point = CGPoint(x: center.x + t * width * 0.75, y: center.y - CGFloat(random.unit()) * width * 0.08)
            shape.addEllipse(
                in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 1.7))
        }
        shape.addRoundedRect(
            in: CGRect(
                x: center.x - width * 0.42, y: center.y - width * 0.04, width: width * 0.84, height: width * 0.16),
            cornerSize: CGSize(width: width * 0.08, height: width * 0.08))
        context.fill(shape, with: .color(.white.opacity(0.92)))
        context.drawLayer { shade in
            shade.clip(to: shape)
            shade.fill(
                Path(CGRect(x: center.x - width, y: center.y, width: width * 2, height: width * 0.3)),
                with: .linearGradient(
                    Gradient(colors: [.clear, Color(red: 0.75, green: 0.8, blue: 0.88).opacity(0.6)]),
                    startPoint: CGPoint(x: 0, y: center.y), endPoint: CGPoint(x: 0, y: center.y + width * 0.14)))
        }
    }

    /// A dolphin leaping in an arc, only drawn above the water, with splashes going in and out.
    private static func dolphin(
        in context: inout GraphicsContext, rect: CGRect, water: CGFloat, start: CGFloat, progress: Double,
        facing: CGFloat,
        size: CGFloat
    ) {
        let travel = rect.width * 0.32 * facing
        let height = rect.height * 0.12
        let p = CGFloat(progress)
        let point = CGPoint(x: start + travel * p, y: water + size * 0.12 - sin(p * .pi) * height)
        let slope = atan2(-cos(p * .pi) * .pi * height, travel)
        context.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: water - rect.minY)))
            layer.translateBy(x: point.x, y: point.y)
            layer.rotate(by: .radians(Double(slope)))
            if facing < 0 { layer.scaleBy(x: 1, y: -1) }
            let length = size
            let back = Color(red: 0.33, green: 0.45, blue: 0.58)
            // The spine arches up; the body is thick in the middle and tapers to a slim tail
            // stock and a short beak.
            func spine(_ u: CGFloat) -> CGPoint {
                CGPoint(x: length * (u - 0.5), y: -length * 0.32 * u * (1 - u))
            }
            func normal(_ u: CGFloat) -> CGPoint {
                let a = spine(max(u - 0.01, 0))
                let b = spine(min(u + 0.01, 1))
                let dx = b.x - a.x
                let dy = b.y - a.y
                let norm = max(sqrt(dx * dx + dy * dy), 0.0001)
                return CGPoint(x: -dy / norm, y: dx / norm)
            }
            func thickness(_ u: CGFloat) -> CGFloat {
                let body = sin(.pi * pow(u, 0.75)) * length * 0.15
                return u > 0.9 ? body * 0.55 : body
            }
            var upper: [CGPoint] = []
            var lower: [CGPoint] = []
            for step in 0...40 {
                let u = CGFloat(step) / 40
                let center = spine(u)
                let n = normal(u)
                let half = thickness(u)
                upper.append(CGPoint(x: center.x - n.x * half * 0.55, y: center.y - n.y * half * 0.55))
                lower.append(CGPoint(x: center.x + n.x * half * 0.45, y: center.y + n.y * half * 0.45))
            }
            var body = Path()
            body.addLines(upper + lower.reversed())
            body.closeSubpath()
            layer.fill(
                body,
                with: .linearGradient(
                    Gradient(colors: [back, Color(red: 0.86, green: 0.9, blue: 0.94)]),
                    startPoint: CGPoint(x: 0, y: -length * 0.14), endPoint: CGPoint(x: 0, y: length * 0.02)))
            // Dorsal fin, swept back, on the highest point of the arch.
            let finBase = spine(0.42)
            let finNormal = normal(0.42)
            let finTop = CGPoint(
                x: finBase.x - finNormal.x * length * 0.2 - length * 0.08, y: finBase.y - finNormal.y * length * 0.2)
            var fin = Path()
            fin.move(to: CGPoint(x: finBase.x + length * 0.07, y: finBase.y - thickness(0.42) * 0.45))
            fin.addQuadCurve(to: finTop, control: CGPoint(x: finBase.x + length * 0.02, y: finTop.y + length * 0.02))
            fin.addQuadCurve(
                to: CGPoint(x: finBase.x - length * 0.06, y: finBase.y - thickness(0.42) * 0.4),
                control: CGPoint(x: finTop.x + length * 0.03, y: finBase.y - length * 0.08))
            fin.closeSubpath()
            layer.fill(fin, with: .color(back))
            // Pectoral flipper.
            let flipperBase = spine(0.66)
            var flipper = Path()
            flipper.move(to: CGPoint(x: flipperBase.x + length * 0.03, y: flipperBase.y + thickness(0.66) * 0.2))
            flipper.addQuadCurve(
                to: CGPoint(x: flipperBase.x - length * 0.07, y: flipperBase.y + length * 0.1),
                control: CGPoint(x: flipperBase.x, y: flipperBase.y + length * 0.08))
            flipper.addLine(to: CGPoint(x: flipperBase.x - length * 0.03, y: flipperBase.y + thickness(0.66) * 0.2))
            flipper.closeSubpath()
            layer.fill(flipper, with: .color(back))
            // Tail flukes, angled along the tail's direction.
            let tailEnd = spine(0)
            let tailNormal = normal(0.02)
            var flukes = Path()
            flukes.move(to: CGPoint(x: tailEnd.x + length * 0.03, y: tailEnd.y))
            for side in [-1.0, 1.0] as [CGFloat] {
                flukes.addQuadCurve(
                    to: CGPoint(
                        x: tailEnd.x - length * 0.12 + tailNormal.x * side * length * 0.11,
                        y: tailEnd.y + tailNormal.y * side * length * 0.11),
                    control: CGPoint(x: tailEnd.x - length * 0.02, y: tailEnd.y + tailNormal.y * side * length * 0.04))
                flukes.addLine(to: CGPoint(x: tailEnd.x - length * 0.05, y: tailEnd.y))
            }
            flukes.closeSubpath()
            layer.fill(flukes, with: .color(back))
            // Eye, just behind the melon.
            let eye = spine(0.82)
            layer.fill(
                Path(
                    ellipseIn: CGRect(
                        x: eye.x - length * 0.017, y: eye.y - length * 0.035, width: length * 0.034,
                        height: length * 0.034)),
                with: .color(Color(white: 0.1)))
        }
        // Splashes where it breaks the surface.
        for (center, amount) in [(start, max(0, 1 - p / 0.2)), (start + travel, max(0, (p - 0.8) / 0.2))]
        where amount > 0 {
            for index in 0..<7 {
                let angle = Double(index) / 6 * .pi
                let reach = size * 0.25 * amount
                let drop = CGPoint(x: center + cos(angle) * reach, y: water - sin(angle) * reach * 0.8)
                let radius = 2 + 2 * amount
                context.fill(
                    Path(
                        ellipseIn: CGRect(x: drop.x - radius, y: drop.y - radius, width: radius * 2, height: radius * 2)
                    ),
                    with: .color(.white.opacity(0.9 * Double(amount))))
            }
        }
    }

    /// A shark fin slicing along the surface, leaving a little wake.
    private static func sharkFin(in context: inout GraphicsContext, at point: CGPoint, size: CGFloat, facing: CGFloat) {
        // A dorsal fin sweeps back: a curved leading edge rises from the front to a tip that
        // points backward, then a short, concave trailing edge drops to the water.
        var fin = Path()
        fin.move(to: CGPoint(x: point.x + facing * size * 0.45, y: point.y))
        fin.addQuadCurve(
            to: CGPoint(x: point.x - facing * size * 0.3, y: point.y - size),
            control: CGPoint(x: point.x + facing * size * 0.25, y: point.y - size * 0.75))
        fin.addQuadCurve(
            to: CGPoint(x: point.x - facing * size * 0.08, y: point.y),
            control: CGPoint(x: point.x - facing * size * 0.05, y: point.y - size * 0.55))
        fin.closeSubpath()
        context.fill(fin, with: .color(Color(red: 0.3, green: 0.34, blue: 0.4)))
        for offset in [0.0, 0.5] as [CGFloat] {
            var wake = Path()
            wake.move(to: CGPoint(x: point.x - facing * size * (0.6 + offset), y: point.y + 1 + offset * 2))
            wake.addLine(to: CGPoint(x: point.x - facing * size * (1.5 + offset * 1.5), y: point.y + 3 + offset * 4))
            context.stroke(wake, with: .color(.white.opacity(0.6 - Double(offset) * 0.6)), lineWidth: 1.5)
        }
        var foam = Path()
        foam.move(to: CGPoint(x: point.x - facing * size * 0.55, y: point.y + 1))
        foam.addLine(to: CGPoint(x: point.x + facing * size * 0.45, y: point.y + 1))
        context.stroke(foam, with: .color(.white.opacity(0.8)), lineWidth: 2)
    }

    private static func seagull(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        let flap = CGFloat(sin(time * 7)) * size * 0.18
        var wings = Path()
        wings.move(to: CGPoint(x: -size * 0.5, y: -flap))
        wings.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -size * 0.25, y: -size * 0.2 - flap))
        wings.addQuadCurve(
            to: CGPoint(x: size * 0.5, y: -flap), control: CGPoint(x: size * 0.25, y: -size * 0.2 - flap))
        context.stroke(wings, with: .color(.white), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.08, y: -size * 0.04, width: size * 0.2, height: size * 0.09)),
            with: .color(.white))
        context.fill(
            Path(ellipseIn: CGRect(x: size * 0.1, y: -size * 0.02, width: size * 0.06, height: size * 0.03)),
            with: .color(Color(red: 1, green: 0.7, blue: 0.2)))
    }

    private static func sailboat(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        context.drawLayer { boat in
            boat.rotate(by: .degrees(2 * sin(time * 1.7)))
            var hull = Path()
            hull.move(to: CGPoint(x: -size * 0.5, y: -size * 0.12))
            hull.addLine(to: CGPoint(x: size * 0.5, y: -size * 0.12))
            hull.addLine(to: CGPoint(x: size * 0.35, y: 0))
            hull.addLine(to: CGPoint(x: -size * 0.35, y: 0))
            hull.closeSubpath()
            boat.fill(hull, with: .color(Color(red: 0.55, green: 0.3, blue: 0.18)))
            var mast = Path()
            mast.move(to: CGPoint(x: 0, y: -size * 0.12))
            mast.addLine(to: CGPoint(x: 0, y: -size * 0.85))
            boat.stroke(mast, with: .color(Color(white: 0.3)), lineWidth: 1.5)
            var sail = Path()
            sail.move(to: CGPoint(x: size * 0.03, y: -size * 0.82))
            sail.addLine(to: CGPoint(x: size * 0.38, y: -size * 0.18))
            sail.addLine(to: CGPoint(x: size * 0.03, y: -size * 0.18))
            sail.closeSubpath()
            boat.fill(sail, with: .color(.white))
            var jib = Path()
            jib.move(to: CGPoint(x: -size * 0.03, y: -size * 0.7))
            jib.addLine(to: CGPoint(x: -size * 0.3, y: -size * 0.18))
            jib.addLine(to: CGPoint(x: -size * 0.03, y: -size * 0.18))
            jib.closeSubpath()
            boat.fill(jib, with: .color(Color(red: 0.9, green: 0.3, blue: 0.25)))
        }
    }

    private static func crab(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        let red = Color(red: 0.88, green: 0.3, blue: 0.2)
        for side in [-1.0, 1.0] as [CGFloat] {
            for leg in 0..<3 {
                let wiggle = CGFloat(sin(time * 25 + Double(leg) + Double(side))) * size * 0.04
                var line = Path()
                line.move(to: CGPoint(x: side * size * 0.15, y: -size * 0.15))
                line.addLine(to: CGPoint(x: side * size * (0.35 + 0.05 * CGFloat(leg)), y: wiggle))
                context.stroke(line, with: .color(red), lineWidth: size * 0.04)
            }
            let claw = CGRect(
                x: side * size * 0.4 - size * 0.08, y: -size * 0.45, width: size * 0.16, height: size * 0.14)
            context.fill(Path(ellipseIn: claw), with: .color(red))
        }
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.28, y: -size * 0.32, width: size * 0.56, height: size * 0.28)),
            with: .color(red))
        for eye in [-0.09, 0.09] as [CGFloat] {
            var stalk = Path()
            stalk.move(to: CGPoint(x: eye * size, y: -size * 0.3))
            stalk.addLine(to: CGPoint(x: eye * size, y: -size * 0.42))
            context.stroke(stalk, with: .color(red), lineWidth: 2)
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: eye * size - size * 0.035, y: -size * 0.48, width: size * 0.07, height: size * 0.07)),
                with: .color(.white))
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: eye * size - size * 0.015, y: -size * 0.46, width: size * 0.03, height: size * 0.03)),
                with: .color(.black))
        }
    }

    // MARK: Cat

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

    /// Flat on its back on the sand, paws in the air, eyes shut, now and then a big stretch.
    static func sunbathingCat(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
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
}
