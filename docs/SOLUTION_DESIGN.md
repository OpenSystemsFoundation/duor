# Duor — Solution Design

> A door simulator for the foldable iPhone Duo. The phone *is* the door: fold it shut and you see the outside of a door you can knock on; unfold it and the door swings open with a creak; fold it again and it closes with a latch — or a slam.

| | |
|---|---|
| **Status** | Draft v0.4 — 26 Oct 2026 (synthesized audio, door UX v2, device-fixed door) |
| **Platform** | iOS 27.1+, iPhone Duo (graceful fallback on other iPhones) |
| **Stack** | Swift 6, SwiftUI, AVAudioEngine + hand-rolled DSP (no samples), Swift Testing |
| **MVP** | One door: oak with iron hinges |

---

## 1. Goals and scope

### Goals

1. Make the physical hinge feel like a real door hinge: sound follows the motion with no noticeable delay.
2. Three core moments: **knock** (folded), **open** (unfold), **close** (fold).
3. A settings screen where the door's look (and sound set) can be changed.
4. An architecture where adding a new door type is a data/asset change, not new logic.

### MVP (v1.0)

- Single style: **wooden oak door, black iron hinges, round knob**.
- Cover display (folded): door outside, tap to knock, haptic thump.
- Unfold: latch click, creak whose volume and pitch follow hinge speed, soft thud at the open stop.
- Fold: latch click (gentle/firm) or slam, based on closing speed.
- Settings sheet with the style picker (one entry for now).
- Works on non-Duo iPhones with an on-screen "hinge" slider.

### Non-goals (for MVP)

- Multiple door styles, custom colours, unlockables.
- iPad, Mac, Watch.
- Monetisation, accounts, analytics.

---

## 2. Platform research: the iPhone Duo hinge API

All signatures below were checked against the **iOS 27.1 SDK** shipped with Xcode 27.1 (`SwiftUICore.swiftinterface`, `UIKit/UIHinge.h`, `UIKit/UIHingeInteraction.h`).

### 2.1 SwiftUI (what Duor uses)

```swift
@available(anyAppleOS 27.1, *)
extension View {
    nonisolated func onHingeChange(
        isEnabled: Bool = true,
        _ action: @escaping (_ oldContext: DeviceHingeContext, _ newContext: DeviceHingeContext) -> Void
    ) -> some View
}

struct DeviceHingeContext: Equatable, Sendable {
    var hinge: DeviceHinge?          // nil on devices without a hinge
}

struct DeviceHinge: Hashable, Sendable {
    var status: Status               // .closed, .partiallyOpen, .fullyOpen
    var angle: Angle                 // SwiftUI Angle; 0° folded, 180° flat
}
```

Notes:

- `DeviceHinge.Status` is a **struct with static members**, not an enum, so it can't be switched over exhaustively. Compare with `==`.
- `isEnabled: false` pauses delivery without removing the modifier (useful while the Settings sheet is up).

### 2.2 UIKit equivalent

```swift
let interaction = UIHingeInteraction { [weak self] _, update in
    guard let hinge = update.hinge else { return }   // nil: left a hierarchy with hinge updates
    hinge.angle    // CGFloat, **radians**
    hinge.status   // UIHinge.Status: .unknown, .closed, .partiallyOpen, .fullyOpen
}
view.addInteraction(interaction)
```

UIKit has an extra `.unknown` status. The handler fires once with the initial state, then on each change.

### 2.3 Rules from Apple's headers and guidance

| Rule | Consequence for Duor |
|---|---|
| "The rate and granularity of angle updates are system policy… don't depend on a particular update frequency or precision." | Velocity is computed from real timestamps, with a clamped time gap. No fixed-rate assumptions. |
| "If you only need to know whether the hinge is closed, partially open, or fully open, prefer `status`." | **Latch, slam and open-stop events trigger on `status` transitions**, not angle thresholds. The angle only drives the creak and the visuals. |
| Use the hinge for **effects and interactions, not layout**. | Layout uses size classes / `reservedRegions`; the hinge only animates the door and drives audio. |
| `hinge` is `nil` on non-foldables. | Fallback slider; the app is still usable everywhere. |
| The hardware angle range isn't documented. | Don't assume closed is exactly 0° or flat is exactly 180°. Map relative to the angles seen at status changes (see §6.3). |

### 2.4 Related iPhone Duo APIs worth knowing

- **`ArrangementView`**: primary/secondary layout across the fold (`.split`, `.overlay`). Not needed for MVP.
- **`GeometryProxy.reservedRegions(kind:)`**: `.division` gives the crease rectangle when unfolded; `.occlusion` gives camera/Dynamic Island areas. **Duor uses `.division` to draw the door's hinge plates exactly on the physical crease.**
- **Cover display**: when folded, the app keeps running on the outer display, which is compact width / regular height and reports no reserved regions (per iPhone-Duo-by-Examples observations). This is where the "outside of the door" lives.
- **Vertical toolbars** (`toolbarVerticalBehavior`, `axisBehavior`): the settings button may be moved to a vertical bar automatically when unfolded.

---

## 3. Prior art

| Project | What it does | What we borrow |
|---|---|---|
| [Accorduon](https://github.com/artemnovichkov/Accorduon) (MIT, SwiftUI) | An accordion; the hinge is the bellows. Hinge **speed** becomes air pressure for a synthesized reed sound. | (1) Speed = `|Δangle| / Δt` with Δt clamped to `[1/120 s, 0.2 s]` so a jump after a pause still counts but isn't infinite. (2) Sound decays by itself when updates stop ("air leaks out"). (3) Synthesis through `AVAudioSourceNode` with state behind a `Mutex`. (4) A non-hinge fallback ("Auto Air"). (5) Xcode 27's JSON `project.xcproj` format. |
| [iPhone-Duo-by-Examples](https://github.com/artemnovichkov/iPhone-Duo-by-Examples) | Catalogue of SwiftUI examples for all Duo APIs. | Cover-display behaviour, reserved regions/crease, "Angle History" visualisation for debugging. |
| [hinge CLI](https://github.com/artemnovichkov/hinge) | Sets the hinge angle of the iPhone Duo **simulator** from the terminal (`hinge 120`, `hinge sweep 180 0 0.3`). Uses a private HID event; simulator only. | Scripted simulator tests of open/close/slam. |
| [expo-foldables](https://github.com/azizbecha/expo-foldables), [expo-hinge](https://docs.expo.dev/versions/latest/sdk/hinge/), [hinge-guess](https://github.com/erkamyaman/hinge-guess) | Cross-platform wrappers and a hinge-angle guessing game. | Confirms the same data model (status + continuous angle) across ecosystems — useful if an Android port ever happens. |

---

## 4. Experience design

### 4.1 The metaphor

The two halves of the phone are the **door leaf** and the **wall/frame**. The crease is the **hinge line**.

Two rules follow from that:

1. **On a real Duo, the screen on the swinging half never animates the swing.** The phone half physically rotates, so it *is* the door. Its screen shows the leaf's inside face standing still; drawing a 3D swing on top would count the motion twice (that was the v0.1 bug). Where nothing swings physically (the Simulator, phones without a hinge) the leaf swings on screen at the true angle: it stands at 180° − hinge angle to the doorway.
2. **The door is fixed to the device.** The app asks for portrait only, but the inner display is a resizable scene and the system rotates it anyway. `DeviceFixed` counter-rotates the whole scene so the door never turns with the interface. It knows the interface turned because each screen has a fixed upright shape (inner: wide book posture; cover: tall), and the physical device orientation says which way to turn back.

```
   FOLDED (cover display)             UNFOLDING (inner display)              FLAT (180°)
  ┌────────────┐                    ┌───────────┬───────────┐          ┌───────────┬───────────┐
  │ ▮   ┌────┐ │                    │  frame    ▮   door    │          │  room     ▮  door     │
  │     │    │ │   tap = knock      │  + room   ▮   leaf    │          │  beyond   ▮  (inside  │
  │     └────┘ │                    │  beyond   ▮  swinging │          │  the      ▮  face,    │
  │     ┌────┐ │                    │           ▮           │          │  doorway  ▮  fully    │
  │     │  ● │ │                    │           ▮           │          │           ▮  open)    │
  │ ▮   └────┘ │                    │           ▮           │          │           ▮           │
  └────────────┘                    └───────────┴───────────┘          └───────────┴───────────┘
   outside face                        ▮ = hinges drawn on the crease: a strap from leaf to frame across the reserved gap, barrel on the hinge line
       (position from reservedRegions(kind: .division); falls back to the middle when the system reports none)
```

### 4.2 Interaction states

| Phone | Door | Screen | Sound | Haptic |
|---|---|---|---|---|
| Folded (`.closed`) | Closed | Cover: door outside face | — | — |
| Tap on cover | Knocked | Soft shadow blooms where the knuckle hit; door jiggles 1.5 pt | Knock (synthesized, every one different) | Heavy impact |
| `.closed → .partiallyOpen` | Unlatching | Whatever screen the system keeps on (often still the cover: then the outside face stays) | Latch release click | Light impact |
| Angle changing | Swinging | Inner display: leaf's inside face (still) + doorway; the room lights up from ~10° to ~120°, hinge-side shadow on the leaf fades | Creak: volume and pitch ∝ speed; fades when updates stop | — |
| `→ .fullyOpen` | Hits stop | Leaf flat against wall | Soft thud, scaled by impact speed | Soft impact |
| `→ .closed`, slow | Gently closed | Back to cover | Quiet latch click | Light |
| `→ .closed`, medium | Firmly closed | Back to cover, 3 pt bump | Full latch click | Medium |
| `→ .closed`, fast | Slammed | Back to cover, door shakes 8 pt in its frame | Slam + frame rattle | Heavy |

Knocking is only enabled while closed (you knock on a closed door).

**Which face to draw.** With a real hinge, the app follows the *screen*, not the hinge status: the system decides when to switch displays, and a slightly opened phone often stays on the cover display. Only the inner display reports a fold region (`reservedRegions(kind: .division, options: .includeInactive)`, inactive when flat); the cover never does. So `RootView` draws the inside view when a fold region exists (or the hinge is fully open), and the outside face otherwise. Screen shape can't be used, because the inner display can rotate. Without a hinge there is one screen, so it follows the simulated hinge status.

### 4.3 Settings

A gear button (top trailing; vertical toolbar when unfolded) opens a sheet:

- **Door style**: MVP has one. Later: grid of thumbnails.
- *(Later)* Wood finish / paint colour, hinge finish (iron, brass, chrome), knob vs. lever vs. knocker, sound on/off per event, haptics on/off, "slam sensitivity".

Hinge updates are paused (`isEnabled: false`) while the sheet is open so no creaks play while browsing settings.

---

## 5. Architecture

### 5.1 Overview

```
 ┌─────────────────────────── SwiftUI (MainActor) ───────────────────────────┐
 │                                                                            │
 │  RootView ──onHingeChange──▶ HingeReading ──▶ DoorController (@Observable) │
 │     │  ▲                         ▲                 │      │                │
 │     │  └── isClosed / angle ─────┼─────────────────┘      │ DoorEvent      │
 │     │                            │                        ▼                │
 │     │                  SimulatedHingeControl     DoorMotionInterpreter     │
 │     │                  (non-Duo fallback)        (pure value type)         │
 │     ▼                                                     │                │
 │  DoorOutsideView / DoorInsideView / SettingsView          │                │
 └───────────────────────────────────────────────────────────┼────────────────┘
                                                             ▼
                                          DoorSoundPlaying (protocol)
                                          └─ DoorAudioEngine: AVAudioEngine
                                               AVAudioSourceNode ─▶ DoorSynth (§6)
```

### 5.2 Components

| File | Responsibility |
|---|---|
| `App/DuorApp.swift` | App entry. |
| `App/RootView.swift` | Picks outside vs. inside view, hosts `onHingeChange`, settings sheet, haptics, fallback slider. |
| `Hinge/HingeReading.swift` | Our own `Sendable` value type for one hinge sample (degrees, status, monotonic timestamp). Decouples logic from `DeviceHinge` so it can be unit tested and simulated. |
| `Door/DoorMotionInterpreter.swift` | **Pure** state machine: `ingest(HingeReading) -> [DoorEvent]`. Computes smoothed velocity, emits `unlatched`, `swing(velocity)`, `hitOpenStop(speed)`, `closed(CloseKind)`. Fully covered by unit tests. |
| `Door/DoorController.swift` | `@Observable` glue: holds the latest reading, feeds the interpreter, maps events → sounds, debounces the creak fade, exposes `isClosed`, `angle`, `knockCount`. |
| `Door/DoorStyle.swift` | Style catalogue (enum, `@AppStorage`-backed). Palette + `SoundProfile` per style. |
| `Door/DoorArt.swift` | `Canvas`-drawn four-panel leaf (grain, raised panels, iron hinges, knob, peephole) with `hingeSide` mirroring; shared `DoorGeometry` so hinges, knob and strike plate line up across views. |
| `Door/DoorwayArt.swift` | The fixed half: casing, jambs, strike plate, and the lit room beyond. |
| `Door/DoorOutsideView.swift` | Cover display: outside face, tap-to-knock with dent and shake. |
| `Door/DoorInsideView.swift` | Inner display: splits at the crease, leaf inside face + doorway, hinge straps across the crease, light driven by angle. |
| `Audio/DoorAudioEngine.swift` | Audio session, `AVAudioEngine` with one `AVAudioSourceNode` that calls `DoorSynth.render`, restart on route change / interruption. Behind the `DoorSoundPlaying` protocol for tests. |
| `Audio/DSP/*` | The synthesizer: `DoorSynth` (thread hand-off + sound recipes), `ImpactVoice`, `CreakVoice`, `ModalBank`, `RoomReverb`, `NoiseSource`, `SoundProfile` (per-style materials). Pure Swift, no AVFoundation, so it is unit tested and renders offline. |
| `Settings/SettingsView.swift` | Style picker. |

### 5.3 Event logic (DoorMotionInterpreter)

```
on reading r (previous p):
  if p == nil                      → remember r, no events   (initial state is not a movement)
  Δt  = clamp(r.t − p.t, 1/240 s, 0.25 s)
  v_i = (r.deg − p.deg) / Δt                       (+ opening, − closing)
  v   = v + (v_i − v) · 0.5                         (exponential smoothing)
  impact = max(|v_i|, |v|)

  p.status == closed  ∧ r.status ≠ closed  → unlatched
  r.status ≠ closed   ∧ |v| ≥ 6 °/s         → swing(v)
  r.status == fullyOpen ∧ p.status ≠ fullyOpen → hitOpenStop(impact)
  r.status == closed  ∧ p.status ≠ closed  → closed(gentle < 90 °/s ≤ firm < 260 °/s ≤ slam)
```

Real readings jitter by a fraction of a degree and the status can flicker at the closed and fully-open points, which used to make the door creak while lying flat and click repeatedly when shut. So:

- **Jitter tolerance (1.5°):** velocity is measured from the last *accepted* position; smaller changes are ignored. Slow real motion still gets through after a few samples, with its true elapsed time.
- **Hysteresis:** the door is either latched or not. It unlatches only after opening 3° past the latched angle and latches once on reaching `.closed`; flickers in between do nothing. The open stop fires once, then re-arms only after the door swings 8° back.

All thresholds live in `DoorMotionInterpreter.Configuration` and **must be tuned on a real device** (§8).

### 5.4 Concurrency

- Project uses Swift 6 strict concurrency with **`MainActor` default isolation** and approachable concurrency.
- Hinge callbacks, the controller and the interpreter run on the main actor (cheap: a few arithmetic ops per sample).
- The synth renders on the real-time audio thread. The main actor never touches synth state: it posts commands (`play`, `setCreak`, `setProfile`) into a small `Mutex`-guarded inbox. At the start of each buffer the audio thread swaps the inbox array with its own pre-reserved scratch array (no allocation), then renders.
- Rules for code under `Audio/DSP`: `nonisolated`, `Sendable` value types; no allocation, locks other than the two short `Mutex`es, Objective-C calls or logging in `render`. Fixed-size storage uses `InlineArray` and `SIMD8`.

---

## 6. Audio design: hand-rolled synthesis

Every sound is generated live from small physical models. There are no audio files. That means no two knocks are identical, the creak follows the hinge continuously instead of looping a recording, every door style is just a set of numbers, and there are no licensing questions.

### 6.1 Building blocks (`Audio/DSP`)

| Block | Model | Used for |
|---|---|---|
| `ModalBank` | Up to 8 two-pole resonators in SIMD lanes. Each lane is one vibration mode of an object: frequency, decay time, gain. Input is scaled by `sin ω` so every mode peaks at its gain. | The "material" of anything struck or scraped. |
| `ImpactVoice` | A **half-sine contact force** (duration = contact time) with optional roughness, driving a `ModalBank`. Short contact (0.2 ms steel bolt) excites high modes; long contact (8 ms rubber stop) only low ones. Random ±3–5 % detune and ±10 % decay per hit. | Knocks, latch clicks, thuds, slams, rattles. |
| `CreakVoice` | **Stick-slip friction.** The hinge pin sticks, builds tension, slips. Each slip is an impulse; slip rate = `baseRate + ratePerDegree · speed` (that's the pitch), with slow random pitch wander and per-slip jitter. Slips ring 4 hinge "squeal" formants and 3 door-body modes. At low speed the grip is unreliable, so slips drop out and the creak sputters into ticks. Formants brighten with intensity and drop ~6 % when closing. | The creak. |
| `RoomReverb` | Small Freeverb-style room: 4 damped combs → 2 allpasses, wet ≈ 12 %, fed by a send bus so each hit chooses how much room it gets. | Puts the door in a hallway. |
| Master | `tanh` soft clipper. | Stacked hits saturate instead of clipping. |
| `NoiseSource` | xorshift32, seeded. | Roughness, randomness; deterministic in tests. |

### 6.2 Sound recipes

Each one-shot is a few strikes on the style's materials (`SoundProfile`: `panel`, `frame`, `latch`, `hinge` mode sets + a `CreakProfile`):

| Sound | Recipe |
|---|---|
| Knock | Dedicated `knock` modes: the same oak, heavily damped by the hand (7–28 ms decays, 160 Hz–1.35 kHz). 0.8–1.2 ms contact (knuckle), ±3 % pitch, plus a 0.2 ms knuckle snap ~1.7 octaves up. Mostly dry (reverb send 0.3) so it sounds close and tight, not hollow. Wood rings out in ~100 ms. |
| Unlatch | Latch click, second lower click 18–30 ms later (bolt clears the strike plate), faint panel tick. The latch material is steel mounted in wood: 4–14 ms decays, so it clacks instead of ringing. |
| Latch (gentle/firm) | Frame thump (∝ volume²) + panel + bolt riding the strike plate, then the bolt snapping in 28–45 ms later. |
| Slam | Heavy frame hit (6 ms, longer decay) + panel + latch at 8 ms + four hinge rattles at 20–45 ms intervals, each 0.6× quieter. |
| Open stop | Panel with 8 ms contact (rubber stopper, dull) + a small hinge tick at 35 ms. |
| Creak | Continuous; driven by signed hinge velocity, smoothed over 40 ms; fades out on its own when updates stop. |

Mode frequencies are chosen for a **phone speaker**, which reproduces little below ~250 Hz. Each sound's body sits around 200 Hz to 1.2 kHz, with lower modes kept for headphones.

### 6.3 Engine and latency

- `AVAudioSession` `.playback` + `.mixWithOthers`, preferred IO buffer 5 ms. *Open question: respect the silent switch? See §9.*
- One mono `AVAudioSourceNode` → main mixer, at the hardware sample rate.
- The engine restarts after route changes, interruptions and media-server resets.
- Target latency from hinge event to sound: **< 30 ms**. Measured CPU, worst case of all 24 voices plus the creak: **0.7 % of one core in Release**. In unoptimized Debug builds typical use costs ~10 %, and the never-reached worst case ~58 %.

### 6.4 Tuning loop

`make sounds` compiles `Audio/DSP` with a small macOS tool (`Tools/RenderSounds`) and writes `build/sounds/*.wav`: knock, unlatch, latch-gentle, latch-firm, slam, open-stop, creak-slow, creak-open and a full **sequence** (knock knock, open, stop, slam). It prints peak/RMS per file. Listen with `afplay build/sounds/sequence.wav`, adjust `SoundProfile.oak`, repeat. Current levels: one-shots peak −1 to −6 dBFS; full-speed creak −2 dBFS; slow creak −12 dBFS.

### 6.5 Angle normalisation (planned)

Because the hardware range is undocumented, record the angle at the `closed → partiallyOpen` transition (`θ₀`) and at `→ fullyOpen` (`θ₁`) and map the leaf's visual rotation over `[θ₀, θ₁]`. The MVP uses the simple `0…180 → 0…100°` mapping until device data is available.

### 6.6 Ideas for later

- Per-style extras: a dedicated door-knocker voice (metal ring), chain rattle, fridge-seal "thwup" (filtered noise burst with a pitch drop), airlock hiss.
- Spatialisation on headphones (knock appears to come from "behind" the door).
- Let creak character drift over a session (the door "warms up").

## 7. Door styles (extensibility)

A style is: **palette / artwork + `SoundProfile` + motion profile** (thresholds, max swing). Adding one should touch only `DoorStyle`, its artwork and its `SoundProfile` numbers.

Backlog of ideas (any hinged thing works):

| Style | Twist |
|---|---|
| Oak door, iron hinges | **MVP** |
| Barn door | Heavy, slow, deep creak |
| Saloon doors | Two leaves; swing-back wobble after release |
| Castle gate | Chains, echo, very slow |
| Fridge | Seal "thwup", interior light, hum |
| Car door | Satisfying "thunk", key chime when open |
| Window shutters | Wind, birds outside |
| Treasure chest | Gold glint and "ta-da" on full open |
| Spaceship airlock | Hiss, no creak |
| Haunted door | Creak never quite stops… |

Later, `DoorStyle` moves from an enum to a `Codable` struct loaded from a bundled JSON catalogue so styles can be added without code changes.

---

## 8. Testing strategy

| Level | How | What |
|---|---|---|
| Unit | Swift Testing (`DuorTests`) | `DoorMotionInterpreter`: first sample silent, unlatch, swing direction, creak threshold, close classification, long-pause clamp, open stop. `DoorSynth`: silent when idle, every sound audible / finite / ≤ 0 dBFS / decays, deterministic per seed, knocks vary, creak follows speed and fades, command bursts bounded. **Runs in CI.** |
| Audio | `make sounds` + listening | Timbre and balance (§6.4). |
| Simulator, manual | iPhone Duo simulator, fold via Xcode Device Hub or `hinge` CLI | Outside/inside switching, cover display layout, settings sheet. |
| Simulator, scripted | `hinge sweep 0 120 1` (slow open), `hinge sweep 120 0 0.15` (slam) | Event sequences and sound choice. Simulator angles are clean; use only for logic, not tuning. |
| Device | Real iPhone Duo | **Threshold tuning**, audio latency, actual update rate, closed-angle reading, cover-display behaviour when folding (see risks). Log samples with `os.Logger` + Instruments "Points of Interest" to build a dataset for tuning. |
| Accessibility | VoiceOver, Reduce Motion, Dynamic Type | Labels on door states, knock as an accessible action, swing animation reduced. |

---

## 9. Risks and open questions

| # | Risk / question | Mitigation / next step |
|---|---|---|
| 1 | **Does the app stay in the foreground on the cover display when folded?** If iOS locks the phone or returns home on fold, knocking breaks. | Verify on device first thing. Simulator observations say the app continues on the cover display. If needed, guide the user to the relevant system setting. |
| 2 | Hinge update rate on device may be low or bursty, making slam detection noisy. | Status-based events + clamped Δt + smoothing; tune with recorded device data. |
| 3 | `.closed` status may fire before the halves physically touch (or after), so the latch sound could be early or late. | Measure on device; optionally delay the latch by a few ms or trigger on a small-angle threshold while still closing. |
| 4 | App Store Guideline 4.2 (minimum functionality): "novelty" apps can be rejected. | Several door styles, polish, haptics and a showcase of the Duo hardware before submission. |
| 5 | Silent switch: should a toy app play with the ringer off? | MVP: plays (`.playback`). Add a setting "Respect silent mode". |
| 6 | Synthesized sound may not convince everyone. | Tuning loop (§6.4); test on device speakers and headphones; samples could still be layered in later behind the same protocol. |
| 7 | Accessibility of a sound-first app for deaf/HoH users. | Haptics on every event + optional on-screen captions ("*creeeak*", "*SLAM*"). |
| 8 | Which half carries the cover display. The art assumes a book-style fold with the hinge on the cover's left edge, so the cover half becomes the left half when open. | Verify on device; flipping it is one `hingeSide` value per view. |

---

## 10. Roadmap

| Milestone | Content |
|---|---|
| **M0 — Scaffold** ✅ | Xcode project (JSON format), app shell, interpreter + tests, audio engine, settings sheet, CI, lint. |
| **M1 — MVP sound** ✅ synth / ⏳ device | Hand-rolled synth for all sounds ✅. Still open: tune thresholds and levels on a real device, latency check. |
| **M2 — MVP visuals** ✅ mostly | Door art (outside + inside face) ✅, room ✅, hinges on the crease ✅, knock dent + slam shake ✅, haptics per event ✅, portrait lock ✅. Still open: Reduce Motion, onboarding hint. |
| **M3 — Polish** | Haptic tuning, captions, angle normalisation (§6.3), app icon, onboarding hint ("fold me"). |
| **M4 — Styles** | Style catalogue as data; 3–5 new doors; thumbnail picker. |
| **Later** | "Knock anywhere" (accelerometer tap detection on the back), Android port via cross-platform hinge libs, shared "door of the day". |

---

## 11. References

- Apple: [`onHingeChange(isEnabled:_:)`](https://developer.apple.com/documentation/swiftui/view/onhingechange(isenabled:_:)), [`ArrangementView`](https://developer.apple.com/documentation/swiftui/arrangementview), [`reservedRegions(kind:options:layoutDirectionBehavior:)`](https://developer.apple.com/documentation/swiftui/geometryproxy/reservedregions(kind:options:layoutdirectionbehavior:)), tech talks [111462](https://developer.apple.com/videos/play/tech-talks/111462/), [111463](https://developer.apple.com/videos/play/tech-talks/111463/), [111464](https://developer.apple.com/videos/play/tech-talks/111464/)
- SDK headers: `UIKit.framework/Headers/UIHinge.h`, `UIHingeInteraction.h`; `SwiftUICore.swiftinterface` (`DeviceHinge`, `DeviceHingeContext`)
- Physical modelling background: modal synthesis (Adrien, *The Missing Link: Modal Synthesis*, 1991); stick-slip friction sounds (Avanzini, Serafin, Rocchesso, *Interactive simulation of rigid body interaction with friction-induced sound generation*, 2005); Freeverb (Jezar, 2000)
- [Accorduon](https://github.com/artemnovichkov/Accorduon) · [iPhone-Duo-by-Examples](https://github.com/artemnovichkov/iPhone-Duo-by-Examples) · [hinge CLI](https://github.com/artemnovichkov/hinge)
- [Reading the iPhone Duo hinge angle with onHingeChange](https://bleepingswift.com/blog/onhingechange-hinge-angle-swiftui) (Bleeping Swift)
- [What can the APIs added in iOS 27.1 for iPhone Duo do?](https://dev.classmethod.jp/en/articles/ios27-1-iphone-duo-new-apis/) (Classmethod)
- [iPhone Duo hinge, poses and adaptive layouts](https://fitsduo.com/guides/hinge-and-poses) (FitsDuo)
- [Six APIs developers have not used before](https://www.macobserver.com/news/iphone-duo-new-apis-developers-have-not-used-before/) (The Mac Observer)
- [expo-hinge](https://docs.expo.dev/versions/latest/sdk/hinge/) · [expo-foldables](https://github.com/azizbecha/expo-foldables) · [hinge-guess](https://github.com/erkamyaman/hinge-guess)
