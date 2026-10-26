# Duor — notes for Claude

iPhone Duo door simulator. Design: `docs/SOLUTION_DESIGN.md`.

## Build and test

- `make test` — builds and runs Swift Testing tests on the *iPhone Duo* simulator. Run after any logic change.
- `make sounds` — renders every synthesized sound to `build/sounds/*.wav` and prints peak/RMS. Run after any change under `Duor/Audio/DSP`; keep peaks below 0 dBFS.
- `make lint` / `make format` — `swift format` with `.swift-format`. CI runs lint in `--strict` mode.

## Conventions

- Swift 6, strict concurrency, `MainActor` default isolation. Mark audio-thread code `nonisolated` explicitly.
- Deployment target iOS 27.1. Use 27.x APIs directly (no availability checks needed), e.g. `AVAudioEngine.connectNode(_:to:format:)` and `AVAudioPlayerNode.playAudio()` (the old `connect`/`play` are deprecated).
- Hinge: use `status` transitions for discrete events, the angle only for continuous effects. Never assume an update rate. Never use the hinge for layout.
- Keep door logic in pure value types (`DoorMotionInterpreter`) with tests; views and `DoorController` stay thin.
- Audio is synthesized, not sampled. Code in `Duor/Audio/DSP` is real-time: `nonisolated` `Sendable` value types, no allocation / logging / Objective-C in `render`, fixed storage via `InlineArray` and `SIMD8`. It must not import AVFoundation or UIKit (the render tool compiles it for macOS).
- Project file is JSON (`Duor.xcodeproj/project.xcproj`). New files must be listed there with `target-membership` (`Duor/compile-sources`, `Duor/resources`, `DuorTests/compile-sources`).
- User-facing strings go through `LocalizedStringResource` / `Text` so the string catalog picks them up.
