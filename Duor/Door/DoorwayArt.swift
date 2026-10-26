import SwiftUI

/// The fixed half of the inner display: the door frame, and the room you see through it.
///
/// The hinge jamb is on the leading edge (against the crease), the latch jamb with its
/// strike plate on the trailing edge. `light` (0...1) is how much of the room is lit by the
/// open door: dark when the door has just cracked open, warm and bright when fully open.
struct DoorwayArt: View {
    let palette: DoorPalette
    var light: Double

    var body: some View {
        Canvas { context, size in
            let casing = size.width * 0.08
            let hingeJamb = size.width * 0.03
            let opening = CGRect(
                x: hingeJamb, y: casing, width: size.width - hingeJamb - casing, height: size.height - casing)

            RoomPainter.paint(in: &context, rect: opening)

            // Dark until the door lets light in.
            context.fill(Path(opening), with: .color(.black.opacity(0.88 * (1 - light))))

            // Frame: casing across the top and down the latch side, a thin jamb on the hinge side.
            let frame = palette.frame
            context.fill(
                Path(CGRect(x: 0, y: 0, width: size.width, height: casing)),
                with: .linearGradient(
                    Gradient(colors: [frame, frame.mix(with: .black, by: 0.12)]), startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: casing)))
            context.fill(
                Path(CGRect(x: size.width - casing, y: 0, width: casing, height: size.height)),
                with: .linearGradient(
                    Gradient(colors: [frame.mix(with: .black, by: 0.12), frame]),
                    startPoint: CGPoint(x: size.width - casing, y: 0), endPoint: CGPoint(x: size.width, y: 0)))
            context.fill(
                Path(CGRect(x: 0, y: 0, width: hingeJamb, height: size.height)),
                with: .color(frame.mix(with: .black, by: 0.2)))

            // Inner shadow where the frame meets the opening.
            var edge = Path()
            edge.move(to: CGPoint(x: opening.minX, y: opening.maxY))
            edge.addLine(to: CGPoint(x: opening.minX, y: opening.minY))
            edge.addLine(to: CGPoint(x: opening.maxX, y: opening.minY))
            edge.addLine(to: CGPoint(x: opening.maxX, y: opening.maxY))
            context.stroke(edge, with: .color(.black.opacity(0.35)), lineWidth: 3)

            // Strike plate at knob height, where the latch bolt goes.
            let strikeHeight = size.height * 0.09
            let strike = CGRect(
                x: opening.maxX - casing * 0.08, y: size.height * DoorGeometry.latchHeight - strikeHeight / 2,
                width: casing * 0.42, height: strikeHeight)
            MetalPainter.plate(in: &context, rect: strike, metal: palette.metal)
            context.fill(
                Path(
                    roundedRect: CGRect(
                        x: strike.minX + strike.width * 0.15, y: strike.midY - strikeHeight * 0.12,
                        width: strike.width * 0.45, height: strikeHeight * 0.24), cornerRadius: 1.5),
                with: .color(.black.opacity(0.8)))
        }
    }
}

/// A warm little room: lamp, picture, floorboards, rug.
private enum RoomPainter {
    static func paint(in context: inout GraphicsContext, rect: CGRect) {
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
        var cord = Path()
        cord.move(to: CGPoint(x: lamp.x, y: rect.minY))
        cord.addLine(to: CGPoint(x: lamp.x, y: lamp.y - rect.width * 0.04))
        context.stroke(cord, with: .color(.black.opacity(0.6)), lineWidth: 1.5)
        var shade = Path()
        let shadeWidth = rect.width * 0.16
        shade.move(to: CGPoint(x: lamp.x - shadeWidth * 0.25, y: lamp.y - rect.width * 0.04))
        shade.addLine(to: CGPoint(x: lamp.x + shadeWidth * 0.25, y: lamp.y - rect.width * 0.04))
        shade.addLine(to: CGPoint(x: lamp.x + shadeWidth / 2, y: lamp.y + rect.width * 0.03))
        shade.addLine(to: CGPoint(x: lamp.x - shadeWidth / 2, y: lamp.y + rect.width * 0.03))
        shade.closeSubpath()
        context.fill(shade, with: .color(Color(red: 0.2, green: 0.35, blue: 0.3)))
    }
}

#Preview {
    DoorwayArt(palette: DoorStyle.oakWithIronHinges.palette, light: 1)
        .ignoresSafeArea()
}
