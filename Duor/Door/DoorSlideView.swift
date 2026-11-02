import SwiftUI

/// A single flat screen: the cover display, or a phone without a hinge.
///
/// The doorframe fills the screen and the door lies on top of it. Swiping the door open slides it
/// off the screen's leading edge, lifted a little off the frame, until only the doorway is left.
/// Swiping back slides it over the frame again until it lands, shut. (The inner display swings
/// the door on its hinge instead, because there one half of the phone is the door.)
struct DoorSlideView: View {
    let look: DoorLook
    /// Door angle: 0 shut, 180 flat open (slid off the screen).
    let doorDegrees: Double
    /// Latest door feedback, for the knock and close shakes.
    let feedback: DoorFeedback?
    /// Add a cat to the scene beyond the door.
    var catLovers = false
    let onKnock: (KnockSpot) -> Void
    /// Opens the door without a swipe (accessibility). Nil when swiping is off.
    var onOpen: (() -> Void)?
    /// Closes the door without a swipe (accessibility). Nil when swiping is off.
    var onClose: (() -> Void)?

    var body: some View {
        let slide = DoorSlide(degrees: doorDegrees)
        GeometryReader { proxy in
            ZStack {
                DoorwayArt(look: look, light: DoorwayLight.amount(openness: slide.uncovered), catLovers: catLovers)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Open door"))
                    .accessibilityValue(Text("Open \(Int(doorDegrees)) degrees"))
                    .accessibilityActions {
                        if let onClose {
                            Button("Close door", action: onClose)
                        }
                    }
                    .accessibilityHidden(!slide.isOpen)

                DoorOutsideView(look: look, feedback: feedback, onKnock: onKnock, onOpen: onOpen)
                    // The shadow the lifted door casts on the frame beside it.
                    .background(alignment: .trailing) {
                        LinearGradient(
                            colors: [.black.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: DoorSlide.shadowWidth)
                        .offset(x: DoorSlide.shadowWidth)
                        .opacity(slide.isOpen ? 1 : 0)
                        .allowsHitTesting(false)
                    }
                    .scaleEffect(slide.scale)
                    .offset(x: slide.offset(width: proxy.size.width))
                    .accessibilityHidden(slide.isOpen)
            }
            // Smooths out swipe and fling updates; the door still tracks the finger closely.
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.86), value: doorDegrees)
        }
        .ignoresSafeArea()
        // The door is physical: never mirror it for right-to-left languages.
        .environment(\.layoutDirection, .leftToRight)
    }
}

#Preview("Sliding open") {
    DoorSlideView(
        look: DoorLook(style: .cottage, hardware: .brass, scene: .beach), doorDegrees: 70, feedback: nil,
        onKnock: { _ in })
}
