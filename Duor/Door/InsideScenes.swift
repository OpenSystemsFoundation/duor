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

    /// Sky, sea, sand, a sun and a striped umbrella.
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
        cloud(
            in: &context, center: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.14),
            size: rect.width * 0.22)
        cloud(
            in: &context, center: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.32),
            size: rect.width * 0.15)

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

        // Umbrella.
        let pole = CGPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY - rect.height * 0.08)
        let canopy = rect.width * 0.26
        let top = CGPoint(x: pole.x + canopy * 0.15, y: shore + (rect.maxY - shore) * 0.05)
        var stick = Path()
        stick.move(to: pole)
        stick.addLine(to: top)
        context.stroke(stick, with: .color(Color(white: 0.95)), lineWidth: 3)
        let colors = [Color(red: 0.9, green: 0.25, blue: 0.22), .white]
        for stripe in 0..<6 {
            var wedge = Path()
            let start = Angle.degrees(180 + Double(stripe) * 30)
            wedge.move(to: top)
            wedge.addArc(
                center: top, radius: canopy / 2, startAngle: start, endAngle: start + .degrees(30), clockwise: false)
            wedge.closeSubpath()
            context.fill(wedge, with: .color(colors[stripe % 2]))
        }
    }

    /// A path into a pine forest at golden hour.
    private static func forest(in context: inout GraphicsContext, rect: CGRect) {
        let horizon = rect.minY + rect.height * 0.62
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.98, green: 0.82, blue: 0.6), Color(red: 0.95, green: 0.62, blue: 0.45)]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: horizon)))
        var random = NoiseSource(seed: 21)
        // Three layers of pines, far (pale) to near (dark).
        let layers: [(Color, CGFloat, CGFloat)] = [
            (Color(red: 0.55, green: 0.55, blue: 0.48), 0.34, 0.12),
            (Color(red: 0.3, green: 0.4, blue: 0.3), 0.5, 0.17),
            (Color(red: 0.13, green: 0.25, blue: 0.16), 0.75, 0.24),
        ]
        for (color, heightFraction, widthFraction) in layers {
            let treeWidth = rect.width * widthFraction
            var x = rect.minX - treeWidth * CGFloat(random.unit())
            while x < rect.maxX + treeWidth {
                let treeHeight = rect.height * heightFraction * CGFloat(random.value(in: 0.75...1.1))
                pine(
                    in: &context, base: CGPoint(x: x, y: horizon + 2), width: treeWidth, height: treeHeight,
                    color: color)
                x += treeWidth * CGFloat(random.value(in: 0.55...0.9))
            }
        }
        context.fill(
            Path(CGRect(x: rect.minX, y: horizon, width: rect.width, height: rect.maxY - horizon)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.24, green: 0.38, blue: 0.2), Color(red: 0.34, green: 0.5, blue: 0.24)]),
                startPoint: CGPoint(x: rect.midX, y: horizon), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        // Undergrowth along the tree line, so trunks sit in bushes, not in the sky.
        var bushX = rect.minX - rect.width * 0.05
        while bushX < rect.maxX {
            let bush = rect.width * CGFloat(random.value(in: 0.1...0.18))
            context.fill(
                Path(ellipseIn: CGRect(x: bushX, y: horizon - bush * 0.45, width: bush, height: bush * 0.7)),
                with: .color(Color(red: 0.16, green: 0.3, blue: 0.17)))
            bushX += bush * 0.6
        }
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - rect.width * 0.02, y: horizon))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.02, y: horizon))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.3, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.3, y: rect.maxY))
        path.closeSubpath()
        context.fill(path, with: .color(Color(red: 0.7, green: 0.56, blue: 0.38)))
    }

    /// Stars, a ringed planet and a faint galaxy.
    private static func space(in context: inout GraphicsContext, rect: CGRect) {
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.02, green: 0.02, blue: 0.08), Color(red: 0.1, green: 0.05, blue: 0.2)]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        let galaxy = CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.3)
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: galaxy.x - rect.width * 0.35, y: galaxy.y - rect.width * 0.15, width: rect.width * 0.7,
                    height: rect.width * 0.3)),
            with: .radialGradient(
                Gradient(colors: [Color(red: 0.75, green: 0.6, blue: 1).opacity(0.35), .clear]), center: galaxy,
                startRadius: 0, endRadius: rect.width * 0.35))
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

    /// Just bricks. And a note.
    private static func brickWall(in context: inout GraphicsContext, rect: CGRect) {
        context.fill(Path(rect), with: .color(Color(red: 0.78, green: 0.74, blue: 0.68)))
        var random = NoiseSource(seed: 3)
        let brickHeight = max(rect.width * 0.09, 12)
        let brickWidth = brickHeight * 2.2
        let mortar: CGFloat = 3
        var row = 0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX - (row.isMultiple(of: 2) ? 0 : brickWidth / 2)
            while x < rect.maxX {
                let brick = CGRect(
                    x: x + mortar / 2, y: y + mortar / 2, width: brickWidth - mortar, height: brickHeight - mortar)
                let tone = Double(random.value(in: -0.08...0.08))
                context.fill(
                    Path(roundedRect: brick, cornerRadius: 1.5),
                    with: .color(Color(red: 0.66 + tone, green: 0.3 + tone * 0.6, blue: 0.22 + tone * 0.4)))
                context.fill(
                    Path(CGRect(x: brick.minX, y: brick.maxY - 2, width: brick.width, height: 2)),
                    with: .color(.black.opacity(0.15)))
                x += brickWidth
            }
            y += brickHeight
            row += 1
        }
        // A sticky note at eye level.
        let note = rect.width * 0.3
        let noteRect = CGRect(x: rect.midX - note / 2, y: rect.minY + rect.height * 0.32, width: note, height: note)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.35), radius: 4, x: 2, y: 3))
            layer.translateBy(x: noteRect.midX, y: noteRect.midY)
            layer.rotate(by: .degrees(-4))
            layer.fill(
                Path(CGRect(x: -note / 2, y: -note / 2, width: note, height: note)),
                with: .color(Color(red: 1, green: 0.92, blue: 0.45)))
            layer.draw(
                Text("Nice try.").font(.system(size: note * 0.17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.25, green: 0.2, blue: 0.1)),
                at: .zero)
        }
    }

    private static func cloud(in context: inout GraphicsContext, center: CGPoint, size: CGFloat) {
        for (dx, dy, scale) in [(-0.3, 0.05, 0.55), (0.0, -0.1, 0.7), (0.3, 0.05, 0.55)]
            as [(CGFloat, CGFloat, CGFloat)]
        {
            let radius = size * scale / 2
            let point = CGPoint(x: center.x + dx * size, y: center.y + dy * size)
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: point.x - radius, y: point.y - radius * 0.7, width: radius * 2, height: radius * 1.4)),
                with: .color(.white.opacity(0.9)))
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
