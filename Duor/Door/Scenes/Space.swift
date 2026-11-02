import SwiftUI

extension ScenePainter {
    /// Stars, a ringed planet, a faint nebula and a distant spiral galaxy.
    static func space(in context: inout GraphicsContext, rect: CGRect) {
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
}

extension SceneLife {
    static func space(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval, catLovers: Bool) {
        // Twinkling stars.
        var random = NoiseSource(seed: 99)
        for _ in 0..<26 {
            let point = CGPoint(
                x: rect.minX + CGFloat(random.unit()) * rect.width, y: rect.minY + CGFloat(random.unit()) * rect.height)
            let speed = 1 + Double(random.unit()) * 2.5
            let glow = 0.5 + 0.5 * sin(time * speed + Double(random.unit()) * 6)
            let size = 1.5 + CGFloat(glow) * 2.5
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)),
                with: .color(.white.opacity(0.3 + 0.7 * glow)))
        }
        // A shooting star now and then.
        if let visit = visit(time: time, period: 6, duration: 0.9, salt: 9) {
            let start = CGPoint(x: rect.minX + rect.width * (0.2 + 0.6 * visit.lane), y: rect.minY + rect.height * 0.05)
            let travel = CGFloat(visit.progress) * rect.width * 0.6
            let head = CGPoint(x: start.x + travel * visit.facing, y: start.y + travel * 0.5)
            let tail = CGPoint(x: head.x - rect.width * 0.18 * visit.facing, y: head.y - rect.width * 0.09)
            var streak = Path()
            streak.move(to: tail)
            streak.addLine(to: head)
            context.stroke(
                streak,
                with: .linearGradient(Gradient(colors: [.clear, .white]), startPoint: tail, endPoint: head),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        // A UFO zips past.
        if let visit = visit(time: time, period: 15, duration: 5, salt: 10) {
            let size = rect.width * 0.26
            let x = visit.x(in: rect, margin: size)
            let y = rect.minY + rect.height * (0.15 + 0.25 * visit.lane) + sin(time * 3) * rect.height * 0.02
            critter(in: &context, at: CGPoint(x: x, y: y), facing: visit.facing) {
                ufo(in: &$0, size: size, time: time)
            }
        }
        // An astronaut drifts by, slowly tumbling.
        if let visit = visit(time: time, period: 26, duration: 16, salt: 11) {
            let size = rect.width * 0.24
            let x = visit.x(in: rect, margin: size)
            let y = rect.minY + rect.height * (0.7 + 0.1 * visit.lane) - CGFloat(visit.progress) * rect.height * 0.2
            context.drawLayer { layer in
                layer.translateBy(x: x, y: y)
                layer.rotate(by: .radians(time * 0.4 * Double(visit.facing)))
                astronaut(in: &layer, size: size)
            }
        }
        // A cat in a space helmet floats by.
        if catLovers {
            catInSpace(in: &context, rect: rect, time: time)
        }
    }

    private static func ufo(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.18, y: -size * 0.28, width: size * 0.36, height: size * 0.26)),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.6, green: 0.95, blue: 1).opacity(0.9),
                    Color(red: 0.3, green: 0.6, blue: 0.8).opacity(0.8),
                ]),
                startPoint: CGPoint(x: 0, y: -size * 0.28), endPoint: CGPoint(x: 0, y: -size * 0.1)))
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.5, y: -size * 0.16, width: size, height: size * 0.2)),
            with: .linearGradient(
                Gradient(colors: [Color(white: 0.85), Color(white: 0.45)]), startPoint: CGPoint(x: 0, y: -size * 0.16),
                endPoint: CGPoint(x: 0, y: size * 0.04)))
        let colors: [Color] = [.red, .yellow, .green, .cyan, .pink]
        for index in 0..<5 {
            let x = size * (-0.32 + 0.16 * CGFloat(index))
            let on = Int(time * 6 + Double(index)) % 3 == 0
            context.fill(
                Path(ellipseIn: CGRect(x: x - size * 0.025, y: -size * 0.08, width: size * 0.05, height: size * 0.05)),
                with: .color(colors[index].opacity(on ? 1 : 0.35)))
        }
    }

    private static func astronaut(in context: inout GraphicsContext, size: CGFloat) {
        let suit = Color(white: 0.95)
        context.fill(
            Path(
                roundedRect: CGRect(x: -size * 0.24, y: -size * 0.2, width: size * 0.12, height: size * 0.34),
                cornerRadius: 4), with: .color(Color(white: 0.75)))
        for (x, y, w, h) in [
            (-0.2, 0.12, 0.12, 0.26), (0.06, 0.12, 0.12, 0.26), (-0.3, -0.12, 0.1, 0.24), (0.16, -0.16, 0.1, 0.24),
        ] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            context.fill(
                Path(
                    roundedRect: CGRect(x: x * size, y: y * size, width: w * size, height: h * size),
                    cornerRadius: size * 0.05), with: .color(suit))
        }
        context.fill(
            Path(
                roundedRect: CGRect(x: -size * 0.18, y: -size * 0.2, width: size * 0.36, height: size * 0.36),
                cornerRadius: size * 0.1), with: .color(suit))
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.17, y: -size * 0.5, width: size * 0.34, height: size * 0.32)),
            with: .color(suit))
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.12, y: -size * 0.45, width: size * 0.24, height: size * 0.2)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.25, green: 0.4, blue: 0.85), Color(red: 0.05, green: 0.08, blue: 0.25)]),
                startPoint: CGPoint(x: -size * 0.1, y: -size * 0.45), endPoint: CGPoint(x: size * 0.1, y: -size * 0.25))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.08, y: -size * 0.42, width: size * 0.06, height: size * 0.04)),
            with: .color(.white.opacity(0.7)))
    }

    // MARK: Cat

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
}
