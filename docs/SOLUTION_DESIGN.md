# Duor — Solution Design

> A door simulator for the foldable iPhone Duo. The phone *is* the door: fold it shut and you see the outside of a door you can knock on; unfold it and the door swings open with a creak; fold it again and it closes with a latch — or a slam.

| | |
|---|---|
| **Status** | Draft v0.7 — 26 Oct 2026 (spaceship and metal doors, forest deer, picker grid) |
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
- Swipe to open and close the door on any screen, so it also works on non-Duo iPhones (§4.2, "Swiping").

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
| `hinge` is `nil` on non-foldables. | Swiping opens the door; the app is still usable everywhere. |
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

1. **On a real Duo, the screen on the swinging half never animates the swing.** The phone half physically rotates, so it *is* the door. Its screen shows the leaf's inside face standing still; drawing a 3D swing on top would count the motion twice (that was the v0.1 bug). Where nothing swings physically (the Simulator, the cover display, phones without a hinge) the leaf swings on screen at the true angle: it stands at 180° − hinge angle to the doorway.
2. **The door is fixed to the device.** The inner display is a resizable scene, which ignores the Info.plist orientation list, and the system's rotation animation spun the whole window through 90° and back. The app is therefore hosted in UIKit (`AppDelegate` → `SceneDelegate` → `DoorHostingController`, a `UIHostingController` subclass) so its root view controller can set **`prefersInterfaceOrientationLocked = true`** (iOS 26+). With the lock, turning the phone turns the door with it and nothing re-lays out. When the system lifts the lock (not full screen, e.g. Split View) `DeviceFixed` still counter-rotates the scene: each screen has a fixed upright shape (inner: wide book posture; cover: tall), and the last landscape device orientation says which way to turn back.

   *Tried and rejected:* the Info.plist orientation list and `supportedInterfaceOrientations` (ignored by resizable scenes); suppressing the rotation animation (it runs outside the app); `UIRequiresFullScreen` (deprecated, and it locked the interface to the inner panel's native orientation, which is the device's landscape).

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

**Controls.** The settings button is a toolbar item with `axisBehavior(.verticalPreferred)` (in a `NavigationStack` with a hidden bar), and so is the settings sheet's Done button. On the iPhone Duo both sit in the system's vertical control lane on the trailing edge, folded and unfolded.

**Which face to draw.** With a real hinge, the app follows the *screen*, not the hinge status: the system decides when to switch displays, and a slightly opened phone often stays on the cover display. Only the inner display reports a fold region (`reservedRegions(kind: .division, options: .includeInactive)`, inactive when flat); the cover never does. So `RootView` draws the inside view when a fold region exists (or the hinge is fully open), and the outside face otherwise, unless the door has been swiped open. Screen shape can't be used, because the inner display can rotate. Without a hinge there is one screen, which shows the inside view whenever the swiped door is open.

**Swiping.** On every screen, swiping left opens the door and swiping right closes it (the way its free edge moves in both views); a swipe across 85% of the width is a full swing. The gesture sits on `RootView`'s container, not on either face, because the face changes mid-swipe as the door unlatches, and it is measured along the door's own axis (undoing any `DeviceFixed` turn). `DoorDrive` (pure, tested) decides where the door is:

- The hinge has the door until the user swipes; then the swipe has it until the two agree again.
- **Inner display:** the phone half is the leaf, so a swipe can close the door further than the phone (the leaf is drawn swung in from the phone half, up to across the doorway) but never open it past the phone. The hinge takes over again once the door is swiped open as far as the phone, or the phone is folded down to meet the door, so folding a swiped-shut phone stays silent.
- **Single screen** (cover display, no hinge): the whole swing is drawn and the swipe can take the door from shut to flat. It hands back to the hinge once swiped shut.
- **Changing screens** hands the door back to the hinge. If the angle jumps (swiped open on the cover, then unfolded), the interpreter restarts instead of hearing a slam.

On release, `DoorFling` carries the door on with the swipe's speed under friction, so a flick slams it and a push leaves it ajar; within 10° of shut a slow door swings itself shut gently. The fling and the drag feed the interpreter like hinge samples (~60 Hz), so creaks, the open stop and close kinds work unchanged. Without a hinge, a "Swipe left to open the door" hint shows until the door has been opened once. VoiceOver users get "Open door" and "Close door" actions. On a foldable, swiping can be turned off in Settings (§4.3).

### 4.3 Settings

A gear button opens a sheet with three picture pickers. Choices persist with `@AppStorage` and combine into one `DoorLook` (style + hardware + scene) that drives both the art and the synth.

| Setting | Options | Notes |
|---|---|---|
| **Door** | Oak, Cottage, Barn, Castle, Spaceship, Metal | Picking a door resets the hardware and the scene to the door's own. Shown as a grid so every door is always visible: four per row folded (or without a hinge), all in one row unfolded. |
| **Hardware** | Iron, Brass, Chrome, Copper, Bronze | Colors and shine of hinges, handle, studs and strike plate, *and* the pitch and ring of the latch and hinges. |
| **Behind the door** | Living room, Great hall, Beach, Forest, Outer space, Brick wall | Picking a door also picks its scene (Oak → living room, Cottage → beach, Barn → forest, Castle → great hall, Spaceship → outer space, Metal → brick wall). |
| **Swipe mode** | On (default), off | Whether the door can be swiped open and shut (§4.2). Only shown with a hinge: without one, swiping is the only way in, so it stays on. Turning it off hands a swiped door back to the hinge. |

Hinge updates are paused (`isEnabled: false`) while the sheet is open, so browsing doesn't creak. Debug builds open the sheet on launch with `-showSettings YES` (for screenshots and UI tests); all three settings can also be passed as launch arguments, e.g. `-doorStyle castle -hardware bronze -insideScene space`.

### 4.4 Living scenes

Each scene is drawn in three layers: the still background (drawn once), a **life** layer at up to 30 fps (`SceneLife`, a `TimelineView`, paused while the door is too shut to see in), then the darkness and the door frame on top, so visitors pass *behind* the frame.

| Scene | Ambient | Visitors |
|---|---|---|
| Living room (a small cabinet with a vase of flowers) | Pendant lamp sways | A ginger cat walks past close by or further back, or peeks in from the side, looks around and goes back; a beagle trots past (tail wagging, tongue out) |
| Great hall | Torch flames flicker and glow | A little knight on patrol; a bat |
| Beach (shells, a starfish, rippled sand) | Waves roll, foam breathes, clouds of different shapes drift by | Seagulls; a crab scuttling sideways; a sailboat on the horizon; a leaping dolphin with splashes; a cruising shark fin |
| Forest (a winding path into a glowing passage, hazy pine layers, a leafy canopy arch, sunbeams, bushes on the left, trunks on the right) | Leaves drift down | A deer pops up from behind a bush, looks right at you, blinks, twitches an ear, and ducks back down, or bolts out and runs off to the right behind the trees; birds; a hopping rabbit |
| Outer space (a distant spiral galaxy in soft nebula haze) | Stars twinkle | Shooting stars; a UFO with blinking lights; a tumbling astronaut |
| Brick wall (shaded, pitted, chipped bricks; grime; moss; ivy climbing) | — | A spider drops in to say hi; a very determined snail |

Visits are a pure function of time: each period gets one visit at a seeded random moment, direction and lane, so nothing is stored and every frame is cheap.

### 4.5 The animated leaf

The drawn leaf has weight. It follows the hinge on a slightly bouncy spring (`SwingingLeaf`, an `Animatable` view), so it lags a touch behind a fast fold and bounces off the stop. When the inside view appears, the leaf swings open from shut. Past 90° of on-screen rotation it shows its outside face, as a real door would.

- **Simulator, cover display and phones without a hinge:** the whole swing is drawn: the leaf stands at (180° − spring angle) to the doorway.
- **Real Duo:** the screen half already stands at the physical angle, so only the spring's lag is drawn (physical − spring, clamped), never the full swing twice.

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
 │     │                  swipe → DoorDrive /       DoorMotionInterpreter     │
 │     │                  DoorFling (pure)          (pure value type)         │
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
| `App/RootView.swift` | Picks outside vs. inside view, hosts `onHingeChange` and the swipe gesture, settings sheet, haptics, swipe hint. |
| `Hinge/HingeReading.swift` | Our own `Sendable` value type for one hinge sample (degrees, status, monotonic timestamp). Decouples logic from `DeviceHinge` so it can be unit tested and simulated. |
| `Door/DoorMotionInterpreter.swift` | **Pure** state machine: `ingest(HingeReading) -> [DoorEvent]`. Computes smoothed velocity, emits `unlatched`, `swing(velocity)`, `hitOpenStop(speed)`, `closed(CloseKind)`. Fully covered by unit tests. |
| `Door/DoorSwipe.swift` | **Pure** swipe logic: `DoorDrive` (hinge or swipe, per screen), `DoorSwipe` (points → degrees), `DoorFling` (momentum after release). Unit tested. |
| `Door/DoorController.swift` | `@Observable` glue: holds the latest hinge reading and the `DoorDrive`, runs the fling, feeds the door angle to the interpreter, maps events → sounds, debounces the creak fade, exposes `isClosed`, `angle`, `isSwiped`. |
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
on reading r:
  first reading               → remember it; latched if r.deg ≤ 2°
  moved = r.deg − anchor.deg  (anchor = last accepted position)
  |moved| ≥ 1.5°              → v_i = moved / clamp(Δt, 1/240 s, 0.5 s); v += (v_i − v) · 0.5; anchor = r
  otherwise, still > 0.3 s    → v = 0
  impact = max(|v_i|, |v|)

  latched ∧ r.deg ≥ latched angle + 3°    → unlatched
  ¬latched ∧ moved ∧ |v| ≥ 6 °/s          → swing(v)
  stop armed ∧ r.status == fullyOpen      → hitOpenStop(impact); re-arms 8° back from the stop
  ¬latched ∧ r.deg ≤ 2°                   → closed(gentle < 90 °/s ≤ firm < 260 °/s ≤ slam); latched

on 0.35 s without readings (settle):
  ¬latched ∧ last.status == closed ∧ last.deg ≤ 15° → closed(…); latched
```

Real readings jitter by a fraction of a degree and the status can flicker at the closed and fully-open points, which used to make the door creak while lying flat and click repeatedly when shut. So:

- **Jitter tolerance (1.5°):** velocity is measured from the last *accepted* position; smaller changes are ignored. Slow real motion still gets through after a few samples, with its true elapsed time.
- **Latch by angle, not status.** The system's `.closed` status means "too shut for the inner display" and switches on as early as ~85° while folding (measured in the simulator: open → partiallyOpen at ~20°, back to closed at ~84°). The door latches at ≤ 2°. Updates thin out near shut (the last sample can read ~10° while the hinge is at 5°), so a hinge that comes to rest at ≤ 15° with the system reporting closed latches after 0.35 s of stillness.
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

### 6.6 Door types and metals

Each door type is a `SoundProfile` preset (its wood, frame, creak and room) plus a `SoundCharacter`, the signature that makes it recognizable. The hardware metal then retunes the latch, hinges and hinge squeal (`SoundProfile.with(metal:)`).

| Door | Wood and room | Signature |
|---|---|---|
| Oak | Solid oak (the reference wood), small hallway. Knock: a soft, warm **fist knock** (padded contact, damped, a little frame thud, no snap) | — |
| Cottage | Painted pine: higher, lighter creak. Knock: a crisp **knuckle knock** with a sharp snap | **Glass panes rattle** on latches and slams |
| Barn | Big weathered boards: low, long groaning creak, wide space | **Loose boards clatter** after hits |
| Castle | Massive oak, very low, slow loud groan, stone-hall echo. Knock: heavy and dark, with a deep thump of the whole leaf | **Heavy iron bolt**: low, long clanks, a scrape when drawn |
| Spaceship | Thin aluminum hull: bright, short metallic "dink" knocks, a hollow aluminum frame, a quiet servo hum instead of a creak | **Airlock**: a pneumatic hiss when it unseals and seals; a damper instead of a slam (soft thud, magnetic click) |
| Metal | Steel plates that ring briefly; knock is a metallic "bong"; stairwell echo | **Squealing hinge**: metallic and tonal but low and breathy (centroid ~1 kHz), a booming slam that settles in under a second |

| Metal | Latch and hinges |
|---|---|
| Iron | Reference: dull clack |
| Brass | Lower (×0.86), rings longer (×1.45) |
| Chrome | Brighter (×1.22), rings longer (×1.25) |
| Copper | Lower and softer (×0.8, ×0.95) |
| Bronze | Lowest (×0.74), slightly longer (×1.15) |

`make sounds` renders `door-<type>.wav` for every door (knock knock, open, stop, slam) plus oak with brass and chrome.

### 6.7 Ideas for later

- Per-style extras: a dedicated door-knocker voice (metal ring), chain rattle, fridge-seal "thwup" (filtered noise burst with a pitch drop), airlock hiss.
- Spatialisation on headphones (knock appears to come from "behind" the door).
- Let creak character drift over a session (the door "warms up").

## 7. Door styles (extensibility)

A door type is a case in `DoorStyle` with: a `DoorDesign` (how the leaf is drawn), surface colors, a default `HardwareFinish`, and a `SoundProfile` preset. Adding one touches only `DoorStyle`, a drawing case in `DoorArt.swift` if it needs a new design, and a preset in `SoundProfile.swift`.

| Shipped | Design | Default metal |
|---|---|---|
| Oak | Four raised panels, knob, peephole | Iron |
| Cottage | Painted, four-pane window, two panels, knob | Brass |
| Barn | Vertical boards, Z brace, strap hinges, D-pull | Iron |
| Castle | Boards, iron bands with studs, strap hinges, ring pull | Bronze |
| Spaceship | Chamfered hull panel, porthole with stars, glowing light strips, control pad, hazard stripes | Chrome |
| Metal | Brushed riveted steel, wired-glass window, vent louvre, diamond-plate kick plate, lever handle | Iron |

Ideas for more: saloon doors (two leaves, swing-back wobble), fridge (seal "thwup", light inside), car door (thunk, key chime), window shutters (wind, birds), treasure chest (ta-da), airlock (hiss), haunted door (the creak never quite stops). Scenes: a scene is one painter function in `InsideScenes.swift`.

## 8. Testing strategy

| Level | How | What |
|---|---|---|
| Unit | Swift Testing (`DuorTests`) | `DoorMotionInterpreter`: first sample silent, unlatch, swing direction, creak threshold, close classification, long-pause clamp, open stop, jitter and flicker silence, hysteresis. `DoorSynth`: silent when idle, every sound for every door type audible / finite / ≤ 0 dBFS / decays, door types sound different, deterministic per seed, knocks vary, creak follows speed and fades, command bursts bounded. **Runs in CI.** |
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
| **M4 — Styles** ✅ | Five doors, five metals, five scenes, picture pickers, per-door sound signatures, animated leaf. |
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
