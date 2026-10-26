import SwiftUI

/// The inner display while the phone is open.
///
/// The fixed half shows the doorway and the scene beyond, which lights up as the door opens.
/// The hinges sit on the crease. The leaf has weight: it follows the hinge on a spring, so it
/// lags a little, bounces off the stop, and swings open from shut when the view appears.
///
/// On a real iPhone Duo the phone half that swings open *is* the door leaf, so only that lag and
/// bounce are drawn on top of the physical motion. Where nothing moves physically (the Simulator,
/// phones without a hinge) the whole swing is drawn.
struct DoorInsideView: View {
    let look: DoorLook
    /// Physical hinge angle: 0 folded, 180 flat.
    let hingeDegrees: Double
    /// The fold crease in this view's coordinates, if the system reports one.
    var crease: CGRect?
    /// Draw the whole swing because nothing swings physically.
    var simulatesSwing = false

    @State private var hasSwungIn = false

    private var openness: Double { min(max(hingeDegrees / 180, 0), 1) }
    /// How lit the scene is: dark when just cracked open, fully lit from about two-thirds open.
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

                DoorwayArt(look: look, light: light)
                    .frame(width: split.doorway.width, height: split.doorway.height)
                    .offset(x: split.doorway.minX, y: split.doorway.minY)
                    .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: hingeDegrees)

                SwingingLeaf(
                    look: look, light: light, physicalDegrees: hingeDegrees,
                    drawnDegrees: hasSwungIn ? hingeDegrees : 0, simulatesSwing: simulatesSwing
                )
                .frame(width: split.leaf.width, height: split.leaf.height)
                .offset(x: split.leaf.minX, y: split.leaf.minY)
                // Weight: a slightly bouncy spring, retargeted smoothly by every hinge update.
                .animation(.spring(response: 0.42, dampingFraction: 0.58), value: hingeDegrees)

                HingeBarrels(palette: look.palette, split: split)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        // The door is physical: never mirror it for right-to-left languages.
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.6)) {
                hasSwungIn = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Open door"))
        .accessibilityValue(Text("Open \(Int(hingeDegrees)) degrees"))
    }
}

/// The door leaf, rotated about its hinge edge to wherever the spring has carried it.
private struct SwingingLeaf: View, Animatable {
    let look: DoorLook
    let light: Double
    /// Where the phone half physically is.
    let physicalDegrees: Double
    /// Where the drawn door is: follows the physical angle with weight. Animated.
    var drawnDegrees: Double
    let simulatesSwing: Bool

    var animatableData: Double {
        get { drawnDegrees }
        set { drawnDegrees = newValue }
    }

    /// Degrees the leaf turns away from its own half of the screen, about the hinge edge.
    private var rotation: Double {
        // Without physical motion the leaf stands at (180° − angle) to the doorway:
        // across the doorway when shut, edge-on at 90°, flat at 180°.
        if simulatesSwing { return 180 - drawnDegrees }
        // On a real Duo the screen half already stands at the physical angle: draw only the lag.
        return min(max(physicalDegrees - drawnDegrees, -30), 85)
    }

    var body: some View {
        // Past 90° we see the other side of the door: its outside face, in the shadow of the frame.
        let showsOutside = rotation > 90
        ZStack {
            DoorLeafArt(look: look, hingeSide: .trailing, face: .inside)
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55 * (1 - light))], startPoint: .leading,
                        endPoint: .trailing)
                }
                .overlay { Color.black.opacity(0.3 * (1 - light)) }
                .opacity(showsOutside ? 0 : 1)
            DoorLeafArt(look: look, hingeSide: .trailing, face: .outside)
                .overlay { Color.black.opacity(0.3) }
                .opacity(showsOutside ? 1 : 0)
        }
        .rotation3DEffect(
            .degrees(rotation), axis: (x: 0, y: 1, z: 0), anchor: .trailing, perspective: 0.4)
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
                    MetalPainter.plate(in: &context, rect: strap, palette: palette, screws: false)
                }
                MetalPainter.barrel(
                    in: &context,
                    rect: CGRect(
                        x: split.creaseX - barrelWidth / 2, y: y - height * 0.55, width: barrelWidth,
                        height: height * 1.1),
                    palette: palette)
            }
        }
    }
}

#Preview("Half open") {
    DoorInsideView(
        look: DoorLook(style: .cottage, hardware: .brass, scene: .beach), hingeDegrees: 130, simulatesSwing: true)
}

#Preview("Flat") {
    DoorInsideView(look: DoorLook(style: .castle, hardware: .bronze, scene: .space), hingeDegrees: 180)
}
