import SwiftUI

extension ScenePainter {
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

    /// A warm little room: lamp, picture, floorboards, rug.
    static func livingRoom(in context: inout GraphicsContext, rect: CGRect) {
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

extension SceneLife {
    static func livingRoom(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval) {
        // The pendant lamp sways a little, as if someone just walked past.
        let anchor = CGPoint(x: rect.midX, y: rect.minY)
        let length = rect.height * 0.1 - rect.width * 0.04
        let swing = Angle.degrees(3 * sin(time * 1.3))
        context.drawLayer { lamp in
            lamp.translateBy(x: anchor.x, y: anchor.y)
            lamp.rotate(by: swing)
            var cord = Path()
            cord.move(to: .zero)
            cord.addLine(to: CGPoint(x: 0, y: length))
            lamp.stroke(cord, with: .color(.black.opacity(0.6)), lineWidth: 1.5)
            let width = rect.width * 0.16
            var shade = Path()
            shade.move(to: CGPoint(x: -width * 0.25, y: length))
            shade.addLine(to: CGPoint(x: width * 0.25, y: length))
            shade.addLine(to: CGPoint(x: width / 2, y: length + rect.width * 0.07))
            shade.addLine(to: CGPoint(x: -width / 2, y: length + rect.width * 0.07))
            shade.closeSubpath()
            lamp.fill(shade, with: .color(Color(red: 0.2, green: 0.35, blue: 0.3)))
        }

        // On the floor, nearer is lower and bigger.
        func floorSpot(distance: CGFloat) -> (y: CGFloat, scale: CGFloat) {
            (rect.minY + rect.height * (0.95 - 0.22 * distance), 1 - 0.45 * distance)
        }

        // The cat: strolls past close by, strolls past further back, or just peeks in from the
        // side, has a look around, and goes back.
        if let visit = visit(time: time, period: 11, duration: 6, salt: 1) {
            if visit.variant == 2 {
                let spot = floorSpot(distance: 0.3 + 0.4 * visit.lane)
                let size = rect.width * 0.3 * spot.scale
                let p = visit.progress
                // In over the first quarter, a look around, back out over the last quarter.
                let reach = p < 0.25 ? smooth(p / 0.25) : (p > 0.75 ? smooth((1 - p) / 0.25) : 1)
                let fromLeft = visit.facing > 0
                let edge = fromLeft ? rect.minX : rect.maxX
                let x = edge + (fromLeft ? 1 : -1) * (-size * 0.6 + CGFloat(reach) * size * 0.75)
                let leaving = p > 0.75
                let facing: CGFloat = (fromLeft != leaving) ? 1 : -1
                critter(in: &context, at: CGPoint(x: x, y: spot.y), facing: facing) {
                    cat(in: &$0, size: size, time: time, pose: p < 0.25 || p > 0.75 ? .walk : .stand)
                }
            } else {
                let spot = floorSpot(distance: visit.variant == 0 ? 0.1 * visit.lane : 0.65 + 0.3 * visit.lane)
                let size = rect.width * 0.3 * spot.scale
                critter(in: &context, at: CGPoint(x: visit.x(in: rect, margin: size), y: spot.y), facing: visit.facing)
                {
                    cat(in: &$0, size: size, time: time)
                }
            }
        }

        // The dog trots past, tail going.
        if let visit = visit(time: time, period: 17, duration: 5, salt: 15) {
            let spot = floorSpot(distance: [0.05, 0.45, 0.8][visit.variant])
            let size = rect.width * 0.34 * spot.scale
            critter(in: &context, at: CGPoint(x: visit.x(in: rect, margin: size), y: spot.y), facing: visit.facing) {
                dog(in: &$0, size: size, time: time)
            }
        }
    }

    /// A beagle-ish dog: floppy ears, a wagging tail, tongue out.
    private static func dog(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        let coat = Color(red: 0.86, green: 0.62, blue: 0.36)
        let white = Color(red: 0.97, green: 0.94, blue: 0.88)
        let brown = Color(red: 0.42, green: 0.26, blue: 0.14)
        let step = time * 10
        let bob = CGFloat(abs(sin(step))) * size * 0.025
        for (x, phase) in [(0.26, 0.0), (0.16, .pi), (-0.26, .pi), (-0.36, 0.0)] as [(CGFloat, Double)] {
            var leg = Path()
            leg.move(to: CGPoint(x: x * size, y: -size * 0.3))
            leg.addLine(to: CGPoint(x: x * size + CGFloat(sin(step + phase)) * size * 0.08, y: 0))
            context.stroke(leg, with: .color(white), style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
        }
        // Tail, wagging fast.
        let wag = CGFloat(sin(time * 18)) * size * 0.1
        var tail = Path()
        tail.move(to: CGPoint(x: -size * 0.42, y: -size * 0.45 - bob))
        tail.addQuadCurve(
            to: CGPoint(x: -size * 0.55 + wag, y: -size * 0.78), control: CGPoint(x: -size * 0.58, y: -size * 0.5))
        context.stroke(tail, with: .color(coat), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
        // Body with a white belly and a dark saddle.
        let body = CGRect(x: -size * 0.48, y: -size * 0.6 - bob, width: size * 0.92, height: size * 0.36)
        context.fill(Path(ellipseIn: body), with: .color(coat))
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: body.minX + size * 0.1, y: body.midY, width: body.width * 0.7, height: body.height * 0.5)),
            with: .color(white))
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: body.minX + size * 0.12, y: body.minY - size * 0.01, width: body.width * 0.5,
                    height: body.height * 0.45)),
            with: .color(brown))
        // Head: skull, white snout, floppy ear, eye, nose and a pink tongue.
        let head = CGPoint(x: size * 0.48, y: -size * 0.7 - bob)
        context.fill(
            Path(ellipseIn: CGRect(x: size * 0.32, y: -size * 0.66 - bob, width: size * 0.2, height: size * 0.24)),
            with: .color(coat))
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: head.x - size * 0.16, y: head.y - size * 0.15, width: size * 0.3, height: size * 0.28)),
            with: .color(coat))
        context.fill(
            Path(
                roundedRect: CGRect(
                    x: head.x + size * 0.05, y: head.y - size * 0.02, width: size * 0.2, height: size * 0.13),
                cornerRadius: size * 0.06),
            with: .color(white))
        let tongue = CGFloat(abs(sin(time * 6))) * size * 0.02
        context.fill(
            Path(
                roundedRect: CGRect(
                    x: head.x + size * 0.12, y: head.y + size * 0.09, width: size * 0.06, height: size * 0.07 + tongue),
                cornerRadius: size * 0.03),
            with: .color(Color(red: 0.95, green: 0.45, blue: 0.5)))
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: head.x + size * 0.21, y: head.y - size * 0.02, width: size * 0.06, height: size * 0.05)),
            with: .color(Color(white: 0.1)))
        let blink = time.truncatingRemainder(dividingBy: 2.9) < 0.12
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: head.x + size * 0.03, y: head.y - size * 0.08, width: size * 0.05,
                    height: blink ? size * 0.01 : size * 0.055)),
            with: .color(Color(white: 0.1)))
        context.drawLayer { ear in
            ear.translateBy(x: head.x - size * 0.06, y: head.y - size * 0.1)
            ear.rotate(by: .degrees(18 + Double(sin(step)) * 6))
            ear.fill(
                Path(ellipseIn: CGRect(x: -size * 0.06, y: 0, width: size * 0.13, height: size * 0.26)),
                with: .color(brown))
        }
    }
}
