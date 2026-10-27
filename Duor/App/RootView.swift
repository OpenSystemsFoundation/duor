import SwiftUI

/// Shows the outside of the door when it's shut and the inside when it's open. The door opens by
/// unfolding the phone, or by swiping (left opens, right closes) on any screen.
struct RootView: View {
    @State private var controller = DoorController()
    @State private var isShowingSettings = false
    @State private var deviceOrientation = DeviceOrientationMonitor()
    @AppStorage(DoorStyle.storageKey) private var style: DoorStyle = .oak
    @AppStorage(HardwareFinish.storageKey) private var hardware: HardwareFinish = .iron
    @AppStorage(InsideScene.storageKey) private var scene: InsideScene = .livingRoom
    @AppStorage(SceneLife.catLoversKey) private var catLovers = false
    @AppStorage("hasOpenedDoor") private var hasOpenedDoor = false
    @AppStorage("swipeMode") private var swipeMode = true

    /// Swiping is the only way in without a hinge, so it can only be turned off on a foldable.
    private var canSwipe: Bool { swipeMode || !controller.hasHardwareHinge }

    private var look: DoorLook { DoorLook(style: style, hardware: hardware, scene: scene) }

    var body: some View {
        // A navigation stack only for its toolbar: on the iPhone Duo the settings button then
        // lives in the system's vertical control lane on the trailing edge.
        NavigationStack {
            door
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Settings", systemImage: "gearshape") {
                            isShowingSettings = true
                        }
                    }
                    .axisBehavior(.verticalPreferred)
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var door: some View {
        GeometryReader { proxy in
            let isInnerDisplay = isInnerDisplay(proxy)
            // A swiped-open door shows its inside on any screen.
            let showsInside = isInnerDisplay || (controller.isSwiped && !controller.isClosed)
            let turns = DeviceFixedTurns.quarterTurns(
                screen: proxy.size, isInnerDisplay: isInnerDisplay, landscape: deviceOrientation.lastLandscape)
            ZStack {
                DeviceFixed(quarterTurns: turns) { _, crease in
                    if showsInside {
                        DoorInsideView(
                            look: look, doorDegrees: controller.angle,
                            hingeDegrees: isInnerDisplay ? controller.hinge?.degrees : nil, crease: crease,
                            isSwiped: controller.isSwiped,
                            simulatesSwing: !isInnerDisplay || Self.isSimulator, catLovers: catLovers,
                            onClose: canSwipe ? { controller.swing(open: false) } : nil)
                    } else {
                        DoorOutsideView(
                            look: look, feedback: controller.feedback, onKnock: controller.knock,
                            onOpen: canSwipe ? { controller.swing(open: true) } : nil)
                    }
                }
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.2), value: showsInside)
            // On the whole screen, not on either face: the face changes mid-swipe as the door opens.
            .contentShape(.rect)
            .simultaneousGesture(swipe(screen: proxy.size, quarterTurns: turns), including: canSwipe ? .all : .subviews)
            .onChange(of: isInnerDisplay, initial: true) { _, isInner in
                controller.screenChanged(isInnerDisplay: isInner)
            }
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
        .overlay(alignment: .bottom) {
            // Without a hinge, swiping is the only way in: say so until the door has been opened.
            if !controller.hasHardwareHinge && !hasOpenedDoor {
                SwipeHint()
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hasOpenedDoor)
        .onChange(of: controller.isClosed) { _, isClosed in
            if !isClosed { hasOpenedDoor = true }
        }
        .onChange(of: canSwipe) { _, canSwipe in
            if !canSwipe { controller.stopSwiping() }
        }
        .sheet(isPresented: $isShowingSettings) {
            // Unfolded: the hinge is open well past halfway (folded or no hinge: four tiles per row).
            SettingsView(
                style: $style, hardware: $hardware, scene: $scene, catLovers: $catLovers, swipeMode: $swipeMode,
                hasHinge: controller.hasHardwareHinge, isUnfolded: (controller.hinge?.degrees ?? 0) > 100)
        }
        // Paused while Settings is open so browsing doesn't creak.
        .onHingeChange(isEnabled: !isShowingSettings) { _, newContext in
            controller.hardwareHingeChanged(
                HingeReading(newContext.hinge, at: ProcessInfo.processInfo.systemUptime)
            )
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

    /// Whether this is the iPhone Duo's inner display, where the door is open as far as the phone.
    ///
    /// The system decides which screen is on (a slightly opened phone often stays on the cover
    /// display), so follow the screen, not the hinge. Only the inner display reports a fold region
    /// (inactive when flat); the cover never does. The interface may also rotate on the inner
    /// display, so the screen's shape can't be used.
    private func isInnerDisplay(_ proxy: GeometryProxy) -> Bool {
        guard controller.hasHardwareHinge else { return false }
        let hasFold = !proxy.reservedRegions(kind: .division, options: .includeInactive).isEmpty
        return hasFold || controller.hinge?.status == .fullyOpen
    }

    /// Swiping the door open or shut, measured across the door (which `DeviceFixed` may have turned).
    private func swipe(screen: CGSize, quarterTurns: Int) -> some Gesture {
        let turn = Double(quarterTurns) * .pi / 2
        let width = quarterTurns.isMultiple(of: 2) ? screen.width : screen.height
        // Screen space to the door's own horizontal axis: undo the door's rotation.
        func across(_ vector: CGSize) -> Double {
            cos(turn) * vector.width + sin(turn) * vector.height
        }
        return DragGesture(minimumDistance: 12)
            .onChanged { value in
                controller.swipeChanged(translation: across(value.translation), width: width)
            }
            .onEnded { value in
                controller.swipeEnded(velocity: across(value.velocity), width: width)
            }
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

/// Tells people without a hinge how to get in.
private struct SwipeHint: View {
    var body: some View {
        Label("Swipe left to open the door", systemImage: "chevron.left.2")
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: .capsule)
            .allowsHitTesting(false)
    }
}

#Preview {
    RootView()
}
