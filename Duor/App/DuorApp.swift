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
        window.rootViewController = DoorHostingController(rootView: RootView())
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
    override var prefersInterfaceOrientationLocked: Bool { true }
}
