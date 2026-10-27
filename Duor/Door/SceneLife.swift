import SwiftUI

/// The moving parts of each scene, drawn on top of the still background every frame.
///
/// Two kinds of life:
/// - **Ambient:** always there, gently moving (a swaying lamp, rolling waves, torch flames,
///   twinkling stars).
/// - **Visitors:** someone passing by now and then (a cat, a knight, a seagull, a UFO…).
///   Visits are a pure function of time: each period gets a random start, direction and lane
///   from a seed, so nothing has to be stored and every frame is cheap to compute.
///
/// With `catLovers` on, every scene also gets a cat with a little story (see `SceneCats.swift`).
enum SceneLife {
    static func paint(
        _ scene: InsideScene, in context: inout GraphicsContext, rect: CGRect, time: TimeInterval,
        catLovers: Bool = false
    ) {
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            switch scene {
            case .livingRoom: livingRoom(in: &layer, rect: rect, time: time)
            case .greatHall: greatHall(in: &layer, rect: rect, time: time, catLovers: catLovers)
            case .beach: beach(in: &layer, rect: rect, time: time, catLovers: catLovers)
            case .forest: forest(in: &layer, rect: rect, time: time, catLovers: catLovers)
            case .space: space(in: &layer, rect: rect, time: time, catLovers: catLovers)
            case .brickWall: brickWall(in: &layer, rect: rect, time: time, catLovers: catLovers)
            }
        }
    }

    static func torchPositions(in rect: CGRect) -> [CGPoint] {
        [0.08, 0.92].map { CGPoint(x: rect.minX + rect.width * $0, y: rect.minY + rect.height * 0.3) }
    }

    // MARK: Scenes

    private static func livingRoom(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval) {
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

    private static func greatHall(
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

    private static func beach(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval, catLovers: Bool) {
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

    private static func forest(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval, catLovers: Bool) {
        // Leaves drifting down.
        for index in 0..<4 {
            let fall = 7.0 + Double(index)
            let phase = (time + Double(index) * 2.3).truncatingRemainder(dividingBy: fall) / fall
            let x =
                rect.minX + rect.width * (0.15 + 0.22 * CGFloat(index)) + sin((time + Double(index)) * 1.6) * rect.width
                * 0.05
            let y = rect.minY + rect.height * CGFloat(phase)
            leaf(in: &context, at: CGPoint(x: x, y: y), size: rect.width * 0.04, time: time + Double(index))
        }
        // Birds crossing the evening sky.
        if let visit = visit(time: time, period: 10, duration: 4.5, salt: 7) {
            let size = rect.width * 0.06
            let x = visit.x(in: rect, margin: size * 4)
            for bird in 0..<3 {
                let offset = CGPoint(x: -CGFloat(bird) * size * 1.4 * visit.facing, y: CGFloat(bird % 2) * size * 0.8)
                let y = rect.minY + rect.height * (0.08 + 0.12 * visit.lane) + offset.y
                critter(in: &context, at: CGPoint(x: x + offset.x, y: y), facing: visit.facing) {
                    flyingBird(in: &$0, size: size, time: time + Double(bird) * 0.3)
                }
            }
        }
        // A deer pops up from behind a bush and looks right at you. Usually it ducks back down;
        // sometimes it bolts out of the bush and runs off to the right.
        if let visit = visit(time: time, period: 14, duration: 6, salt: 14) {
            let bush = ForestLayout.deerBush(in: rect)
            let p = visit.progress
            let runsAway = visit.variant == 1
            let size = bush.size * 0.5
            let hidden = bush.center.y + bush.size * 0.05
            let peak = bush.center.y - bush.size * 0.74
            let rise =
                p < 0.15
                ? smooth(p / 0.15)
                : runsAway ? (p < 0.45 ? 1 : 0) : (p > 0.85 ? smooth((1 - p) / 0.15) : 1)
            if rise > 0 {
                // Only what's above the ground line shows; the bush covers the rest.
                context.drawLayer { layer in
                    layer.clip(
                        to: Path(
                            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: bush.center.y - rect.minY)))
                    deer(
                        in: &layer, head: CGPoint(x: bush.center.x, y: hidden + (peak - hidden) * CGFloat(rise)),
                        size: size, time: time)
                }
            }
            ForestLayout.paintBush(bush, in: &context, shadow: false)
            if runsAway, p >= 0.45 {
                let run = CGFloat((p - 0.45) / 0.55)
                let runner = bush.size * 0.7
                let x = bush.center.x + (rect.maxX + runner - bush.center.x) * run
                let hop = abs(sin(time * 11)) * runner * 0.22
                let feet = bush.center.y + bush.size * 0.04 - hop
                critter(in: &context, at: CGPoint(x: x, y: feet), facing: 1) {
                    runningDeer(in: &$0, size: runner, time: time)
                }
                // The trunks are nearer than the deer: redraw them over it, only around the deer
                // so the canopy above is untouched.
                context.drawLayer { layer in
                    layer.clip(
                        to: Path(
                            CGRect(
                                x: rect.minX, y: feet - runner * 1.1, width: rect.width, height: runner * 1.1 + hop + 4)
                        ))
                    ForestLayout.paintTrunks(in: &layer, rect: rect)
                }
            }
        }
        // A rabbit hops across the grass. For cat lovers, it stops to nibble and a cat stalks it.
        if catLovers {
            catChasingRabbit(in: &context, rect: rect, time: time)
        } else if let visit = visit(time: time, period: 12, duration: 4, salt: 8) {
            let size = rect.width * 0.14
            let x = visit.x(in: rect, margin: size)
            let hop = abs(sin(time * 7)) * size * 0.35
            critter(in: &context, at: CGPoint(x: x, y: rect.minY + rect.height * 0.92 - hop), facing: visit.facing) {
                rabbit(in: &$0, size: size)
            }
        }
    }

    private static func space(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval, catLovers: Bool) {
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

    private static func brickWall(
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
        // A cat pounces on a mouse. The mouse was right behind it.
        if catLovers {
            catAtTheWall(in: &context, rect: rect, time: time)
        }
    }

    // MARK: Visits

    struct Visit {
        /// 0 at the start of the visit, 1 at the end.
        let progress: Double
        /// 1 walking right, -1 walking left.
        let facing: CGFloat
        /// 0...1, a random lane (height) for this visit.
        let lane: CGFloat
        /// 0, 1 or 2: which version of the visit this is (e.g. near, far, or just a peek).
        let variant: Int

        /// Horizontal position, entering and leaving just outside the scene.
        func x(in rect: CGRect, margin: CGFloat) -> CGFloat {
            let travel = CGFloat(progress)
            let from = rect.minX - margin
            let to = rect.maxX + margin
            return facing > 0 ? from + (to - from) * travel : to - (to - from) * travel
        }
    }

    /// Whether a visitor is passing at `time`, and where. Each `period` holds one visit of
    /// `duration` at a random moment, in a random direction; `salt` keeps visitors independent.
    static func visit(time: TimeInterval, period: Double, duration: Double, salt: UInt32) -> Visit? {
        let cycle = (time / period).rounded(.down)
        var random = NoiseSource(seed: UInt32(truncatingIfNeeded: Int64(cycle)) &* 2_654_435_761 &+ salt &* 97)
        let start = Double(random.unit()) * (period - duration)
        let phase = time - cycle * period - start
        guard phase >= 0, phase <= duration else { return nil }
        let facing: CGFloat = random.unit() < 0.5 ? 1 : -1
        let lane = CGFloat(random.unit())
        return Visit(progress: phase / duration, facing: facing, lane: lane, variant: Int(random.nextUInt() % 3))
    }

    /// Draws a critter in its own coordinates: origin at its feet, facing right (mirrored if not).
    static func critter(
        in context: inout GraphicsContext, at point: CGPoint, facing: CGFloat, draw: (inout GraphicsContext) -> Void
    ) {
        context.drawLayer { layer in
            layer.translateBy(x: point.x, y: point.y)
            layer.scaleBy(x: facing, y: 1)
            draw(&layer)
        }
    }

    // MARK: Critters (origin at the feet, facing right)

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

    private static func smooth(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// A deer facing you: big ears that twitch, big dark eyes that blink.
    private static func deer(in context: inout GraphicsContext, head: CGPoint, size: CGFloat, time: TimeInterval) {
        let fur = Color(red: 0.68, green: 0.45, blue: 0.27)
        let pale = Color(red: 0.95, green: 0.88, blue: 0.78)
        // Neck, reaching down behind the bush.
        context.fill(
            Path(
                roundedRect: CGRect(x: head.x - size * 0.16, y: head.y, width: size * 0.32, height: size * 0.9),
                cornerRadius: size * 0.12),
            with: .color(fur.mix(with: .black, by: 0.1)))
        // Ears, one twitching now and then.
        let twitch = time.truncatingRemainder(dividingBy: 2.6) < 0.18 ? 14.0 : 0
        for side in [-1.0, 1.0] as [CGFloat] {
            context.drawLayer { ear in
                ear.translateBy(x: head.x + side * size * 0.2, y: head.y - size * 0.22)
                ear.rotate(by: .degrees(Double(side) * (58 + (side > 0 ? twitch : 0))))
                ear.fill(
                    Path(ellipseIn: CGRect(x: -size * 0.09, y: -size * 0.36, width: size * 0.18, height: size * 0.36)),
                    with: .color(fur))
                ear.fill(
                    Path(ellipseIn: CGRect(x: -size * 0.05, y: -size * 0.31, width: size * 0.1, height: size * 0.26)),
                    with: .color(Color(red: 0.95, green: 0.75, blue: 0.7)))
            }
        }
        // Head: a wide brow narrowing to a pale muzzle.
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: head.x - size * 0.24, y: head.y - size * 0.32, width: size * 0.48, height: size * 0.44)),
            with: .color(fur))
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: head.x - size * 0.14, y: head.y - size * 0.02, width: size * 0.28, height: size * 0.3)),
            with: .color(pale))
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: head.x - size * 0.06, y: head.y + size * 0.08, width: size * 0.12, height: size * 0.08)),
            with: .color(Color(white: 0.1)))
        // Big eyes looking straight at you, blinking every few seconds.
        let blink = time.truncatingRemainder(dividingBy: 3.1) < 0.14
        for side in [-1.0, 1.0] as [CGFloat] {
            let eye = CGRect(
                x: head.x + side * size * 0.12 - size * 0.055, y: head.y - size * 0.14, width: size * 0.11,
                height: blink ? size * 0.015 : size * 0.12)
            context.fill(Path(ellipseIn: eye), with: .color(Color(white: 0.08)))
            if !blink {
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: eye.minX + eye.width * 0.2, y: eye.minY + eye.height * 0.15, width: eye.width * 0.35,
                            height: eye.width * 0.35)),
                    with: .color(.white))
            }
        }
    }

    /// A deer bounding away, side on: legs stretched out then tucked, white tail up.
    private static func runningDeer(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        let fur = Color(red: 0.68, green: 0.45, blue: 0.27)
        let stride = CGFloat(sin(time * 11))
        // Legs: stretched fore and aft mid-leap, tucked when landing.
        for (x, reach) in [(0.28, 0.22), (0.2, 0.18), (-0.26, -0.22), (-0.34, -0.18)] as [(CGFloat, CGFloat)] {
            var leg = Path()
            leg.move(to: CGPoint(x: x * size, y: -size * 0.32))
            leg.addLine(to: CGPoint(x: (x + reach * stride) * size, y: -size * 0.02))
            context.stroke(
                leg, with: .color(fur.mix(with: .black, by: 0.15)),
                style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
        }
        // Body, white belly and the white tail flag.
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.45, y: -size * 0.55, width: size * 0.85, height: size * 0.3)),
            with: .color(fur))
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.3, y: -size * 0.38, width: size * 0.55, height: size * 0.12)),
            with: .color(Color(red: 0.95, green: 0.88, blue: 0.78)))
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.55, y: -size * 0.66, width: size * 0.13, height: size * 0.18)),
            with: .color(.white))
        // Neck and head, stretched forward.
        var neck = Path()
        neck.move(to: CGPoint(x: size * 0.22, y: -size * 0.5))
        neck.addLine(to: CGPoint(x: size * 0.42, y: -size * 0.78))
        context.stroke(neck, with: .color(fur), style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round))
        context.fill(
            Path(ellipseIn: CGRect(x: size * 0.36, y: -size * 0.88, width: size * 0.24, height: size * 0.14)),
            with: .color(fur))
        context.fill(
            Path(ellipseIn: CGRect(x: size * 0.54, y: -size * 0.84, width: size * 0.05, height: size * 0.04)),
            with: .color(Color(white: 0.1)))
        context.fill(
            Path(ellipseIn: CGRect(x: size * 0.44, y: -size * 0.86, width: size * 0.04, height: size * 0.04)),
            with: .color(Color(white: 0.08)))
        context.drawLayer { ear in
            ear.translateBy(x: size * 0.39, y: -size * 0.86)
            ear.rotate(by: .degrees(-35))
            ear.fill(
                Path(ellipseIn: CGRect(x: -size * 0.04, y: -size * 0.16, width: size * 0.08, height: size * 0.16)),
                with: .color(fur))
        }
    }

    static func rabbit(in context: inout GraphicsContext, size: CGFloat) {
        let fur = Color(red: 0.78, green: 0.66, blue: 0.54)
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.4, y: -size * 0.4, width: size * 0.6, height: size * 0.4)),
            with: .color(fur))
        context.fill(
            Path(ellipseIn: CGRect(x: -size * 0.5, y: -size * 0.36, width: size * 0.16, height: size * 0.16)),
            with: .color(.white))
        let head = CGRect(x: size * 0.05, y: -size * 0.55, width: size * 0.3, height: size * 0.26)
        for (dx, tilt) in [(0.1, -12.0), (0.2, 6.0)] as [(CGFloat, Double)] {
            context.drawLayer { ear in
                ear.translateBy(x: dx * size + size * 0.05, y: head.minY + size * 0.04)
                ear.rotate(by: .degrees(tilt))
                ear.fill(
                    Path(ellipseIn: CGRect(x: -size * 0.05, y: -size * 0.32, width: size * 0.1, height: size * 0.34)),
                    with: .color(fur))
                ear.fill(
                    Path(ellipseIn: CGRect(x: -size * 0.025, y: -size * 0.27, width: size * 0.05, height: size * 0.24)),
                    with: .color(Color(red: 0.95, green: 0.75, blue: 0.75)))
            }
        }
        context.fill(Path(ellipseIn: head), with: .color(fur))
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: head.midX + size * 0.04, y: head.minY + size * 0.08, width: size * 0.04, height: size * 0.05)),
            with: .color(.black))
    }

    private static func flyingBird(in context: inout GraphicsContext, size: CGFloat, time: TimeInterval) {
        let flap = CGFloat(sin(time * 9)) * size * 0.3
        var wings = Path()
        wings.move(to: CGPoint(x: -size * 0.5, y: -flap))
        wings.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -size * 0.2, y: -size * 0.1))
        wings.addQuadCurve(to: CGPoint(x: size * 0.5, y: -flap), control: CGPoint(x: size * 0.2, y: -size * 0.1))
        context.stroke(
            wings, with: .color(Color(red: 0.2, green: 0.15, blue: 0.15)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private static func leaf(in context: inout GraphicsContext, at point: CGPoint, size: CGFloat, time: TimeInterval) {
        context.drawLayer { layer in
            layer.translateBy(x: point.x, y: point.y)
            layer.rotate(by: .radians(sin(time * 2.2) * 0.9))
            var shape = Path()
            shape.move(to: CGPoint(x: -size / 2, y: 0))
            shape.addQuadCurve(to: CGPoint(x: size / 2, y: 0), control: CGPoint(x: 0, y: -size * 0.5))
            shape.addQuadCurve(to: CGPoint(x: -size / 2, y: 0), control: CGPoint(x: 0, y: size * 0.5))
            layer.fill(shape, with: .color(Color(red: 0.9, green: 0.55, blue: 0.2)))
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
}
