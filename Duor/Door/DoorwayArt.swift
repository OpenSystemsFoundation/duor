import SwiftUI

/// The fixed half of the inner display: the door frame, and the scene you see through it.
///
/// The hinge jamb is on the leading edge (against the crease), the latch jamb with its
/// strike plate on the trailing edge. `light` (0...1) is how much of the room is lit by the
/// open door: dark when the door has just cracked open, warm and bright when fully open.
struct DoorwayArt: View {
    let look: DoorLook
    var light: Double
    /// Add a cat to the scene.
    var catLovers = false

    var body: some View {
        // Three layers: the still scene, its moving life (passing behind the frame), then the
        // darkness and the frame on top. Only the life layer redraws every frame.
        ZStack {
            Canvas { context, size in
                ScenePainter.paint(look.scene, in: &context, rect: Self.opening(in: size))
            }
            // Paused while the door is too shut to see in (saves battery).
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: light < 0.02)) { timeline in
                Canvas { context, size in
                    SceneLife.paint(
                        look.scene, in: &context, rect: Self.opening(in: size),
                        time: timeline.date.timeIntervalSinceReferenceDate, catLovers: catLovers)
                }
            }
            Canvas { context, size in
                paintFrame(in: &context, size: size)
            }
        }
    }

    private static func opening(in size: CGSize) -> CGRect {
        let casing = size.width * 0.08
        let hingeJamb = size.width * 0.03
        return CGRect(x: hingeJamb, y: casing, width: size.width - hingeJamb - casing, height: size.height - casing)
    }

    private func paintFrame(in context: inout GraphicsContext, size: CGSize) {
        let casing = size.width * 0.08
        let hingeJamb = size.width * 0.03
        let opening = Self.opening(in: size)
        let palette = look.palette

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
        MetalPainter.plate(in: &context, rect: strike, palette: palette)
        context.fill(
            Path(
                roundedRect: CGRect(
                    x: strike.minX + strike.width * 0.15, y: strike.midY - strikeHeight * 0.12,
                    width: strike.width * 0.45, height: strikeHeight * 0.24), cornerRadius: 1.5),
            with: .color(.black.opacity(0.8)))
    }
}

/// How lit the scene beyond the door is, for how open the door is (0...1): dark when just cracked
/// open, fully lit from about two-thirds open.
enum DoorwayLight {
    static func amount(openness: Double) -> Double {
        let t = min(max((openness - 0.06) / 0.6, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

#Preview {
    DoorwayArt(look: DoorLook(style: .oak, hardware: .brass, scene: .beach), light: 1)
        .ignoresSafeArea()
}

extension View {
    /// Describes the open door for VoiceOver, with an action to close it when swiping is on.
    func openDoorAccessibility(degrees: Double, onClose: (() -> Void)?) -> some View {
        accessibilityElement(children: .ignore)
            // Not "Open door": that's the action on the closed door, and translates differently.
            .accessibilityLabel(Text("Doorway"))
            .accessibilityValue(Text("Open \(Int(degrees)) degrees"))
            .accessibilityActions {
                if let onClose {
                    Button("Close door", action: onClose)
                }
            }
    }
}
