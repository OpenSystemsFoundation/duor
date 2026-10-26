import SwiftUI

/// The outside face of the door, shown on the cover display while folded. Tap to knock.
struct DoorOutsideView: View {
    let style: DoorStyle
    /// Latest door feedback, for the knock and close shakes.
    let feedback: DoorFeedback?
    let onKnock: () -> Void

    @State private var dents: [KnockDent] = []

    var body: some View {
        DoorLeafArt(palette: style.palette, hingeSide: .leading)
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
            .accessibilityHint(Text("Double-tap to knock. Unfold your phone to open the door."))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onKnock() }
    }

    private func knock(at location: CGPoint) {
        let dent = KnockDent(location: location)
        dents.append(dent)
        onKnock()
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

#Preview {
    DoorOutsideView(style: .oakWithIronHinges, feedback: nil, onKnock: {})
}
