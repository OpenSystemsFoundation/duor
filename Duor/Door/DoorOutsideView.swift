import SwiftUI

/// The outside face of the door, filling the screen while it's shut. Tap to knock. (Swiping to
/// open is handled by `RootView`, since the door slides off the screen as it opens.)
struct DoorOutsideView: View {
    let look: DoorLook
    /// Latest door feedback, for the knock and close shakes.
    let feedback: DoorFeedback?
    /// Called with where on the door the knock landed.
    let onKnock: (KnockSpot) -> Void
    /// Opens the door without a swipe (accessibility). Nil when swiping is off.
    var onOpen: (() -> Void)?

    @State private var dents: [KnockDent] = []
    @State private var size: CGSize = .zero

    var body: some View {
        DoorLeafArt(look: look, hingeSide: .leading, face: .outside)
            .overlay {
                ForEach(dents) { dent in
                    KnockDentView()
                        .position(dent.location)
                }
            }
            .keyframeAnimator(initialValue: 0.0, trigger: feedback) { content, offset in
                content.visualEffect { content, proxy in
                    // The door fills the screen, so a plain sideways shake would uncover the screen edge.
                    // Zoom in just enough to cover the shift: each side grows by |offset| (+1 pt for hairlines).
                    let overscan = offset == 0 ? 0 : (2 * abs(offset) + 2) / max(proxy.size.width, 1)
                    return
                        content
                        .scaleEffect(1 + overscan)
                        .offset(x: offset)
                }
            } keyframes: { _ in
                // The door rattles in its frame: barely for a knock, hard for a slam.
                let amplitude = Self.shakeAmplitude(for: feedback?.kind)
                CubicKeyframe(-amplitude, duration: 0.04)
                CubicKeyframe(amplitude * 0.7, duration: 0.06)
                CubicKeyframe(-amplitude * 0.4, duration: 0.07)
                CubicKeyframe(amplitude * 0.15, duration: 0.08)
                CubicKeyframe(0, duration: 0.1)
            }
            .ignoresSafeArea()
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: {
                size = $0
            }
            .contentShape(.rect)
            .gesture(
                SpatialTapGesture().onEnded { tap in
                    knock(at: tap.location)
                }
            )
            // The door is physical: never mirror it for right-to-left languages.
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement()
            .accessibilityLabel(Text("Closed door"))
            .accessibilityHint(Text("Double-tap to knock."))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onKnock(.center) }
            .accessibilityActions {
                if let onOpen {
                    Button("Open door", action: onOpen)
                }
            }
    }

    private func knock(at location: CGPoint) {
        let dent = KnockDent(location: location)
        dents.append(dent)
        onKnock(KnockSpot(tap: location, in: size))
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            dents.removeAll { $0.id == dent.id }
        }
    }

    private static func shakeAmplitude(for kind: DoorFeedback.Kind?) -> Double {
        switch kind {
        case .knock: 1.5
        case .closed(.firm): 3
        case .closed(.slam): 8
        default: 0
        }
    }
}

private struct KnockDent: Identifiable {
    let id = UUID()
    let location: CGPoint
}

/// A soft shadow that blooms where the knuckle hit, then fades.
private struct KnockDentView: View {
    @State private var isSettled = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(colors: [.black.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 50)
            )
            .frame(width: 100, height: 100)
            .scaleEffect(isSettled ? 1.3 : 0.4)
            .opacity(isSettled ? 0 : 1)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    isSettled = true
                }
            }
    }
}

extension KnockSpot {
    /// Where a tap at `location` lands on a door leaf of `size`. The door is never mirrored, so x
    /// runs from the hinge (leading) edge to the latch edge. The middle until the size is known.
    init(tap location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            self = .center
            return
        }
        self.init(x: Float(location.x / size.width), y: Float(location.y / size.height))
    }
}

#Preview {
    DoorOutsideView(look: DoorLook(style: .barn, hardware: .iron, scene: .forest), feedback: nil, onKnock: { _ in })
}
