// swift-tools-version: 6.2
// Builds and tests the audio code (Duor/Audio/DSP) and the pure door logic without Xcode, e.g. on
// Linux. Sources and tests are symlinks into the app, so this checks the very same files.
//
//   swift test --package-path Tools/AudioCheck
//
// The app itself is built and tested with `make test` (Xcode).
import PackageDescription

let settings: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "AudioCheck",
    targets: [
        .target(name: "Duor", swiftSettings: settings),
        .testTarget(name: "DuorTests", dependencies: ["Duor"], swiftSettings: settings),
    ]
)
