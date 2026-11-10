// Renders the App Store header and search results artwork from the app's own drawing code: the oak
// door swung open on its brass hinges, and through the doorway the living room, drawn wide, where
// the cat and the dog meet on the rug. It's the app's open-door screen, so the search result shows
// what Duor is at a glance. No text, so it works in every language.
//
//   make banner   →   appstore/creative/header-21x9.png, appstore/creative/search-3x2.png
import AppKit
import SwiftUI

let look = DoorLook(style: .oak, hardware: .brass, scene: .livingRoom)

/// The pieces of the picture, from the left: the open leaf, the hinge line, the doorway.
struct Layout {
    let size: CGSize
    var leaf: CGRect { CGRect(x: 0, y: 0, width: min(size.height * 0.5, size.width * 0.25), height: size.height) }
    var hingeX: CGFloat { leaf.maxX }
    var jamb: CGFloat { size.height * 0.02 }
    var casing: CGFloat { size.height * 0.06 }
    var opening: CGRect {
        CGRect(
            x: hingeX + jamb, y: casing, width: size.width - hingeX - jamb - casing, height: size.height - casing)
    }
}

/// The living room, drawn wide into `rect`. The room is drawn for a narrow doorway, so it goes in
/// a centre "core" and the wall, floor, skirting and floorboards are extended to the sides.
func paintRoom(in context: inout GraphicsContext, rect: CGRect) {
    let height = rect.height
    // Wider than about 1.05× the height, the picture (sized by width) reaches down into the cabinet.
    let coreWidth = min(rect.width, height * 0.75)
    let core = CGRect(x: rect.midX - coreWidth / 2, y: rect.minY, width: coreWidth, height: height)
    let horizon = rect.minY + height * 0.66
    context.fill(
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: horizon - rect.minY)),
        with: .linearGradient(
            Gradient(colors: [Color(red: 0.97, green: 0.89, blue: 0.72), Color(red: 0.88, green: 0.74, blue: 0.56)]),
            startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: horizon)))
    context.fill(
        Path(CGRect(x: rect.minX, y: horizon, width: rect.width, height: rect.maxY - horizon)),
        with: .linearGradient(
            Gradient(colors: [Color(red: 0.45, green: 0.28, blue: 0.16), Color(red: 0.62, green: 0.40, blue: 0.23)]),
            startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: rect.maxY)))
    let vanishing = CGPoint(x: core.midX, y: rect.minY + height * 0.3)
    let t = (horizon - vanishing.y) / (rect.maxY - vanishing.y)
    for index in -40...40 {
        let bottomX = core.midX + CGFloat(index) * coreWidth * 0.16
        var seam = Path()
        seam.move(to: CGPoint(x: vanishing.x + (bottomX - vanishing.x) * t, y: horizon))
        seam.addLine(to: CGPoint(x: bottomX, y: rect.maxY))
        context.stroke(seam, with: .color(.black.opacity(0.18)), lineWidth: 1)
    }
    context.fill(
        Path(CGRect(x: rect.minX, y: horizon - height * 0.025, width: rect.width, height: height * 0.025)),
        with: .color(Color(red: 0.95, green: 0.93, blue: 0.88)))
    ScenePainter.livingRoom(in: &context, rect: core)

    // The swaying lamp, at a moment with no visitors in the room.
    var quiet: TimeInterval = 0
    while SceneLife.visit(time: quiet, period: 11, duration: 6, salt: 1) != nil
        || SceneLife.visit(time: quiet, period: 17, duration: 5, salt: 15) != nil
    {
        quiet += 0.25
    }
    SceneLife.livingRoom(in: &context, rect: core, time: quiet)

    // The cat and the dog meet on the rug, sized to fit the doorway's width as well as its height.
    let stage = min(height, rect.width * 0.62)
    func spot(_ distance: CGFloat) -> (y: CGFloat, scale: CGFloat) {
        (rect.minY + height * (0.95 - 0.22 * distance), 1 - 0.45 * distance)
    }
    let cat = spot(0.25)
    SceneLife.critter(in: &context, at: CGPoint(x: core.midX - stage * 0.25, y: cat.y), facing: 1) {
        SceneLife.cat(in: &$0, size: stage * 0.345 * cat.scale, time: 0.3, pose: .stand)
    }
    let dog = spot(0.2)
    SceneLife.critter(in: &context, at: CGPoint(x: core.midX + stage * 0.28, y: dog.y), facing: -1) {
        // At a time where sin(10 t) = 0 the legs are straight: standing, not mid-stride.
        SceneLife.dog(in: &$0, size: stage * 0.39 * dog.scale, time: .pi / 10)
    }
}

/// The door frame around the opening, as in the app's `DoorwayArt`: casing across the top and down
/// the latch side, a thin jamb on the hinge side, and the strike plate.
func paintFrame(in context: inout GraphicsContext, layout: Layout) {
    let size = layout.size
    let opening = layout.opening
    let frame = look.palette.frame
    let left = layout.hingeX
    context.fill(
        Path(CGRect(x: left, y: 0, width: size.width - left, height: layout.casing)),
        with: .linearGradient(
            Gradient(colors: [frame, frame.mix(with: .black, by: 0.12)]), startPoint: .zero,
            endPoint: CGPoint(x: 0, y: layout.casing)))
    context.fill(
        Path(CGRect(x: opening.maxX, y: 0, width: layout.casing, height: size.height)),
        with: .linearGradient(
            Gradient(colors: [frame.mix(with: .black, by: 0.12), frame]),
            startPoint: CGPoint(x: opening.maxX, y: 0), endPoint: CGPoint(x: size.width, y: 0)))
    context.fill(
        Path(CGRect(x: left, y: 0, width: layout.jamb, height: size.height)),
        with: .color(frame.mix(with: .black, by: 0.2)))

    var edge = Path()
    edge.move(to: CGPoint(x: opening.minX, y: opening.maxY))
    edge.addLine(to: CGPoint(x: opening.minX, y: opening.minY))
    edge.addLine(to: CGPoint(x: opening.maxX, y: opening.minY))
    edge.addLine(to: CGPoint(x: opening.maxX, y: opening.maxY))
    context.stroke(edge, with: .color(.black.opacity(0.35)), lineWidth: size.height * 0.004)

    let strikeHeight = size.height * 0.09
    let strike = CGRect(
        x: opening.maxX - layout.casing * 0.08, y: size.height * DoorGeometry.latchHeight - strikeHeight / 2,
        width: layout.casing * 0.42, height: strikeHeight)
    MetalPainter.plate(in: &context, rect: strike, palette: look.palette)
    context.fill(
        Path(
            roundedRect: CGRect(
                x: strike.minX + strike.width * 0.15, y: strike.midY - strikeHeight * 0.12,
                width: strike.width * 0.45, height: strikeHeight * 0.24), cornerRadius: strike.width * 0.06),
        with: .color(.black.opacity(0.8)))

    // Hinge knuckles on the hinge line, as on the crease in the app.
    let barrelWidth = size.height * 0.022
    for center in DoorGeometry.hingeCenters {
        let hinge = size.height * DoorGeometry.hingeHeight
        MetalPainter.barrel(
            in: &context,
            rect: CGRect(
                x: left - barrelWidth / 2, y: size.height * center - hinge * 0.55, width: barrelWidth,
                height: hinge * 1.1),
            palette: look.palette)
    }
}

struct Banner: View {
    let layout: Layout

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.doorShadow
            // Warm light from the room falls on the floor in front of the door.
            RadialGradient(
                colors: [Color(red: 1, green: 0.85, blue: 0.55).opacity(0.35), .clear],
                center: UnitPoint(x: layout.hingeX / layout.size.width, y: 1),
                startRadius: 0, endRadius: layout.size.height * 0.9)
            Canvas { context, _ in
                var room = context
                room.clip(to: Path(layout.opening))
                paintRoom(in: &room, rect: layout.opening)
                paintFrame(in: &context, layout: layout)
            }
            // The leaf, open about 50° toward us on its hinges, showing its inside face.
            DoorLeafArt(look: look, hingeSide: .trailing, face: .inside)
                .frame(width: layout.leaf.width, height: layout.leaf.height)
                .rotation3DEffect(.degrees(50), axis: (x: 0, y: 1, z: 0), anchor: .trailing, perspective: 0.4)
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .environment(\.layoutDirection, .leftToRight)
    }
}

@MainActor
func render(width: CGFloat, height: CGFloat, to path: String) {
    let renderer = ImageRenderer(content: Banner(layout: Layout(size: CGSize(width: width, height: height))))
    renderer.scale = 1
    renderer.isOpaque = true
    guard let image = renderer.cgImage else { fatalError("render failed") }
    // Flatten to RGB with no alpha channel, as the App Store requires.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let flat = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    flat.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let rep = NSBitmapImageRep(cgImage: flat.makeImage()!)
    do {
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    } catch {
        fatalError("could not write \(path): \(error)")
    }
    print(path, image.width, image.height)
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "appstore/creative"
MainActor.assumeIsolated {
    render(width: 3840, height: 1646, to: "\(out)/header-21x9.png")
    render(width: 3840, height: 2560, to: "\(out)/search-3x2.png")
}
