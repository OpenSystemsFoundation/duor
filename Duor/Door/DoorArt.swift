import SwiftUI

/// Shared proportions so the hinges on the door leaf, the frame and the crease line up.
enum DoorGeometry {
    /// Vertical centers of the three hinges, as fractions of the door height.
    static let hingeCenters: [CGFloat] = [0.1, 0.5, 0.9]
    static let hingeHeight: CGFloat = 0.075
    /// Vertical center of the handle and strike plate.
    static let latchHeight: CGFloat = 0.45
}

/// Which side of the leaf is showing. The peephole is only on the outside.
enum DoorFace {
    case outside
    case inside
}

/// A door leaf, drawn in a `Canvas`.
///
/// `hingeSide` is the side the hinges are on as seen on screen: the leading edge on the
/// cover display (the physical hinge is on the left), the trailing edge on the inside face.
struct DoorLeafArt: View {
    let design: DoorDesign
    let palette: DoorPalette
    var hingeSide: HorizontalEdge = .leading
    var face: DoorFace = .outside

    init(look: DoorLook, hingeSide: HorizontalEdge = .leading, face: DoorFace = .outside) {
        self.init(design: look.style.design, palette: look.palette, hingeSide: hingeSide, face: face)
    }

    init(design: DoorDesign, palette: DoorPalette, hingeSide: HorizontalEdge = .leading, face: DoorFace = .outside) {
        self.design = design
        self.palette = palette
        self.hingeSide = hingeSide
        self.face = face
    }

    var body: some View {
        Canvas { context, size in
            DoorLeafPainter(design: design, palette: palette, hingeSide: hingeSide, face: face, size: size)
                .paint(in: &context)
        }
    }
}

private struct DoorLeafPainter {
    let design: DoorDesign
    let palette: DoorPalette
    let hingeSide: HorizontalEdge
    let face: DoorFace
    let size: CGSize

    var width: CGFloat { size.width }
    var height: CGFloat { size.height }
    var latchY: CGFloat { height * DoorGeometry.latchHeight }

    /// Mirrors x so hinges and handles land on the right sides.
    func fromHinge(_ x: CGFloat) -> CGFloat { hingeSide == .leading ? x : width - x }

    func paint(in context: inout GraphicsContext) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [palette.wood, palette.woodShade]), startPoint: .zero,
                endPoint: CGPoint(x: width, y: height)))
        WoodGrain.paint(
            in: &context, rect: CGRect(origin: .zero, size: size), color: palette.woodShade, seed: 7,
            strength: palette.isPainted ? 0.25 : 1)

        switch design {
        case .fourPanel: paintFourPanel(in: &context)
        case .glazed: paintGlazed(in: &context)
        case .planks: paintPlanks(in: &context, boards: 5, brace: true)
        case .studded: paintStudded(in: &context)
        case .slab: paintSlab(in: &context)
        }

        paintHinges(in: &context)
        paintHandle(in: &context)

        if design == .fourPanel, face == .outside {
            let peephole = min(width * 0.04, 18)
            MetalPainter.knob(
                in: &context,
                rect: CGRect(x: width / 2 - peephole / 2, y: height * 0.22, width: peephole, height: peephole),
                palette: palette)
        }
    }

    // MARK: Designs

    private func paintFourPanel(in context: inout GraphicsContext) {
        let stile = width * 0.15
        let muntin = width * 0.07
        let columnWidth = (width - 2 * stile - muntin) / 2
        let rows: [(CGFloat, CGFloat)] = [
            (height * 0.07, latchY - height * 0.05),
            (latchY + height * 0.06, height * 0.92),
        ]
        for (top, bottom) in rows {
            for column in 0..<2 {
                let x = stile + CGFloat(column) * (columnWidth + muntin)
                paintPanel(in: &context, rect: CGRect(x: x, y: top, width: columnWidth, height: bottom - top))
            }
        }
    }

    private func paintGlazed(in context: inout GraphicsContext) {
        let stile = width * 0.15
        let window = CGRect(x: stile, y: height * 0.07, width: width - 2 * stile, height: latchY - height * 0.12)

        // Glass: sky tint with a diagonal reflection, divided into four panes.
        context.fill(
            Path(roundedRect: window.insetBy(dx: -4, dy: -4), cornerRadius: 3), with: .color(palette.woodShade))
        context.fill(
            Path(window),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.78, green: 0.88, blue: 0.95), Color(red: 0.52, green: 0.66, blue: 0.78)]
                ),
                startPoint: CGPoint(x: window.minX, y: window.minY), endPoint: CGPoint(x: window.maxX, y: window.maxY)))
        var glare = Path()
        glare.move(to: CGPoint(x: window.minX + window.width * 0.15, y: window.maxY))
        glare.addLine(to: CGPoint(x: window.minX + window.width * 0.45, y: window.minY))
        glare.addLine(to: CGPoint(x: window.minX + window.width * 0.6, y: window.minY))
        glare.addLine(to: CGPoint(x: window.minX + window.width * 0.3, y: window.maxY))
        glare.closeSubpath()
        context.fill(glare, with: .color(.white.opacity(0.22)))
        let bar = max(width * 0.025, 4)
        context.fill(
            Path(CGRect(x: window.midX - bar / 2, y: window.minY, width: bar, height: window.height)),
            with: .color(palette.wood))
        context.fill(
            Path(CGRect(x: window.minX, y: window.midY - bar / 2, width: window.width, height: bar)),
            with: .color(palette.wood))

        let columnWidth = (width - 2 * stile - width * 0.07) / 2
        for column in 0..<2 {
            let x = stile + CGFloat(column) * (columnWidth + width * 0.07)
            paintPanel(
                in: &context,
                rect: CGRect(x: x, y: latchY + height * 0.06, width: columnWidth, height: height * 0.86 - latchY))
        }
    }

    private func paintPlanks(in context: inout GraphicsContext, boards: Int, brace: Bool) {
        var random = NoiseSource(seed: 11)
        let boardWidth = width / CGFloat(boards)
        for board in 0..<boards {
            let rect = CGRect(x: CGFloat(board) * boardWidth, y: 0, width: boardWidth, height: height)
            context.fill(Path(rect), with: .color(palette.woodShade.opacity(0.18 * Double(random.unit()))))
            if board > 0 {
                context.fill(
                    Path(CGRect(x: rect.minX - 1.5, y: 0, width: 3, height: height)),
                    with: .color(.black.opacity(0.45)))
            }
        }
        guard brace else { return }

        // Z brace: two rails behind the top and bottom hinges, a diagonal from the bottom hinge
        // side up to the top latch side.
        let rail = height * 0.08
        let rails = [height * DoorGeometry.hingeCenters[0], height * DoorGeometry.hingeCenters[2]]
        for center in rails {
            paintBoard(in: &context, rect: CGRect(x: 0, y: center - rail / 2, width: width, height: rail))
        }
        var diagonal = Path()
        diagonal.move(to: CGPoint(x: fromHinge(width * 0.06), y: rails[1] - rail / 2))
        diagonal.addLine(to: CGPoint(x: fromHinge(width * 0.06 + rail * 1.2), y: rails[1] - rail / 2))
        diagonal.addLine(to: CGPoint(x: fromHinge(width * 0.94), y: rails[0] + rail / 2))
        diagonal.addLine(to: CGPoint(x: fromHinge(width * 0.94 - rail * 1.2), y: rails[0] + rail / 2))
        diagonal.closeSubpath()
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.4), radius: 3, x: 1, y: 2))
            layer.fill(diagonal, with: .color(palette.wood.mix(with: .white, by: 0.06)))
        }
        context.stroke(diagonal, with: .color(.black.opacity(0.3)), lineWidth: 1)
    }

    private func paintStudded(in context: inout GraphicsContext) {
        paintPlanks(in: &context, boards: 4, brace: false)
        // Iron bands with studs, and a row of studs along the top and bottom.
        let band = max(height * 0.035, 8)
        let stud = max(width * 0.03, 6)
        for center in [height * 0.25, height * 0.72] {
            MetalPainter.plate(
                in: &context, rect: CGRect(x: 0, y: center - band / 2, width: width, height: band), palette: palette,
                screws: false)
            studs(in: &context, y: center, size: stud)
        }
        studs(in: &context, y: height * 0.04, size: stud * 0.8)
        studs(in: &context, y: height * 0.96, size: stud * 0.8)
    }

    private func paintSlab(in context: inout GraphicsContext) {
        for fraction in [0.3, 0.7] {
            let y = height * fraction
            context.fill(Path(CGRect(x: 0, y: y - 1.5, width: width, height: 2)), with: .color(.black.opacity(0.22)))
            context.fill(Path(CGRect(x: 0, y: y + 0.5, width: width, height: 1.5)), with: .color(.white.opacity(0.35)))
        }
    }

    // MARK: Parts

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
        WoodGrain.paint(
            in: &context, rect: field, color: palette.woodShade, seed: UInt32(rect.minX + rect.minY),
            strength: palette.isPainted ? 0.2 : 1)

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

    /// A horizontal board laid on top of the planks (a brace rail).
    private func paintBoard(in context: inout GraphicsContext, rect: CGRect) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2))
            layer.fill(Path(rect), with: .color(palette.wood.mix(with: .white, by: 0.06)))
        }
        WoodGrain.paint(in: &context, rect: rect, color: palette.woodShade, seed: UInt32(rect.minY), strength: 0.8)
        context.stroke(Path(rect), with: .color(.black.opacity(0.3)), lineWidth: 1)
    }

    private func studs(in context: inout GraphicsContext, y: CGFloat, size: CGFloat) {
        let count = 7
        for index in 0..<count {
            let x = width * (0.08 + 0.84 * CGFloat(index) / CGFloat(count - 1))
            MetalPainter.knob(
                in: &context, rect: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size),
                palette: palette)
        }
    }

    private func paintHinges(in context: inout GraphicsContext) {
        for center in DoorGeometry.hingeCenters {
            let y = height * center
            switch design {
            case .planks, .studded:
                // Long strap hinges reaching across the boards.
                let thickness = max(height * 0.03, 9)
                let length = width * (design == .studded ? 0.62 : 0.5)
                MetalPainter.strap(
                    in: &context, from: CGPoint(x: fromHinge(0), y: y), length: length, thickness: thickness,
                    direction: hingeSide == .leading ? 1 : -1, palette: palette)
            case .slab:
                let plate = CGRect(
                    x: hingeSide == .leading ? 0 : width - max(width * 0.025, 6),
                    y: y - height * DoorGeometry.hingeHeight * 0.4, width: max(width * 0.025, 6),
                    height: height * DoorGeometry.hingeHeight * 0.8)
                MetalPainter.plate(in: &context, rect: plate, palette: palette, screws: false)
            case .fourPanel, .glazed:
                let plateWidth = max(width * 0.045, 10)
                let plateHeight = height * DoorGeometry.hingeHeight
                let plate = CGRect(
                    x: hingeSide == .leading ? 0 : width - plateWidth, y: y - plateHeight / 2, width: plateWidth,
                    height: plateHeight)
                MetalPainter.plate(in: &context, rect: plate, palette: palette)
            }
        }
    }

    private func paintHandle(in context: inout GraphicsContext) {
        switch design {
        case .fourPanel, .glazed:
            // Knob with escutcheon and keyhole, centered in the latch-side stile.
            let stile = width * 0.15
            let knobX = fromHinge(width - stile / 2)
            let knobSize = min(stile * 0.62, width * 0.1)
            let escutcheon = CGRect(
                x: knobX - knobSize * 0.42, y: latchY - knobSize * 0.9, width: knobSize * 0.84,
                height: knobSize * 2.3)
            MetalPainter.plate(in: &context, rect: escutcheon, palette: palette, screws: false)
            keyhole(in: &context, at: CGPoint(x: knobX, y: latchY + knobSize * 0.95))
            MetalPainter.knob(
                in: &context,
                rect: CGRect(x: knobX - knobSize / 2, y: latchY - knobSize / 2, width: knobSize, height: knobSize),
                palette: palette)
        case .planks:
            // A D-shaped pull on two posts.
            let x = fromHinge(width * 0.88)
            let length = height * 0.16
            MetalPainter.bar(
                in: &context,
                rect: CGRect(x: x - width * 0.012, y: latchY - length / 2, width: width * 0.024, height: length),
                palette: palette)
        case .studded:
            // A heavy ring hanging from a round plate.
            let x = fromHinge(width * 0.8)
            let plate = width * 0.11
            MetalPainter.knob(
                in: &context, rect: CGRect(x: x - plate / 2, y: latchY - plate, width: plate, height: plate),
                palette: palette)
            let ring = width * 0.14
            MetalPainter.ring(
                in: &context, rect: CGRect(x: x - ring / 2, y: latchY - plate * 0.45, width: ring, height: ring),
                thickness: max(width * 0.018, 4), palette: palette)
        case .slab:
            // A long vertical bar.
            let x = fromHinge(width * 0.86)
            let length = height * 0.34
            MetalPainter.bar(
                in: &context,
                rect: CGRect(x: x - width * 0.012, y: latchY - length / 2, width: width * 0.024, height: length),
                palette: palette)
        }
    }

    private func keyhole(in context: inout GraphicsContext, at point: CGPoint) {
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)), with: .color(.black))
        context.fill(Path(CGRect(x: point.x - 1.2, y: point.y, width: 2.4, height: 6)), with: .color(.black))
    }
}

/// Faint, slightly wavy vertical grain lines. Seeded, so the door looks the same every time.
enum WoodGrain {
    static func paint(
        in context: inout GraphicsContext, rect: CGRect, color: Color, seed: UInt32, strength: Double = 1
    ) {
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
                let progress = (y - rect.minY) / max(rect.height, 1)
                path.addLine(to: CGPoint(x: baseX + amplitude * sin(phase + waves * progress * .pi * 2), y: y))
            }
            context.stroke(
                path, with: .color(color.opacity((0.08 + 0.14 * Double(random.unit())) * strength)),
                lineWidth: 0.6 + CGFloat(random.unit()) * 1.4)
        }
    }
}

/// Door hardware in the chosen metal.
enum MetalPainter {
    private static func gradient(_ palette: DoorPalette) -> Gradient {
        Gradient(colors: [
            palette.metal.mix(with: .white, by: palette.metalShine * 0.6), palette.metal,
            palette.metal.mix(with: .black, by: 0.35),
        ])
    }

    static func plate(in context: inout GraphicsContext, rect: CGRect, palette: DoorPalette, screws: Bool = true) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 2, x: 1, y: 1.5))
            layer.fill(
                Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.2),
                with: .linearGradient(
                    gradient(palette), startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        }
        guard screws else { return }
        let screw = min(rect.width * 0.32, 5)
        for fraction in [0.2, 0.8] {
            let center = CGPoint(x: rect.midX, y: rect.minY + rect.height * fraction)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - screw / 2, y: center.y - screw / 2, width: screw, height: screw)),
                with: .color(palette.metal.mix(with: .black, by: 0.5)))
        }
    }

    static func knob(in context: inout GraphicsContext, rect: CGRect, palette: DoorPalette) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 3, x: 1.5, y: 2.5))
            layer.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [
                        palette.metal.mix(with: .white, by: 0.2 + palette.metalShine * 0.6), palette.metal,
                        palette.metal.mix(with: .black, by: 0.4),
                    ]),
                    center: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.3),
                    startRadius: 0, endRadius: rect.width * 0.75))
        }
    }

    /// A handle bar with a post at each end.
    static func bar(in context: inout GraphicsContext, rect: CGRect, palette: DoorPalette) {
        let post = rect.width * 1.4
        for y in [rect.minY + post * 0.6, rect.maxY - post * 0.6] {
            knob(
                in: &context, rect: CGRect(x: rect.midX - post / 2, y: y - post / 2, width: post, height: post),
                palette: palette)
        }
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 4, x: 3, y: 4))
            layer.fill(
                Path(roundedRect: rect, cornerRadius: rect.width / 2),
                with: .linearGradient(
                    gradient(palette), startPoint: CGPoint(x: rect.minX, y: rect.midY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
        }
    }

    static func ring(in context: inout GraphicsContext, rect: CGRect, thickness: CGFloat, palette: DoorPalette) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 3, x: 1.5, y: 3))
            layer.stroke(
                Path(ellipseIn: rect),
                with: .linearGradient(
                    gradient(palette), startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)), lineWidth: thickness)
        }
    }

    /// A long strap hinge from the hinge edge, tapering to a point, with rivets.
    static func strap(
        in context: inout GraphicsContext, from origin: CGPoint, length: CGFloat, thickness: CGFloat,
        direction: CGFloat, palette: DoorPalette
    ) {
        var path = Path()
        let tip = origin.x + direction * length
        let taperStart = origin.x + direction * length * 0.82
        path.move(to: CGPoint(x: origin.x, y: origin.y - thickness / 2))
        path.addLine(to: CGPoint(x: taperStart, y: origin.y - thickness / 2))
        path.addLine(to: CGPoint(x: tip, y: origin.y))
        path.addLine(to: CGPoint(x: taperStart, y: origin.y + thickness / 2))
        path.addLine(to: CGPoint(x: origin.x, y: origin.y + thickness / 2))
        path.closeSubpath()
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 2, x: 1, y: 2))
            layer.fill(
                path,
                with: .linearGradient(
                    gradient(palette), startPoint: CGPoint(x: origin.x, y: origin.y - thickness / 2),
                    endPoint: CGPoint(x: origin.x, y: origin.y + thickness / 2)))
        }
        let rivet = thickness * 0.38
        for fraction in [0.15, 0.45, 0.72] {
            let x = origin.x + direction * length * fraction
            context.fill(
                Path(ellipseIn: CGRect(x: x - rivet / 2, y: origin.y - rivet / 2, width: rivet, height: rivet)),
                with: .color(palette.metal.mix(with: .black, by: 0.5)))
        }
    }

    /// The hinge barrel: a vertical cylinder straddling the hinge line.
    static func barrel(in context: inout GraphicsContext, rect: CGRect, palette: DoorPalette) {
        let metal = palette.metal
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2))
            layer.fill(
                Path(roundedRect: rect, cornerRadius: rect.width / 2),
                with: .linearGradient(
                    Gradient(colors: [
                        metal.mix(with: .black, by: 0.3), metal.mix(with: .white, by: 0.2 + palette.metalShine * 0.4),
                        metal, metal.mix(with: .black, by: 0.45),
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

#Preview("All doors") {
    HStack(spacing: 12) {
        ForEach(DoorStyle.allCases) { style in
            DoorLeafArt(look: DoorLook(style: style, hardware: style.defaultHardware, scene: .livingRoom))
                .frame(width: 140, height: 210)
        }
    }
    .padding()
}
