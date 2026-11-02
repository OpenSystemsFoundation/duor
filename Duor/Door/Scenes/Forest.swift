import SwiftUI

extension ScenePainter {
    /// A winding path leading into a glowing passage through a pine forest at golden hour.
    ///
    /// Painted back to front with atmospheric perspective: hazy far pines, a mist band, mid groves
    /// framing the passage, sunlit ground and path, foreground trunks under a leafy canopy, then
    /// sunbeams and big bushes.
    static func forest(in context: inout GraphicsContext, rect: CGRect) {
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
}

extension SceneLife {
    static func forest(in context: inout GraphicsContext, rect: CGRect, time: TimeInterval, catLovers: Bool) {
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

    // MARK: Cat

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
