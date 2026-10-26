import SwiftUI

/// Shared proportions so the hinges on the door leaf, the frame and the crease line up.
enum DoorGeometry {
    /// Vertical centers of the three hinges, as fractions of the door height.
    static let hingeCenters: [CGFloat] = [0.1, 0.5, 0.9]
    static let hingeHeight: CGFloat = 0.075
    /// Vertical center of the knob and strike plate.
    static let latchHeight: CGFloat = 0.45
}

/// A four-panel wooden door leaf, drawn in a `Canvas`.
///
/// `hingeSide` is the side the hinges are on as seen on screen: the leading edge on the
/// cover display (the physical hinge is on the left), the trailing edge on the inside face.
struct DoorLeafArt: View {
    let palette: DoorPalette
    var hingeSide: HorizontalEdge = .leading
    var showsPeephole = true

    var body: some View {
        Canvas { context, size in
            DoorLeafPainter(palette: palette, hingeSide: hingeSide, showsPeephole: showsPeephole)
                .paint(in: &context, size: size)
        }
    }
}

private struct DoorLeafPainter {
    let palette: DoorPalette
    let hingeSide: HorizontalEdge
    let showsPeephole: Bool

    func paint(in context: inout GraphicsContext, size: CGSize) {
        let width = size.width
        let height = size.height
        /// Mirrors x for hardware so hinges and knob land on the right sides.
        func fromHinge(_ x: CGFloat) -> CGFloat { hingeSide == .leading ? x : width - x }

        // Wood and grain.
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [palette.wood, palette.woodShade]), startPoint: .zero,
                endPoint: CGPoint(x: width, y: height)))
        WoodGrain.paint(in: &context, rect: CGRect(origin: .zero, size: size), color: palette.woodShade, seed: 7)

        // Panels: stiles on both sides, a muntin in the middle, a lock rail at knob height.
        let stile = width * 0.15
        let muntin = width * 0.07
        let columnWidth = (width - 2 * stile - muntin) / 2
        let rows: [(CGFloat, CGFloat)] = [
            (height * 0.07, height * (DoorGeometry.latchHeight - 0.05)),
            (height * (DoorGeometry.latchHeight + 0.06), height * 0.92),
        ]
        for (top, bottom) in rows {
            for column in 0..<2 {
                let x = stile + CGFloat(column) * (columnWidth + muntin)
                paintPanel(in: &context, rect: CGRect(x: x, y: top, width: columnWidth, height: bottom - top))
            }
        }

        // Hinge plates on the hinge edge.
        let plateWidth = max(width * 0.045, 10)
        for center in DoorGeometry.hingeCenters {
            let plateHeight = height * DoorGeometry.hingeHeight
            let x = hingeSide == .leading ? 0 : width - plateWidth
            let plate = CGRect(x: x, y: height * center - plateHeight / 2, width: plateWidth, height: plateHeight)
            MetalPainter.plate(in: &context, rect: plate, metal: palette.metal)
        }

        // Knob with escutcheon and keyhole, centered in the latch-side stile.
        let knobX = fromHinge(width - stile / 2)
        let knobY = height * DoorGeometry.latchHeight
        let knobSize = min(stile * 0.62, width * 0.1)
        let escutcheon = CGRect(
            x: knobX - knobSize * 0.42, y: knobY - knobSize * 0.9, width: knobSize * 0.84, height: knobSize * 2.3)
        MetalPainter.plate(in: &context, rect: escutcheon, metal: palette.metal, screws: false)
        let keyhole = CGPoint(x: knobX, y: knobY + knobSize * 0.95)
        context.fill(
            Path(ellipseIn: CGRect(x: keyhole.x - 2.5, y: keyhole.y - 2.5, width: 5, height: 5)), with: .color(.black))
        context.fill(
            Path(CGRect(x: keyhole.x - 1.2, y: keyhole.y, width: 2.4, height: 6)), with: .color(.black))
        MetalPainter.knob(
            in: &context,
            rect: CGRect(x: knobX - knobSize / 2, y: knobY - knobSize / 2, width: knobSize, height: knobSize),
            metal: palette.metal)

        if showsPeephole {
            let peephole = min(muntin * 0.55, 18)
            MetalPainter.knob(
                in: &context,
                rect: CGRect(x: width / 2 - peephole / 2, y: height * 0.22, width: peephole, height: peephole),
                metal: palette.metal)
        }
    }

    /// A raised panel: dark recess, a lighter field, and bevel light from the top left.
    private func paintPanel(in context: inout GraphicsContext, rect: CGRect) {
        let bevel = min(rect.width, rect.height) * 0.09
        context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(palette.woodShade.opacity(0.6)))
        let field = rect.insetBy(dx: bevel, dy: bevel)
        context.fill(
            Path(roundedRect: field, cornerRadius: 2),
            with: .linearGradient(
                Gradient(colors: [palette.wood.mix(with: .white, by: 0.08), palette.wood]),
                startPoint: CGPoint(x: field.minX, y: field.minY), endPoint: CGPoint(x: field.maxX, y: field.maxY)))
        WoodGrain.paint(in: &context, rect: field, color: palette.woodShade, seed: UInt32(rect.minX + rect.minY))

        var highlight = Path()
        highlight.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        highlight.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        highlight.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        context.stroke(highlight, with: .color(.black.opacity(0.35)), lineWidth: 2)
        var shade = Path()
        shade.move(to: CGPoint(x: field.minX, y: field.maxY))
        shade.addLine(to: CGPoint(x: field.maxX, y: field.maxY))
        shade.addLine(to: CGPoint(x: field.maxX, y: field.minY))
        context.stroke(shade, with: .color(.black.opacity(0.25)), lineWidth: 1.5)
        var shine = Path()
        shine.move(to: CGPoint(x: field.minX, y: field.maxY))
        shine.addLine(to: CGPoint(x: field.minX, y: field.minY))
        shine.addLine(to: CGPoint(x: field.maxX, y: field.minY))
        context.stroke(shine, with: .color(.white.opacity(0.15)), lineWidth: 1.5)
    }
}

/// Faint, slightly wavy vertical grain lines. Seeded, so the door looks the same every time.
enum WoodGrain {
    static func paint(in context: inout GraphicsContext, rect: CGRect, color: Color, seed: UInt32) {
        var random = NoiseSource(seed: seed &+ 1)
        let lineCount = Int(rect.width / 9)
        for _ in 0..<lineCount {
            let baseX = rect.minX + CGFloat(random.unit()) * rect.width
            let amplitude = 1 + CGFloat(random.unit()) * 4
            let waves = 0.5 + CGFloat(random.unit()) * 2
            let phase = CGFloat(random.unit()) * .pi * 2
            var path = Path()
            var y = rect.minY
            path.move(to: CGPoint(x: baseX + amplitude * sin(phase), y: y))
            while y < rect.maxY {
                y = min(y + 10, rect.maxY)
                let progress = (y - rect.minY) / rect.height
                path.addLine(to: CGPoint(x: baseX + amplitude * sin(phase + waves * progress * .pi * 2), y: y))
            }
            context.stroke(
                path, with: .color(color.opacity(0.08 + 0.14 * Double(random.unit()))),
                lineWidth: 0.6 + CGFloat(random.unit()) * 1.4)
        }
    }
}

/// Wrought-iron hardware.
enum MetalPainter {
    static func plate(in context: inout GraphicsContext, rect: CGRect, metal: Color, screws: Bool = true) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 2, x: 1, y: 1.5))
            layer.fill(
                Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.2),
                with: .linearGradient(
                    Gradient(colors: [metal.mix(with: .white, by: 0.25), metal, metal.mix(with: .black, by: 0.3)]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        }
        guard screws else { return }
        let screw = min(rect.width * 0.32, 5)
        for fraction in [0.2, 0.8] {
            let center = CGPoint(x: rect.midX, y: rect.minY + rect.height * fraction)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - screw / 2, y: center.y - screw / 2, width: screw, height: screw)),
                with: .color(metal.mix(with: .black, by: 0.5)))
        }
    }

    static func knob(in context: inout GraphicsContext, rect: CGRect, metal: Color) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 3, x: 1.5, y: 2.5))
            layer.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [metal.mix(with: .white, by: 0.45), metal, metal.mix(with: .black, by: 0.4)]),
                    center: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.3),
                    startRadius: 0, endRadius: rect.width * 0.75))
        }
    }

    /// The hinge barrel: a vertical cylinder straddling the hinge line.
    static func barrel(in context: inout GraphicsContext, rect: CGRect, metal: Color) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2))
            layer.fill(
                Path(roundedRect: rect, cornerRadius: rect.width / 2),
                with: .linearGradient(
                    Gradient(colors: [
                        metal.mix(with: .black, by: 0.3), metal.mix(with: .white, by: 0.4), metal,
                        metal.mix(with: .black, by: 0.45),
                    ]),
                    startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
        }
        // Knuckle seams.
        for fraction in [0.33, 0.66] {
            let y = rect.minY + rect.height * fraction
            var seam = Path()
            seam.move(to: CGPoint(x: rect.minX + 1, y: y))
            seam.addLine(to: CGPoint(x: rect.maxX - 1, y: y))
            context.stroke(seam, with: .color(.black.opacity(0.5)), lineWidth: 1)
        }
    }
}

#Preview("Outside") {
    DoorLeafArt(palette: DoorStyle.oakWithIronHinges.palette)
        .ignoresSafeArea()
}

#Preview("Inside face") {
    DoorLeafArt(palette: DoorStyle.oakWithIronHinges.palette, hingeSide: .trailing, showsPeephole: false)
        .ignoresSafeArea()
}
