import SwiftUI

/// Shows the door. On the iPhone Duo's inner display it swings open with the phone; on a single
/// screen (the cover display, or a phone without a hinge) a swipe slides it off the doorframe.
/// Swiping left opens, swiping right closes, on any screen.
struct RootView: View {
    @State private var controller = DoorController()
    @State private var isShowingSettings = false
    /// Whether the window fills the screen (not in Split View), from `DoorHostingController`.
    var windowFit = WindowFit()
    /// The screen the door is on, as decided in `door`. Places the settings button.
    @State private var screen: DoorScreen = .single
    private var isOnInnerDisplay: Bool { screen == .inner }
    @State private var deviceOrientation = DeviceOrientationMonitor()
    @State private var settings = DoorSettings()

    /// Off by default on a foldable (the hinge opens the door); always on without a hinge or in Split View.
    private var canSwipe: Bool {
        // In Split View the phone is already open, so only a swipe can open the door.
        screen == .window || settings.isSwipeOn(hasHinge: controller.hasHardwareHinge)
    }

    private var look: DoorLook { settings.look }

    var body: some View {
        // A navigation stack only for its toolbar: on the iPhone Duo's inner display the settings
        // button then lives in the system's vertical control lane on the trailing edge. Anywhere
        // else it stays in the top bar: on the cover display that edge is the door's latch side,
        // and the lane would sit over the handle and take its taps.
        NavigationStack {
            door
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Settings", systemImage: "gearshape") {
                            isShowingSettings = true
                        }
                    }
                    .axisBehavior(isOnInnerDisplay ? .verticalPreferred : .horizontalOnly)
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
                // No vertical lane at all off the inner display: it covers the cover display's
                // latch edge (and the handle) even with nothing in it.
                .toolbarVerticalBehavior(isOnInnerDisplay ? .automatic : .disabled)
        }
    }

    private var door: some View {
        GeometryReader { proxy in
            let screen = doorScreen(proxy)
            let isInnerDisplay = screen == .inner
            let turns = DeviceFixedTurns.quarterTurns(
                screen: proxy.size, isInnerDisplay: isInnerDisplay, hasHinge: controller.hasHardwareHinge,
                landscape: deviceOrientation.lastLandscape)
            ZStack {
                DeviceFixed(quarterTurns: turns) { _, crease in
                    if isInnerDisplay {
                        // One half of the phone is the door: it swings on the hinge.
                        DoorInsideView(
                            look: look, doorDegrees: controller.angle, hingeDegrees: controller.hinge?.degrees,
                            crease: crease, isSwiped: controller.isSwiped, simulatesSwing: Self.isSimulator,
                            catLovers: settings.catLovers, onClose: canSwipe ? { controller.swing(open: false) } : nil)
                    } else {
                        // One flat screen: a swipe slides the door off the doorframe and back.
                        DoorSlideView(
                            look: look, doorDegrees: controller.isSwiped ? controller.angle : 0,
                            feedback: controller.feedback, catLovers: settings.catLovers,
                            onKnock: controller.knock(at:),
                            onOpen: canSwipe ? { controller.swing(open: true) } : nil,
                            onClose: canSwipe ? { controller.swing(open: false) } : nil)
                    }
                }
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.2), value: isInnerDisplay)
            // On the whole screen, not on the door: the door slides off the screen mid-swipe.
            .contentShape(.rect)
            .simultaneousGesture(swipe(screen: proxy.size, quarterTurns: turns), including: canSwipe ? .all : .subviews)
            .onChange(of: screen, initial: true) { _, screen in
                controller.screenChanged(to: screen)
                self.screen = screen
            }
        }
        // Dark, never white, if anything ever shows behind the door (crossfades, shakes).
        .background(Color.doorShadow.ignoresSafeArea())
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
            if !controller.hasHardwareHinge && !settings.hasOpenedDoor {
                SwipeHint()
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: settings.hasOpenedDoor)
        .onChange(of: controller.isClosed) { _, isClosed in
            if !isClosed { settings.hasOpenedDoor = true }
        }
        .onChange(of: canSwipe) { _, canSwipe in
            if !canSwipe { controller.stopSwiping() }
        }
        .sheet(isPresented: $isShowingSettings) {
            // Unfolded: the hinge is open well past halfway (folded or no hinge: four tiles per row).
            SettingsView(
                settings: settings, hasHinge: controller.hasHardwareHinge,
                isUnfolded: (controller.hinge?.degrees ?? 0) > 100)
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
            // UI testing and screenshots: launch with `-showSettings YES` or `-openDoor YES`.
            .task {
                let defaults = UserDefaults.standard
                guard defaults.bool(forKey: "showSettings") || defaults.bool(forKey: "openDoor") else { return }
                try? await Task.sleep(for: .milliseconds(600))
                if defaults.bool(forKey: "openDoor") { controller.swing(open: true) }
                if defaults.bool(forKey: "showSettings") { isShowingSettings = true }
            }
        #endif
    }

    /// Which screen the door is on: the iPhone Duo's inner display (where the door is open as far
    /// as the phone), part of it in Split View, or one flat screen.
    ///
    /// The system decides which screen is on (a slightly opened phone often stays on the cover
    /// display), so follow the screen, not the hinge. Only the inner display reports a fold region
    /// (inactive when flat); the cover never does. The interface may also rotate on the inner
    /// display, so the screen's shape can't be used.
    private func doorScreen(_ proxy: GeometryProxy) -> DoorScreen {
        DoorScreen.current(
            hasHinge: controller.hasHardwareHinge, fillsScreen: windowFit.fillsScreen,
            hasFold: !proxy.reservedRegions(kind: .division, options: .includeInactive).isEmpty,
            isFullyOpen: controller.hinge?.status == .fullyOpen)
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
