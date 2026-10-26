import Foundation
import SwiftUI

/// One sample of the device hinge, decoupled from SwiftUI's `DeviceHinge`
/// so door logic can be unit tested and driven by a simulated hinge.
struct HingeReading: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case closed
        case partiallyOpen
        case fullyOpen
    }

    /// Hinge angle in degrees. 0 is folded shut, 180 is flat.
    var degrees: Double
    var status: Status
    /// Monotonic timestamp in seconds (system uptime).
    var timestamp: TimeInterval
}

extension HingeReading {
    /// Builds a reading from the system hinge. Returns nil on devices without a hinge.
    init?(_ hinge: DeviceHinge?, at timestamp: TimeInterval) {
        guard let hinge else { return nil }
        self.init(degrees: hinge.angle.degrees, status: Self.mapStatus(of: hinge), timestamp: timestamp)
    }

    // `DeviceHinge.Status` is a struct, not an enum, so it can't be switched over exhaustively.
    private static func mapStatus(of hinge: DeviceHinge) -> Status {
        if hinge.status == .closed { return .closed }
        if hinge.status == .fullyOpen { return .fullyOpen }
        return .partiallyOpen
    }

    /// A reading for devices without a hinge (simulated with a slider).
    /// Status is derived from the angle, since there is no hardware status.
    static func simulated(degrees: Double, at timestamp: TimeInterval) -> HingeReading {
        let status: Status =
            if degrees <= 1 { .closed } else if degrees >= 179 { .fullyOpen } else { .partiallyOpen }
        return HingeReading(degrees: degrees, status: status, timestamp: timestamp)
    }
}
