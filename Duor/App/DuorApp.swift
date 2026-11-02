import SwiftUI
import UIKit

/// The app is hosted in UIKit so its root view controller can lock the interface orientation:
/// SwiftUI has no modifier for `prefersInterfaceOrientationLocked`.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = DoorHostingController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

/// Keeps the interface from rotating while the app fills the screen.
///
/// The door is physical: turning the phone should turn the door with it, not spin the
/// interface around (the iPhone Duo's inner display is a resizable scene, which ignores the
/// Info.plist orientation list). If the system lifts the lock (e.g. Split View),
/// `DeviceFixed` still turns the door back into place.
final class DoorHostingController: UIHostingController<RootView> {
    private let windowFit: WindowFit

    init() {
        let windowFit = WindowFit()
        self.windowFit = windowFit
        super.init(rootView: RootView(windowFit: windowFit))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Locked on iPhone, where the door is part of the phone. An iPad turns freely: the door follows.
    override var prefersInterfaceOrientationLocked: Bool { traitCollection.userInterfaceIdiom == .phone }

    /// Split View shares the screen: tell the door it's in a window.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let screen = view.window?.windowScene?.screen else { return }
        let fills = WindowFit.fills(window: view.bounds.size, screen: screen.bounds.size)
        if fills != windowFit.fillsScreen { windowFit.fillsScreen = fills }
    }
}

/// Whether the app's window fills its screen. Not in Split View, where it shares the screen.
@Observable
final class WindowFit {
    var fillsScreen = true

    /// Whether a window of `window` size fills a screen of `screen` size, either way round.
    static func fills(window: CGSize, screen: CGSize) -> Bool {
        let windowSides = [window.width, window.height].sorted()
        let screenSides = [screen.width, screen.height].sorted()
        return abs(windowSides[0] - screenSides[0]) < 1 && abs(windowSides[1] - screenSides[1]) < 1
    }
}
