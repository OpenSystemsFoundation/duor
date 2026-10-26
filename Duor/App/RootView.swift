import SwiftUI

/// Shows the outside of the door when folded (cover display) and the inside when open.
struct RootView: View {
    @State private var controller = DoorController()
    @State private var isShowingSettings = false
    @State private var simulatedAngle: Double = 0
    @State private var deviceOrientation = DeviceOrientationMonitor()
    @AppStorage(DoorStyle.storageKey) private var style: DoorStyle = .oak
    @AppStorage(HardwareFinish.storageKey) private var hardware: HardwareFinish = .iron
    @AppStorage(InsideScene.storageKey) private var scene: InsideScene = .livingRoom

    private var look: DoorLook { DoorLook(style: style, hardware: hardware, scene: scene) }

    var body: some View {
        GeometryReader { proxy in
            let showsInside = showsInside(proxy)
            let turns = DeviceFixedTurns.quarterTurns(
                screen: proxy.size, isInnerDisplay: showsInside && controller.hasHardwareHinge,
                device: deviceOrientation.orientation)
            ZStack(alignment: .topTrailing) {
                DeviceFixed(quarterTurns: turns) { _, crease in
                    if showsInside {
                        DoorInsideView(
                            look: look, hingeDegrees: controller.angle, crease: crease,
                            simulatesSwing: !controller.hasHardwareHinge || Self.isSimulator)
                    } else {
                        DoorOutsideView(look: look, feedback: controller.feedback, onKnock: controller.knock)
                    }
                }
                .transition(.opacity)

                Button("Settings", systemImage: "gearshape") {
                    isShowingSettings = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .padding()
            }
            .animation(.easeInOut(duration: 0.2), value: showsInside)
        }
        // Dark, never white, if anything ever shows behind the door (crossfades, shakes).
        .background(Color(red: 0.1, green: 0.07, blue: 0.05).ignoresSafeArea())
        .sensoryFeedback(trigger: controller.feedback) { _, feedback in
            switch feedback?.kind {
            case .knock: .impact(weight: .heavy, intensity: 0.9)
            case .unlatch: .impact(weight: .light, intensity: 0.7)
            case .openStop: .impact(weight: .medium, intensity: 0.5)
            case .closed(.gentle): .impact(weight: .light, intensity: 0.8)
            case .closed(.firm): .impact(weight: .medium, intensity: 1)
            case .closed(.slam): .impact(weight: .heavy, intensity: 1)
            case nil: nil
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !controller.hasHardwareHinge {
                SimulatedHingeControl(degrees: $simulatedAngle)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(style: $style, hardware: $hardware, scene: $scene)
        }
        // Paused while Settings is open so browsing doesn't creak.
        .onHingeChange(isEnabled: !isShowingSettings) { _, newContext in
            controller.hardwareHingeChanged(
                HingeReading(newContext.hinge, at: ProcessInfo.processInfo.systemUptime)
            )
        }
        .onChange(of: simulatedAngle) { _, degrees in
            controller.simulatedHingeChanged(degrees: degrees)
        }
        .task(id: look) {
            controller.apply(sound: look.soundProfile)
        }
        .onAppear {
            deviceOrientation.start()
        }
        #if DEBUG
            // UI testing and screenshots: launch with `-showSettings YES`.
            .task {
                guard UserDefaults.standard.bool(forKey: "showSettings") else { return }
                try? await Task.sleep(for: .milliseconds(600))
                isShowingSettings = true
            }
        #endif
    }

    /// Which face of the door to draw.
    ///
    /// With a real hinge the system decides which screen is on (a slightly opened phone often stays
    /// on the cover display), so follow the screen. Only the inner display reports a fold region
    /// (inactive when flat); the cover never does. The interface may also rotate on the inner
    /// display, so the screen's shape can't be used. Without a hinge there is one screen, so
    /// follow the simulated hinge instead.
    private func showsInside(_ proxy: GeometryProxy) -> Bool {
        guard controller.hasHardwareHinge else { return !controller.isClosed }
        let hasFold = !proxy.reservedRegions(kind: .division, options: .includeInactive).isEmpty
        return hasFold || controller.reading?.status == .fullyOpen
    }

    /// In the Simulator nothing folds physically, so the door swings on screen.
    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
            true
        #else
            false
        #endif
    }
}

/// Stand-in for the hinge on devices that don't have one (and in Previews).
private struct SimulatedHingeControl: View {
    @Binding var degrees: Double

    var body: some View {
        VStack(spacing: 4) {
            Text("No hinge detected. Drag to open the door.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Slider(value: $degrees, in: 0...180) {
                Text("Hinge angle")
            }
        }
        .padding()
        .background(.regularMaterial)
    }
}

#Preview {
    RootView()
}
