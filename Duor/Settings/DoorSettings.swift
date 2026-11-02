import Foundation
import Observation

/// Everything the user picks in Settings, plus whether they've opened the door yet. Each change is
/// saved to `UserDefaults` right away.
///
/// Launch arguments such as `-doorStyle castle` override the saved values, because they sit in
/// the arguments domain of the standard defaults.
@Observable
final class DoorSettings {
    enum Key {
        static let style = "doorStyle"
        static let hardware = "hardware"
        static let scene = "insideScene"
        static let catLovers = "catLovers"
        static let swipeMode = "swipeMode"
        static let hasOpenedDoor = "hasOpenedDoor"
    }

    var style: DoorStyle {
        didSet { defaults.set(style.rawValue, forKey: Key.style) }
    }
    var hardware: HardwareFinish {
        didSet { defaults.set(hardware.rawValue, forKey: Key.hardware) }
    }
    var scene: InsideScene {
        didSet { defaults.set(scene.rawValue, forKey: Key.scene) }
    }
    /// A cat joins every scene.
    var catLovers: Bool {
        didSet { defaults.set(catLovers, forKey: Key.catLovers) }
    }
    /// "Swipe mode" as the user set it. Nil until they change it, so the default can follow
    /// whether there's a hinge (see `SwipeMode`).
    var savedSwipeMode: Bool? {
        didSet { defaults.set(savedSwipeMode, forKey: Key.swipeMode) }
    }
    /// The door has been opened at least once, so the swipe hint is no longer needed.
    var hasOpenedDoor: Bool {
        didSet { defaults.set(hasOpenedDoor, forKey: Key.hasOpenedDoor) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        style = defaults.string(forKey: Key.style).flatMap(DoorStyle.init) ?? .oak
        hardware = defaults.string(forKey: Key.hardware).flatMap(HardwareFinish.init) ?? .iron
        scene = defaults.string(forKey: Key.scene).flatMap(InsideScene.init) ?? .livingRoom
        catLovers = defaults.bool(forKey: Key.catLovers)
        savedSwipeMode = defaults.object(forKey: Key.swipeMode) == nil ? nil : defaults.bool(forKey: Key.swipeMode)
        hasOpenedDoor = defaults.bool(forKey: Key.hasOpenedDoor)
    }

    /// Everything that decides how the door looks and sounds.
    var look: DoorLook { DoorLook(style: style, hardware: hardware, scene: scene) }

    /// Picks a door. Each door comes with its own hardware and scene, which can be changed after.
    func pick(_ door: DoorStyle) {
        style = door
        hardware = door.defaultHardware
        scene = door.defaultScene
    }

    /// Whether swiping moves the door.
    func isSwipeOn(hasHinge: Bool) -> Bool {
        SwipeMode.isOn(saved: savedSwipeMode, hasHinge: hasHinge)
    }

    /// What the "Swipe mode" toggle shows: the device's default until the user picks.
    func swipeModeSetting(hasHinge: Bool) -> Bool {
        savedSwipeMode ?? SwipeMode.isOnByDefault(hasHinge: hasHinge)
    }
}
