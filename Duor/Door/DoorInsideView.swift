import SwiftUI

/// The inner display while the phone is open.
///
/// On a real iPhone Duo the phone half that swings open *is* the door leaf, so its screen shows the
/// leaf's inside face and stays still: the physical motion does the animating. Where nothing moves
/// physically (the Simulator, phones without a hinge), the leaf swings on screen at the true angle.
/// The fixed half shows the doorway and the room beyond, which lights up as the door opens.
/// The hinges sit on the crease.
struct DoorInsideView: View {
    let style: DoorStyle
    /// Physical hinge angle: 0 folded, 180 flat.
    let hingeDegrees: Double
    /// The fold crease in this view's coordinates, if the system reports one.
    var crease: CGRect?
    /// Swing the leaf on screen because nothing swings physically.
    var simulatesSwing = false

    private var openness: Double { min(max(hingeDegrees / 180, 0), 1) }
    /// How lit the room is: dark when just cracked open, fully lit from about two-thirds open.
    private var light: Double {
        let t = min(max((openness - 0.06) / 0.6, 0), 1)
        return t * t * (3 - 2 * t)
    }

    var body: some View {
        GeometryReader { proxy in
            let split = CreaseSplit(size: proxy.size, crease: crease)
            ZStack(alignment: .topLeading) {
                // The crease, when the system reserves one, is the shadowed gap between door and frame.
                Color(red: 0.1, green: 0.07, blue: 0.05)

                DoorwayArt(palette: style.palette, light: light)
                    .frame(width: split.doorway.width, height: split.doorway.height)
                    .offset(x: split.doorway.minX, y: split.doorway.minY)

                leaf
                    .frame(width: split.leaf.width, height: split.leaf.height)
                    .offset(x: split.leaf.minX, y: split.leaf.minY)

                HingeBarrels(palette: style.palette, split: split)
                    .allowsHitTesting(false)
            }
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: hingeDegrees)
        }
        .ignoresSafeArea()
        // The door is physical: never mirror it for right-to-left languages.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Open door"))
        .accessibilityValue(Text("Open \(Int(hingeDegrees)) degrees"))
    }

    /// The inside face of the leaf: shaded near the hinge while barely open, lit by the room once open.
    private var leaf: some View {
        DoorLeafArt(palette: style.palette, hingeSide: .trailing, showsPeephole: false)
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55 * (1 - light))], startPoint: .leading, endPoint: .trailing)
            }
            .overlay { Color.black.opacity(0.3 * (1 - light)) }
            // The leaf stands at (180° − hinge angle) to the doorway: edge-on at 90°, flat at 180°.
            .rotation3DEffect(
                .degrees(simulatesSwing ? 180 - hingeDegrees : 0), axis: (x: 0, y: 1, z: 0), anchor: .trailing,
                perspective: 0.4)
    }
}

/// Where the fold is, and the two halves on either side of it.
private struct CreaseSplit {
    let creaseX: CGFloat
    let leaf: CGRect
    let doorway: CGRect

    init(size: CGSize, crease: CGRect?) {
        // Without a reported fold (flat, or no hinge), split down the middle.
        let fold = crease.flatMap { $0.height > $0.width ? $0 : nil }
        creaseX = fold?.midX ?? size.width / 2
        let gap = fold?.width ?? 0
        leaf = CGRect(x: 0, y: 0, width: creaseX - gap / 2, height: size.height)
        doorway = CGRect(x: creaseX + gap / 2, y: 0, width: size.width - creaseX - gap / 2, height: size.height)
    }
}

/// The hinges, drawn exactly on the crease so the physical hinge looks like the door's hinge:
/// a strap from the leaf across the gap to the frame, with the knuckle barrel on the hinge line.
private struct HingeBarrels: View {
    let palette: DoorPalette
    let split: CreaseSplit

    var body: some View {
        Canvas { context, size in
            let barrelWidth = max(size.width * 0.012, 12)
            let strapOverlap = max(size.width * 0.02, 14)
            for center in DoorGeometry.hingeCenters {
                let height = size.height * DoorGeometry.hingeHeight
                let y = size.height * center
                if split.doorway.minX > split.leaf.maxX {
                    let strap = CGRect(
                        x: split.leaf.maxX - strapOverlap, y: y - height * 0.4,
                        width: split.doorway.minX - split.leaf.maxX + strapOverlap * 2, height: height * 0.8)
                    MetalPainter.plate(in: &context, rect: strap, metal: palette.metal, screws: false)
                }
                MetalPainter.barrel(
                    in: &context,
                    rect: CGRect(
                        x: split.creaseX - barrelWidth / 2, y: y - height * 0.55, width: barrelWidth,
                        height: height * 1.1),
                    metal: palette.metal)
            }
        }
    }
}

#Preview("Half open") {
    DoorInsideView(style: .oakWithIronHinges, hingeDegrees: 130, simulatesSwing: true)
}

#Preview("Flat") {
    DoorInsideView(style: .oakWithIronHinges, hingeDegrees: 180)
}
