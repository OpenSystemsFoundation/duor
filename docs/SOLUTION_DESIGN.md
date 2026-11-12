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
| Tap on cover | Knocked | Soft shadow blooms where the knuckle hit; door jiggles 1.5 pt | Knock (synthesized, every one different, shaped by where it lands) | Heavy impact |
| `.closed → .partiallyOpen` | Unlatching | Whatever screen the system keeps on (often still the cover: then the outside face stays) | Latch release click | Light impact |
| Angle changing | Swinging | Inner display: leaf's inside face (still) + doorway; the room lights up from ~10° to ~120°, hinge-side shadow on the leaf fades | Creak: volume and pitch ∝ speed; fades when updates stop | — |
| `→ .fullyOpen` | Hits stop | Leaf flat against wall | Soft thud, scaled by impact speed | Soft impact |
| `→ .closed`, slow | Gently closed | Back to cover | Quiet latch click | Light |
| `→ .closed`, medium | Firmly closed | Back to cover, 3 pt bump | Full latch click | Medium |
| `→ .closed`, fast | Slammed | Back to cover, door shakes 8 pt in its frame | Slam + frame rattle | Heavy |

Knocking is only enabled while closed (you knock on a closed door).

**Controls.** The settings button is a toolbar item with `axisBehavior(.verticalPreferred)` (in a `NavigationStack` with a hidden bar), and so is the settings sheet's Done button. On the iPhone Duo both sit in the system's vertical control lane on the trailing edge, folded and unfolded.

**Which face to draw.** With a real hinge, the app follows the *screen*, not the hinge status: the system decides when to switch displays, and a slightly opened phone often stays on the cover display. Only the inner display reports a fold region (`reservedRegions(kind: .division, options: .includeInactive)`, inactive when flat); the cover never does. So `RootView` draws the inside view when a fold region exists (or the hinge is fully open), and the single-screen door (`DoorSlideView`) otherwise. Screen shape can't be used, because the inner display can rotate. Without a hinge there is only the single-screen door.

**Swiping.** On every screen, swiping left opens the door and swiping right closes it (the way the door moves in both views); a swipe across 85% of the width is a full swing. The gesture sits on `RootView`'s container, not on the door, because the door slides off the screen mid-swipe, and it is measured along the door's own axis (undoing any `DeviceFixed` turn). `DoorDrive` (pure, tested) decides where the door is:

- The hinge has the door until the user swipes; then the swipe has it until the two agree again.
- **Inner display:** the phone half is the leaf, so a swipe can close the door further than the phone (the leaf is drawn swung in from the phone half, up to across the doorway) but never open it past the phone. The hinge takes over again once the door is swiped open as far as the phone, or the phone is folded down to meet the door, so folding a swiped-shut phone stays silent.
- **Single screen** (cover display, no hinge): the swipe can take the door from shut to flat open, and hands back to the hinge once swiped shut. The door is not drawn swinging (half door, half frame looks wrong on one screen): the doorframe fills the screen and the door's outside face lies on top of it. Opening slides the door off the leading edge, lifted slightly (scaled up, with a shadow on the frame), until the whole doorway shows; closing slides it back over the frame until it lands and rattles shut. `DoorSlide` (pure, tested) maps the angle to how far the door has slid, its lift, and its offset.
- **Changing screens** hands the door back to the hinge. If the angle jumps (swiped open on the cover, then unfolded), the interpreter restarts instead of hearing a slam.

On release, `DoorFling` carries the door on with the swipe's speed under friction, so a flick slams it and a push leaves it ajar; within 10° of shut a slow door swings itself shut gently. The fling and the drag feed the interpreter like hinge samples (~60 Hz), so creaks, the open stop and close kinds work unchanged. Without a hinge, a "Swipe left to open the door" hint shows until the door has been opened once. VoiceOver users get "Open door" and "Close door" actions. On a foldable, swiping is off until turned on in Settings (§4.3).

### 4.3 Settings

A gear button opens a sheet with three picture pickers. Choices live in `DoorSettings` (saved to `UserDefaults`) and combine into one `DoorLook` (style + hardware + scene) that drives both the art and the synth.

| Setting | Options | Notes |
|---|---|---|
| **Door** | Oak, Cottage, Barn, Castle, Spaceship, Metal | Picking a door resets the hardware and the scene to the door's own. Shown as a grid so every door is always visible: four per row folded (or without a hinge), all in one row unfolded. |
| **Hardware** | Iron, Brass, Chrome, Copper, Bronze | Colors and shine of hinges, handle, studs and strike plate, *and* the pitch and ring of the latch and hinges. |
| **Behind the door** | Living room, Great hall, Beach, Forest, Outer space, Brick wall | Picking a door also picks its scene (Oak → living room, Cottage → beach, Barn → forest, Castle → great hall, Spaceship → outer space, Metal → brick wall). |
| **Swipe mode** | Off (default with a hinge), on | Whether the door can be swiped open and shut (§4.2). Only shown with a hinge: without one, swiping is the only way in, so it stays on. With a hinge the hinge opens the door, so swiping starts off; a choice the user saved is kept (`SwipeMode`). Whether there is a hinge is detected at runtime from the first `onHingeChange` sample, not from the device model, so any foldable counts. Turning it off hands a swiped door back to the hinge. |
| **Language** | The device's language | Shows the language in use, named in itself ("Deutsch", "日本語"). Tapping it opens Duor's page in the Settings app, where iOS keeps the per-app language choice; Duor has no picker of its own (§4.6). |

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

### 4.6 Languages

Duor ships in 15 languages: English (the source) plus Arabic, Chinese (Simplified and Traditional), Dutch, French, German, Italian, Japanese, Korean, Polish, Portuguese (Brazil), Russian, Spanish and Turkish. All strings live in `Resources/Localizable.xcstrings`; iOS picks the language from the device, or from Duor's own language setting in the Settings app.

- **Right-to-left:** the door is a physical object on the phone's hinge, so the door view is forced `.leftToRight` in every language (`RootView`). Settings still mirrors in Arabic. The swipe hint arrow stays left-to-right too, because "left" means the screen's left.
- **App Store:** one listing per language in `appstore/release.json` (16 locales: Spanish has both `es-ES` and `es-MX`), each with translated screenshot captions.

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
| `App/RootView.swift` | Picks the inner-display or single-screen view, hosts `onHingeChange` and the swipe gesture, settings sheet, haptics, swipe hint. |
| `Hinge/HingeReading.swift` | Our own `Sendable` value type for one hinge sample (degrees, status, monotonic timestamp). Decouples logic from `DeviceHinge` so it can be unit tested and simulated. |
| `Door/DoorMotionInterpreter.swift` | **Pure** state machine: `ingest(HingeReading) -> [DoorEvent]`. Computes smoothed velocity, emits `unlatched`, `swing(velocity)`, `hitOpenStop(speed)`, `closed(CloseKind)`. Fully covered by unit tests. |
| `Door/DoorSwipe.swift` | **Pure** swipe logic: `DoorDrive` (hinge or swipe, per screen), `DoorSwipe` (points → degrees), `DoorFling` (momentum after release), `DoorSlide` (how the single-screen door slides). Unit tested. |
| `Door/DoorController.swift` | `@Observable` glue: holds the latest hinge reading and the `DoorDrive`, runs the fling (on an injected `DoorClock`, so tests run without waiting), feeds the door angle to the interpreter, maps events → sounds, debounces the creak fade, exposes `isClosed`, `angle`, `isSwiped`. |
| `Door/DoorStyle.swift` | Style catalogue: door styles, hardware finishes, scenes. Palette + `SoundProfile` per style. |
| `Door/DoorArt.swift` | `Canvas`-drawn four-panel leaf (grain, raised panels, iron hinges, knob, peephole) with `hingeSide` mirroring; shared `DoorGeometry` so hinges, knob and strike plate line up across views. |
| `Door/DoorwayArt.swift` | The fixed half: casing, jambs, strike plate, and the lit room beyond. |
| `Door/DoorOutsideView.swift` | Cover display: outside face, tap-to-knock with dent and shake. |
| `Door/DoorSlideView.swift` | Single screen: the doorframe fills the screen; the outside face slides off it when swiped open and back on top when swiped shut. |
| `Door/DoorInsideView.swift` | Inner display: splits at the crease, leaf inside face + doorway, hinge straps across the crease, light driven by angle. |
| `Door/Scenes/*` | What's behind the door, one file per scene: its still background (`ScenePainter`), its moving life (`SceneLife`) and its cat. `Scenes.swift` holds the dispatch and the shared visit timing, `Cats.swift` the cat drawing. |
| `Audio/DoorAudioEngine.swift` | Audio session, `AVAudioEngine` with one `AVAudioSourceNode` that calls `DoorSynth.render`, restart on route change / interruption. Behind the `DoorSoundPlaying` protocol for tests. |
| `Audio/DSP/*` | The synthesizer: `DoorSynth` (thread hand-off + sound recipes), `ImpactVoice`, `KnockSpot` (how a knock's position shapes it), `CreakVoice`, `ModalBank`, `RoomReverb`, `NoiseSource`, `SoundProfile` (per-style materials). Pure Swift, no AVFoundation, so it is unit tested and renders offline. |
| `Settings/DoorSettings.swift` | `@Observable` model of everything picked in Settings, saved to `UserDefaults`. Picking a door brings its hardware and scene. |
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

Rebuilt in 1.1 following `docs/2026-11-10-hinge-sound-improvement.md` (the findings and the reasons are there).

| Block | Model | Used for |
|---|---|---|
| `ModalBank` | 8 two-pole resonators in SIMD lanes. Each lane is one vibration mode of an object: frequency, decay time, gain. Input is scaled by `sin ω` so every mode peaks at its gain. `ModeSet` describes 8 modes; metal parts have two close-spaced pairs for a slight beat. | The "material" of anything struck or scraped. |
| `ImpactVoice` | A **half-sine contact force** driving a `ModalBank`, plus **contact noise** (`ContactNoise`: a band-passed noise burst of 2–20 ms per material, the "crack"). **Hardness** (from the event's speed, `DoorStrength`) shortens the contact, tilts the modes of the middle (250 Hz to 2 kHz) up and makes the crack louder and brighter. Two things keep every hit soft on the ear: **highs die sooner** (a loss that grows with the square of the frequency is added to every mode: at 3 kHz nothing rings longer than 12 ms to 1/e, at 6 kHz 3 ms), and the **crack has a top** (a low-pass that opens with hardness from 1.5 to 4.5 kHz, never more than two octaves above its band). Optional mild saturation per hit (knocks, slams). When all 24 voices are busy the one furthest into its decay is stolen, and fades over 2 ms. Random ±3–5 % detune and ±10 % decay per hit. | Knocks, latch clicks, thuds, slams, rattles. |
| `CreakVoice` | **Tension and release.** Tension builds with the distance the door moves; past a threshold (redrawn per slip) the pin slips: a shaped pulse as loud as the tension released, with a short scrape of sliding noise after it. The door's `FrictionMap` (a seeded floor with a few tight spots, shifted and weaker when closing) sets threshold and loudness, so the creak comes and goes at the same angles. Slow = few strong countable slips, faster = a soft rasp, above a per-door speed only friction noise. Pitch comes from the door's body modes, not from hand speed. Metal can lock to a body mode for a short squeal; the spaceship has a tonal servo hum (`ServoHum`) instead. | The creak. |
| `SwingBedVoice` | Air (band-passed noise, level with speed²) and hinge roll (sparse soft ticks of the hinge modes, per degree of travel), all through the room. | The quiet "it moves" sound under the creak. |
| `RoomReverb` | **Feedback delay network**: pre-delay, up to four early reflections, two input allpasses and eight lines through a Householder matrix, with decay and damping per room (`RoomAcoustics`). Sleeps when silent; a change of room fades over 12 ms. Two instances: the door's own room (`SoundProfile.space`) and the **space beyond the doorway** (`SceneAcoustics`, from the inside scene), which mixes in as the door opens, following the hinge angle. | Oak hallway ≈ 0.4 s, castle stone hall ≈ 1.8 s; the great hall blooms as the door opens, the beach takes room away. |
| `SpeakerVoicing` | On the built-in speaker only (follows the audio route): virtual bass (rectified lows → overtones at ~400 Hz), 24 dB/oct cut at 150 Hz, +3 dB at 380 Hz, −2 dB above 9 kHz, a fast 3:1 compressor with make-up gain. Glides in and out over 50 ms. After duomin's speaker stage. | Phone speakers can't play the lows where most of a knock lives. |
| Master | Per-door `trim` × `DoorSynth.mixGain`, voicing, then a **`PeakLimiter`** (1.5 ms lookahead, 80 ms release) and a `tanh` soft clipper as the safety net. A single event reaches the clipper at or below 0 dBFS, so attacks stay clean; stacked hits are turned down as a whole. | Loudness without waveshaping every hit; doors within a few dB of each other. |
| `NoiseSource` | xorshift32, seeded. | Roughness, randomness; deterministic in tests. |

### 6.2 Sound recipes

Each one-shot is a few strikes on the style's materials (`SoundProfile`: `panel`, `frame`, `latch`, `hinge` mode sets + a `CreakProfile`):

| Sound | Recipe |
|---|---|
| Knock | Dedicated `knock` modes: the same oak, heavily damped by the hand (7–28 ms decays, 160 Hz–1.35 kHz). 0.8–1.2 ms contact (knuckle), ±3 % pitch, plus a 0.2 ms knuckle snap ~1.7 octaves up. Mostly dry (reverb send 0.3) so it sounds close and tight, not hollow. Wood rings out in ~100 ms. **Where it lands** (`KnockSpot`): the profile's knock is the middle of the door, slightly deeper there; toward the edges the leaf is stiffer, so up to 8 % higher, shorter (0.7× decay, 0.7× contact), more snap and frame thud, with modes tilted toward the high ones. Each mode is also weighted by how much its plate mode (door ≈ 1:2) moves at that spot, so equally central spots still differ. Near the handle the latch bolt ticks faintly. **Same spot twice**: each knock lands ±3 % off target, with ±14 % per-mode gain and ±30 % snap jitter. |
| Unlatch | Two soft spring ticks of handle and spindle, a short falling scrape as the bolt draws back, its click, then the leaf letting go of its stop (a low, quiet frame thud). No speed: the handle turns at the same pace however the door then swings. Castle: its iron bolt drawn (clank, scrape, clank). Spaceship: the airlock hiss. |
| Close (latch and slam) | One recipe, driven by the closing speed through `DoorStrength`: `force` (loudness), `hardness` (contact time and brightness), `boltDelay` (timing), `slamWeight` and `overSlam` (how much of a slam). The leaf meets its stop (frame + panel with their contact crack); the bolt touches the strike plate and rides up it (a rising scrape, noise through a gliding band that also rings the latch modes) until it snaps home 9 ms (thrown) to 80 ms (eased) later; the leaf touches a second time as it settles. Eased shut: more scrape, soft click. Firm: tight and bright. A slam is the same close and more, coming in gradually from 190 to 360°/s: air pushed ahead of the leaf (a 36 ms swell of 300–800 Hz noise before the hit), a stronger crack, the edge of the leaf knocking on its stop (the knock modes an octave up, 1 ms contact: what makes a harder close brighter, in the middle like a knock and not at the top), the ring of frame and leaf driven into a soft overload instead of a higher peak, a rebound 70–110 ms later, hinges rattling down, more of the room. Above 340°/s the blow itself eases off and what follows grows: a second rebound, a longer rattle. Under every click of the bolt the frame gives a small low thunk, so it is never a bare tick. The spaceship has a damper: above a firm close the speed is taken out, and what is heard is a padded thud, its seal hissing, and a magnetic catch. |
| Open stop | Each door's own (`DoorStop`): a rubber bumper for oak and cottage, a wooden post for the barn, an iron ring on stone that dances after the hit for the castle, an actuator end-stop with the motor winding down for the spaceship, a sprung steel stop for the metal door. Then the leaf's shudder: two soft frame thumps and a hinge tick. The stop's body sits at 300 Hz to 1 kHz, where a phone speaker plays. |
| Creak | Continuous; driven by signed hinge velocity, smoothed over 40 ms; fades out on its own when updates stop. |

Loudness is set against each door's slam on the tool's phone measure (voiced, loudest 300 ms in 200 Hz to 6 kHz): knock −4 dB, firm latch −6, open stop −8, gentle latch and unlatch −12, swing sound at most −10. `EventLevels` holds the per-door balance, `SoundProfile.trim` the level between doors; `make sounds` prints the table and marks misses.

**Soft on the ear.** The first 1.1 build was harsh on a real phone: a third of an unlatch or a cottage slam, and two thirds of the spaceship's close, sat in 2–5 kHz, where the ear is most sensitive and a phone speaker loudest. A real door closing is dark (most of its energy under 400 Hz, highs only in the first tenth of a second), and the app is for children. So over the first 200 ms, flat: closes have their centroid at about 700 Hz or lower and at most 8 % of their energy in 2–5 kHz, unlatches at most 15 %, open stops 10 %, and nothing has more than 3 % above 5 kHz (6 % with glass or a seal); the spaceship's closes stay under 1.5 kHz and 30 %. Besides the two rules in `ImpactVoice`: latch, hinge and glass modes fall off steeply above 2 kHz (about 9 dB per octave) and the glass sits around 1.4 kHz; the bolt's contact is 0.3 ms instead of 0.2; contact noise bands are lower (latch 2.4 kHz, was 5.2); the airlock's hiss and seal are around 1 kHz instead of 2–4; the creak's rasp stops at 2 kHz; rooms lose their highs faster (stone 0.33, stairwell 0.45, airlock 0.35 damping). Brightness still rises with closing speed, from a darker base. `make sounds` prints the table and marks misses; `RecipeTests.everySoundStartsDark` pins it.

Mode frequencies are chosen for a **phone speaker**, which reproduces little below ~250 Hz. Each sound's body sits around 200 Hz to 1.2 kHz, with lower modes kept for headphones.

### 6.3 Engine and latency

- `AVAudioSession` `.playback` + `.mixWithOthers`, preferred IO buffer 5 ms. *Open question: respect the silent switch? See §9.*
- One mono `AVAudioSourceNode` → main mixer, at the hardware sample rate.
- The engine restarts after route changes, interruptions and media-server resets.
- Target latency from hinge event to sound: **< 30 ms** (the limiter adds 1.5 ms). Measured CPU in 1.0, worst case of all 24 voices plus the creak: **0.7 % of one core in Release**. `make bench` measures it on the machine at hand; 1.1 costs about 20 % more than 1.0 there (two rooms, contact noise, the slip model), well under the 2 % budget. In unoptimized Debug builds expect several times more.

### 6.4 Tuning loop

`make sounds` compiles `Audio/DSP` with `Tools/RenderSounds` (no Accelerate, so it also builds on Linux) and writes `build/sounds/*.wav`: for every door, each event (knock, unlatch, gentle and firm latch, slam, open stop) and six swing gestures (slow, normal, fast, hesitating, wiggle, open and close) fed the way `DoorController` feeds the synth, flat and `speaker-` voiced, plus a full **sequence**, the metals, a closing-speed sweep, update rates and a burst of 200 hits. It prints loudness on a phone-speaker measure relative to each door's slam against the targets (knock −4 dB, firm latch −6, open stop −8, gentle latch and unlatch −12, creak at most −10), harshness (centroid and the shares of energy in 2–5 kHz and above 5 kHz over the first 200 ms of every event, flat and voiced, against the targets in §6.2), gain staging and limiter work, door balance, creak periodicity and pitch range, room decay, and render cost, and writes `build/sounds/metrics.json`; `make sounds BASELINE=old.json` prints before → after. `make audio-check` runs the audio and door-logic tests as a Swift package without Xcode.

### 6.5 Angle normalisation (planned)

Because the hardware range is undocumented, record the angle at the `closed → partiallyOpen` transition (`θ₀`) and at `→ fullyOpen` (`θ₁`) and map the leaf's visual rotation over `[θ₀, θ₁]`. The MVP uses the simple `0…180 → 0…100°` mapping until device data is available.

### 6.6 Door types and metals

Each door type is a `SoundProfile` preset (its wood, frame, creak and room) plus a `SoundCharacter`, the signature that makes it recognizable. The hardware metal then retunes the latch, hinges and hinge squeal (`SoundProfile.with(metal:)`).

| Door | Wood and room | Signature |
|---|---|---|
| Oak | An ordinary, well-fitted house door of solid oak: leaf and frame a little above the reference wood (×1.08, ×1.1) and damped more (ring ×0.7), the frame's lowest mode held back, tight hinges, a short click; a small carpeted hallway (0.34 s). A tidy "thock" that is over in half a second. Knock: a soft, warm **fist knock** (padded contact, damped, no snap, no frame boom) | — |
| Cottage | A light painted pine door, **the quiet one**: higher (×1.3), a boxy middle with little below 150 Hz, a short ring, a softer latch, a lighter creak, the smallest and driest room. Set about 4 dB under the oak door (2 to 2.5 dB on the phone's speakers). Knock: a crisp **knuckle knock** with a sharp snap | **Glass panes** tinkle faintly on latches and slams: a soft tink around 1.4 kHz |
| Barn | Big weathered boards: low (leaf ×0.67, frame ×0.72), ringing on for over a second, a long groaning creak, a wide space | **Loose boards clatter** after hits |
| Castle | Massive oak, **the deepest door**: leaf and frame an octave under the reference wood (×0.5) with the strongest modes between 100 and 250 Hz ringing twice as long, the 140 and 210 Hz frame modes brought up so the boom is there on a phone speaker too; slow loud groan, stone-hall echo. Knock: heavy and dark, with a deep thump of the whole leaf | **Heavy iron bolt**: low, long clanks (kept under the boom), a scrape when drawn |
| Spaceship | Thin aluminum hull: bright, short metallic "dink" knocks, a hollow aluminum frame, a quiet servo hum instead of a creak | **Airlock**: a soft pneumatic "pfff" (around 1 kHz) when it unseals and seals; a damper instead of a slam (padded thud, magnetic click) |
| Metal | Steel plates that ring briefly; knock is a metallic "bong"; stairwell echo | **Squealing hinge**: metallic and tonal but low and breathy (centroid ~1 kHz), a booming slam that settles in under a second |

| Metal | Latch and hinges |
|---|---|
| Iron | Reference: dull clack |
| Brass | Lower (×0.86), rings longer (×1.45), a slightly softer click (bite 0.8) |
| Chrome | Brighter (×1.22), rings longer (×1.25), the hardest click (bite 1.3) |
| Copper | Lower and dead (×0.82, ×0.8), the softest click (bite 0.6) |
| Bronze | Lowest and bell-like (×0.72, ×1.3), a soft click (bite 0.75) |

The metal also retunes a stop that is hardware (the castle's ring, the metal door's spring).

The four wood doors are kept apart on purpose (measured on a slam, flat): oak and cottage are short (T60 about 0.5 s) and sit around 700 Hz, barn rings 1.3 s around 480 Hz, castle 2 s around 350 Hz; barn and castle carry more than half of a slam's energy below 200 Hz, oak about 40 %, cottage under 30 %. The doors are levelled to within 7 dB of each other on a knock, open, slam sequence (4 dB on the phone's speakers), the cottage door lowest on purpose.

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

Ideas for more: saloon doors (two leaves, swing-back wobble), fridge (seal "thwup", light inside), car door (thunk, key chime), window shutters (wind, birds), treasure chest (ta-da), airlock (hiss), haunted door (the creak never quite stops). Scenes: a scene is one file in `Door/Scenes/` plus a case in `InsideScene`.

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
