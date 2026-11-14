# Duor — notes for Claude

iPhone Duo door simulator. Design: `docs/SOLUTION_DESIGN.md`.

## Build and test

- `make test` — builds and runs Swift Testing tests on the *iPhone Duo* simulator, skipping the slow sound-synthesis suites (`AUDIO_SUITES` in the Makefile; add new ones there). Run after any logic change. `make test-audio` runs everything; run it (or `make audio-check`) after any change under `Duor/Audio/DSP`.
- `make sounds` — renders every door × event × swing gesture to `build/sounds/*.wav` (flat and `speaker-` voiced) and prints the measurements: loudness relative to each door's slam against the design targets (`!` marks a miss), peaks and level into the soft clipper, door balance, creak periodicity, decay, update-rate independence and render cost. Run after any change under `Duor/Audio/DSP`; keep peaks below 0 dBFS. `make sounds BASELINE=old.json` prints before → after (each run writes `build/sounds/metrics.json`). `make bench` prints the render cost only.
- `make audio-check` — builds `Duor/Audio/DSP` plus the pure door logic as a Swift package (`Tools/AudioCheck`, symlinks into the app) and runs their tests without Xcode. Works on Linux with a Swift 6.2+ toolchain, as does `make sounds`. A new DSP file is picked up automatically; a new test file needs a symlink in `Tools/AudioCheck/Tests/DuorTests`.
- `make banner` — renders the App Store header and search results artwork (`Tools/RenderBanner`, compiles the scene code for macOS). Keep `Duor/Door/Scenes` free of UIKit.
- `make lint` / `make format` — `swift format` with `.swift-format`. CI runs lint in `--strict` mode.

## Conventions

- Swift 6, strict concurrency, `MainActor` default isolation. Mark audio-thread code `nonisolated` explicitly.
- Deployment target iOS 27.1. Use 27.x APIs directly (no availability checks needed), e.g. `AVAudioEngine.connectNode(_:to:format:)` and `AVAudioPlayerNode.playAudio()` (the old `connect`/`play` are deprecated).
- Hinge: use `status` transitions for discrete events, the angle only for continuous effects. Never assume an update rate. Never use the hinge for layout.
- Keep door logic in pure value types (`DoorMotionInterpreter`) with tests; views and `DoorController` stay thin.
- Audio is synthesized, not sampled. Code in `Duor/Audio/DSP` is real-time: `nonisolated` `Sendable` value types, no allocation / logging / Objective-C in `render`, fixed storage via `InlineArray` and `SIMD8`. It must not import AVFoundation or UIKit (the render tool compiles it for macOS).
- The app uses the UIKit lifecycle (`DuorApp.swift`) only so `DoorHostingController` can lock the interface orientation. Keep UI in SwiftUI. After switching lifecycles, delete the app from the simulator once: restored scene sessions keep the old delegate.
- Debug launch arguments: `-showSettings YES`, `-openDoor YES`, `-doorStyle <oak|cottage|barn|castle|spaceship|metal>`, `-hardware <iron|brass|chrome|copper|bronze>`, `-insideScene <livingRoom|greatHall|beach|forest|space|brickWall>`, `-catLovers YES`, `-speakerVoicing <auto|on|off>` (force the phone-speaker voicing to compare it).
- Project file is JSON (`Duor.xcodeproj/project.xcproj`). New files must be listed there with `target-membership` (`Duor/compile-sources`, `Duor/resources`, `DuorTests/compile-sources`).
- User-facing strings go through `LocalizedStringResource` / `Text` so the string catalog picks them up. The app ships in 15 languages (en + 14 in `Localizable.xcstrings`): translate every new string into all of them, and update the matching App Store listings and screenshot captions in `appstore/release.json`.
- Right-to-left: the door view is forced `.leftToRight` (the door is physical and never mirrors); Settings mirrors normally.
