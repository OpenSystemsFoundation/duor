import Foundation
import Testing

@testable import Duor

@Suite("DoorSettings")
struct DoorSettingsTests {
    /// Fresh, empty defaults for each test, so nothing leaks between tests or into the app.
    private func emptyDefaults() -> UserDefaults {
        let name = "DoorSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func startsWithTheOakDoorAndNoSwipeChoice() {
        let settings = DoorSettings(defaults: emptyDefaults())
        #expect(settings.look == DoorLook(style: .oak, hardware: .iron, scene: .livingRoom))
        #expect(!settings.catLovers)
        #expect(!settings.hasOpenedDoor)
        #expect(settings.savedSwipeMode == nil)
    }

    @Test func savesEveryChange() {
        let defaults = emptyDefaults()
        let settings = DoorSettings(defaults: defaults)
        settings.style = .castle
        settings.hardware = .copper
        settings.scene = .space
        settings.catLovers = true
        settings.savedSwipeMode = false
        settings.hasOpenedDoor = true

        let reloaded = DoorSettings(defaults: defaults)
        #expect(reloaded.look == DoorLook(style: .castle, hardware: .copper, scene: .space))
        #expect(reloaded.catLovers)
        #expect(reloaded.savedSwipeMode == false)
        #expect(reloaded.hasOpenedDoor)
    }

    @Test func pickingADoorBringsItsHardwareAndScene() {
        let settings = DoorSettings(defaults: emptyDefaults())
        settings.hardware = .chrome
        settings.scene = .beach
        settings.pick(.castle)
        #expect(settings.look == DoorLook(style: .castle, hardware: .bronze, scene: .greatHall))
    }

    @Test func swipeModeFollowsTheHingeUntilTheUserPicks() {
        let settings = DoorSettings(defaults: emptyDefaults())
        #expect(!settings.isSwipeOn(hasHinge: true))
        #expect(!settings.swipeModeSetting(hasHinge: true))
        #expect(settings.isSwipeOn(hasHinge: false))

        settings.savedSwipeMode = true
        #expect(settings.isSwipeOn(hasHinge: true))

        // Without a hinge, swiping is the only way in: a saved "off" can't lock the user out.
        settings.savedSwipeMode = false
        #expect(settings.isSwipeOn(hasHinge: false))
    }

    @Test func ignoresUnknownSavedValues() {
        let defaults = emptyDefaults()
        defaults.set("drawbridge", forKey: DoorSettings.Key.style)
        #expect(DoorSettings(defaults: defaults).style == .oak)
    }
}
