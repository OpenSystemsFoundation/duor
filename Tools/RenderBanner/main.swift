// Renders the App Store header and search results artwork from the app's own scene code: the
// living room, stretched wide, with the cat and the dog. No text, so it works in every language.
//
//   make banner   →   appstore/creative/header-21x9.png, appstore/creative/search-3x2.png
import AppKit
import SwiftUI

@MainActor
func render(width: CGFloat, height: CGFloat, to path: String) {
    let view = Canvas { context, size in
        // The room is drawn for a narrow doorway, so draw it in a centre "core" and extend the
        // wall, floor, skirting and floorboards out to the sides.
        let coreWidth = min(size.width, size.height * 1.15)
        let core = CGRect(x: (size.width - coreWidth) / 2, y: 0, width: coreWidth, height: size.height)
        let horizon = size.height * 0.66
        context.fill(
            Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.97, green: 0.89, blue: 0.72), Color(red: 0.88, green: 0.74, blue: 0.56)]
                ),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: horizon)))
        context.fill(
            Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.45, green: 0.28, blue: 0.16), Color(red: 0.62, green: 0.40, blue: 0.23)]
                ),
                startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: size.height)))
        let vanishing = CGPoint(x: core.midX, y: size.height * 0.3)
        let t = (horizon - vanishing.y) / (size.height - vanishing.y)
        for index in -40...40 {
            let bottomX = core.midX + CGFloat(index) * coreWidth * 0.16
            var seam = Path()
            seam.move(to: CGPoint(x: vanishing.x + (bottomX - vanishing.x) * t, y: horizon))
            seam.addLine(to: CGPoint(x: bottomX, y: size.height))
            context.stroke(seam, with: .color(.black.opacity(0.18)), lineWidth: 1)
        }
        context.fill(
            Path(CGRect(x: 0, y: horizon - size.height * 0.025, width: size.width, height: size.height * 0.025)),
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

        // The cat and the dog meet on the rug.
        func spot(_ distance: CGFloat) -> (y: CGFloat, scale: CGFloat) {
            (size.height * (0.95 - 0.22 * distance), 1 - 0.45 * distance)
        }
        let cat = spot(0.25)
        SceneLife.critter(
            in: &context, at: CGPoint(x: core.midX - coreWidth * 0.22, y: cat.y), facing: 1
        ) {
            SceneLife.cat(in: &$0, size: coreWidth * 0.3 * cat.scale, time: 0.3, pose: .stand)
        }
        let dog = spot(0.2)
        SceneLife.critter(
            in: &context, at: CGPoint(x: core.midX + coreWidth * 0.24, y: dog.y), facing: -1
        ) {
            SceneLife.dog(in: &$0, size: coreWidth * 0.34 * dog.scale, time: 0.12)
        }
    }
    .frame(width: width, height: height)

    let renderer = ImageRenderer(content: view)
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
