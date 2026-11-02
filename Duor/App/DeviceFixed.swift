import SwiftUI
import UIKit

/// Lays content out in the device's own portrait frame and counter-rotates it when the system
/// rotates the interface, so the door stays fixed to the hardware.
///
/// The interface orientation is normally locked (`DoorHostingController`), but the lock holds
/// whatever orientation the app was in, and the system lifts it in some layouts. Whenever the
/// interface ends up turned relative to the device, this turns the door back so it stays fixed
/// to the hardware.
struct DeviceFixed<Content: View>: View {
    /// Clockwise quarter turns that undo the interface rotation. See `DeviceFixedTurns`.
    let quarterTurns: Int
    /// Builds the content for its device-portrait size and the fold crease in that space (if any).
    @ViewBuilder let content: (_ size: CGSize, _ crease: CGRect?) -> Content

    var body: some View {
        GeometryReader { proxy in
            let screen = proxy.size
            let size = quarterTurns.isMultiple(of: 2) ? screen : CGSize(width: screen.height, height: screen.width)
            let crease = proxy.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
                .first { $0.isActive }
                .map { Self.toContent($0.frame, screen: screen, content: size, turns: quarterTurns) }

            content(size, crease)
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(Double(quarterTurns) * 90))
                .frame(width: screen.width, height: screen.height)
        }
        .ignoresSafeArea()
    }

    /// Maps a rect from screen space into the unrotated content space.
    private static func toContent(_ rect: CGRect, screen: CGSize, content: CGSize, turns: Int) -> CGRect {
        let contentToScreen = CGAffineTransform(translationX: screen.width / 2, y: screen.height / 2)
            .rotated(by: CGFloat(turns) * .pi / 2)
            .translatedBy(x: -content.width / 2, y: -content.height / 2)
        return rect.applying(contentToScreen.inverted())
    }
}

enum DeviceFixedTurns {
    /// How far to turn the door so it stays fixed to the device.
    ///
    /// Each screen has a known shape when the device is upright: the inner display is wide (the
    /// book posture), the cover display is tall. If the screen's current shape differs, the system
    /// rotated the interface, and the physical device orientation says which way.
    /// Without a hinge (a regular iPhone or an iPad) the door isn't part of the hardware: it stays
    /// upright and follows the interface, which on iPad rotates freely.
    /// - Parameter landscape: The last landscape orientation the device was in. The interface can only
    ///   have turned to one of these, and if it's locked there, the device may since have turned back.
    static func quarterTurns(
        screen: CGSize, isInnerDisplay: Bool, hasHinge: Bool, landscape: UIDeviceOrientation
    ) -> Int {
        guard hasHinge else { return 0 }
        let isWide = screen.width > screen.height
        guard isWide != isInnerDisplay else { return 0 }
        // The interface turned to stay upright for the user; turn the door back the other way.
        return landscape == .landscapeRight ? 1 : -1
    }
}

/// The physical device orientation, ignoring face up / face down, which don't rotate anything.
@Observable
final class DeviceOrientationMonitor {
    private(set) var orientation: UIDeviceOrientation = .portrait
    /// The most recent landscape orientation (`.landscapeLeft` until the device has been in one).
    private(set) var lastLandscape: UIDeviceOrientation = .landscapeLeft
    @ObservationIgnored private var observation: Task<Void, Never>?

    func start() {
        guard observation == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        update(UIDevice.current.orientation)
        observation = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIDevice.orientationDidChangeNotification) {
                self?.update(UIDevice.current.orientation)
            }
        }
    }

    private func update(_ newValue: UIDeviceOrientation) {
        guard newValue.isPortrait || newValue.isLandscape else { return }
        orientation = newValue
        if newValue.isLandscape { lastLandscape = newValue }
    }
}
