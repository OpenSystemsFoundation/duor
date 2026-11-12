# Hinge sound: making the swing sound nice

2026-11-10 · branch `improve-hinge-sound` · status: plan, nothing implemented yet

## Why

Early feedback on 1.0: the sound the door makes while it swings is not pleasant. Knocks, latches and slams got no complaints.

Part 1 (below) covers the continuous swing sound (`CreakVoice` and what feeds it), which is what the feedback was about. Part 2, added later the same day, extends the work to every other sound in the app; its release order replaces the one at the end of part 1.

# Part 1. The swing sound

## What is wrong today

Measured on `make sounds` output (oak, seed 42) and read from `Duor/Audio/DSP/CreakVoice.swift`.

| # | Finding | Evidence | Why it sounds bad |
|---|---|---|---|
| 1 | The creak is a pitched tone that glides with hinge speed. | Slip rate = `40 + 1.6 · speed` Hz. In `creak-open.wav` the pitch runs 104 → 327 → 157 Hz over one swing, with autocorrelation periodicity up to 0.91. | A clean buzz sliding up and down reads as a kazoo or a small motor, not as wood and metal. On a real door the pitch comes from what resonates (pin, leaf, frame), and barely moves with speed. |
| 2 | Buzz source through four fixed formants. | Single-sample impulses into resonators at 720 / 1380 / 2250 / 3600 Hz. | That is the recipe of a voice synthesizer, so the door sounds nasal and vocal. |
| 3 | It is too loud, and loudest when it should be quietest. | Full-speed creak: RMS −15.4 dBFS against −18.6 for the slam. On the tool's "on phone" measure: −10.8 dB against −20.9 dB. Intensity rises with speed up to 45°/s and stays at full. | The creak outweighs the slam by about 10 dB on the phone speaker. Real hinges creak most when moved slowly and mostly go quiet on a fast swing. |
| 4 | It never stops. | Any movement above 6°/s creaks, for the whole swing, on every swing. | A real door creaks in patches, at the same few angles. Constant creaking is tiring within a minute. |
| 5 | There is no other swing sound. | The only continuous voice is the creak. | The choice is creak or silence, so the creak has to carry all the "it moves" feedback and cannot be turned down. |
| 6 | Every swing is the same door-agnostic texture. | The synth gets velocity only (`setCreak(velocity:)`), never the angle. | No sense of a particular door with its own tight spots. |
| 7 | It ends abruptly. | `DoorController` sets velocity to 0 after 150 ms without updates; the voice fades over the 40 ms smoothing. | A real door settles: the last few slips come further and further apart. |

Findings 1 to 4 are the unpleasantness. 5 to 7 are what would make it nice rather than merely not annoying.

## Target

- Slow swing: a woody creak made of separate slips you can almost count, pitched by the door, not by your hand speed.
- Normal swing: mostly a soft movement sound, with a short creak at one or two spots.
- Fast swing: air and a faint hinge roll. The slam or the open stop is the event, not the creak.
- The creak always sits clearly below the latch and the slam.
- The same door creaks at the same angles each time, a little differently opening and closing.
- Spaceship keeps its servo hum, which is meant to be tonal. It gets the level and tail fixes only.

## Plan

### Step 0. Make it measurable and comparable (small)

Do this first so every later step can be judged by ear and by numbers.

- `Tools/RenderSounds`: add swing gestures that match real use: slow open (3 s), normal open (1 s), fast open (0.4 s), a hesitating open, a small back-and-forth wiggle, open then close. Render each flat and with speaker voicing, for every door.
- Print creak metrics next to peak and RMS: pitch range and periodicity (autocorrelation), share of time sounding, level relative to that door's slam, share of energy in 2–5 kHz.
- Keep the 1.0 model selectable: `-creakModel <classic|new>` launch argument, and both rendered side by side into `build/sounds/` for A/B listening.
- Gather a handful of recordings of real doors as listening and spectrogram references. Reference only; they are never shipped (audio stays synthesized).

### Step 1. Quick wins in the current model (small, could ship alone as 1.0.1)

Parameter and small code changes in `CreakVoice` and `SoundProfile`:

- Level down about 8 dB, and make intensity peak at slow to medium speed and fall off above roughly 90°/s instead of holding at full.
- Take pitch away from speed: slip rate in a narrow, low band with much more jitter, so slips read as roughness, not as a note.
- Replace the single-sample impulse with a short shaped pulse whose length varies per slip (reuse the half-sine contact from `ImpactVoice`), which removes the buzz.
- Longer decays on the body modes, shorter and quieter squeal formants, so pitch comes from the wood.

This addresses findings 1 to 3 without new architecture.

### Step 2. A tension-and-release slip model (medium)

Replace the phase accumulator with a model of what the pin does:

- Tension builds in proportion to the distance moved (`|velocity| · dt`). When it passes a threshold, the pin slips: one pulse, loudness proportional to the tension released. The threshold is redrawn at random for each slip.
- Consequences that come for free: slow movement gives few, strong slips (the countable creak); faster movement gives many weak ones that blur into a soft rasp; stopping mid-stick is silent, and a door that coasts to rest gives its last slips further apart (finding 7).
- Above a per-door speed the surfaces slide without sticking: slips fade into low friction noise.
- Optional per door: when the slip rate nears a body mode, lock to it for a short squeal. On for Metal, off for Oak.

Why this and not a full friction simulation (mass, spring, Stribeck curve solved per sample): the accumulator is unconditionally stable, cheap, allocation-free, deterministic by seed, and easy to tune per door. A solved friction oscillator can sound more alive but needs oversampling and guarding against blow-ups on the audio thread. Revisit only if step 2 fails the listening test.

### Step 3. The door has tight spots (medium)

- Pass the angle to the synth as well: `setSwing(angle:velocity:)` replaces `setCreak(velocity:)` through `DoorSoundPlaying`, `DoorAudioEngine` and `DoorSynth`'s inbox. This is a continuous effect, so using the angle fits the hinge rules.
- Each `CreakProfile` gets a friction map over the swing: a few bumps (position, width, strength) on a low floor, generated from a seed per door style and hardware. The slip threshold and loudness follow the map, so the creak comes and goes at fixed angles (findings 4 and 6).
- Closing uses the same map shifted a few degrees and slightly weaker.
- Oak: two modest spots. Barn and Castle: wide, strong ones. Cottage: one light one. Metal: one squeal spot.

### Step 4. A movement bed under the creak (small to medium)

A second continuous voice so the creak no longer has to carry the motion (finding 5):

- Air: band-passed noise in roughly 300 Hz to 1.5 kHz, level following speed squared, very quiet. Heavier doors lower and louder.
- Hinge roll: sparse, soft ticks from the hinge modes at a rate following speed.
- Both go through the reverb send, so the room is heard while the door moves.

### Step 5. Smooth control and retune every door (medium)

- In the synth, glide between velocity updates instead of stepping, with no assumption about the update rate. Check with gestures fed at 20, 60 and 120 Hz and with irregular gaps.
- Retune all six doors and the five metals against the references, flat and voiced. Set creak level per door relative to its slam.
- Update `docs/SOLUTION_DESIGN.md` §6.1, §6.2 and §6.6.

### Step 6. Optional: let people choose (decision needed)

A "Hinges" setting: Oiled (movement bed only), A little creaky (default), Haunted. Taste clearly differs, and this makes the app quieter for those who want it. Cost: three new strings in 15 languages plus the App Store listings in `appstore/release.json`. Recommended, but after step 5 so the default is already good.

## How we know it worked

Automated, in `DuorTests/DoorSynthTests.swift` (existing creak tests keep passing):

- Wood doors: periodicity below 0.5 at every speed from 5 to 300°/s (no clean tone).
- Creak RMS at least 6 dB below the same door's slam, voiced and flat. Peaks below 0 dBFS in `make sounds`.
- Silent at rest; silent when stopped mid-swing; output finite and bounded for any velocity and angle sequence, including jumps.
- Same seed and gesture gives the same samples. Different angles give different output. Same angle on two swings gives a similar level.
- Result independent of update rate within a tolerance.
- Worst-case render cost stays near today's 0.7 % of a core in Release.

By ear:

- A/B of `classic` against `new` on a real Duo speaker and on headphones, all six doors.
- Blind A/B with the people who gave the feedback. Done when they prefer the new one and nobody calls it annoying after a few minutes of play.

## Constraints to keep

- Synthesized, not sampled. `Duor/Audio/DSP` stays real-time safe: `nonisolated` `Sendable` value types, no allocation or logging in `render`, fixed storage, no AVFoundation or UIKit.
- Discrete events stay on `status` transitions. The angle is used for the creak only.
- Door logic stays in `DoorMotionInterpreter`; the controller only forwards angle and velocity.

## Order and what ships when

1. Steps 0 and 1 together: a 1.0.1 that already removes the worst of it.
2. Steps 2 to 5: the real improvement, one release.
3. Step 6 if wanted.

## Open questions

- Ship step 1 early as 1.0.1, or hold everything for one release?
- Add the Hinges setting (step 6)?
- Which door did the feedback come from? If it was Metal, its squeal needs the most attention; if Oak, the default does.
- Was it heard on the phone speaker or on headphones?

# Part 2. The rest of the suite

Nobody complained about the knocks, latches and slams, so this part is not a rescue. It is about going from "fine" to "this feels like a real door in my hand". The findings come from the same renders and from reading `ImpactVoice`, `DoorSynth`'s recipes, `RoomReverb`, `SpeakerVoicing` and `DoorAudioEngine`.

## What holds the other sounds back

| # | Finding | Evidence | Effect |
|---|---|---|---|
| 8 | Loudness comes from the soft clipper. | The last stage is `tanh`, so the level going in can be worked back from the output peak. Oak knock: +5.0 dBFS in, squashed 5.5 dB. Castle knock and every speaker-voiced knock: +8.2 dBFS in. Slam: +3.1. Firm latch: +2.0. | The loudest moment of every hit is waveshaped, without oversampling. It gives loudness, but also a slightly crunchy, same-sounding attack on everything, and stacked hits smear. |
| 9 | Levels between doors and between sounds are not balanced. | Full sequence RMS: castle −11.2 dBFS, spaceship −24.9 dBFS (13.7 dB apart). On the phone measure the open stop sits at −36.1 dB against −20.9 for the slam and −26.9 for the gentle latch. | Switching doors changes the volume a lot. The open stop is close to inaudible on the phone speaker, so opening the door fully has no audible ending. |
| 10 | How hard a hit is only changes how loud it is. | `volume` scales amplitude. Closes arrive as three steps (0.6, 1, slam at 1); the measured closing speed is thrown away after classification. Knocks are a random 0.85 to 1. | Real contacts get brighter and shorter when harder. Without that, a gentle close sounds like a quiet firm close, and repeated closes sound stepped. |
| 11 | Every hit is six clean decaying sine waves. | `ImpactVoice`: half-sine force into a `ModalBank` of six modes (the bank has eight lanes; two are unused). The only noise is roughness on the force. | Pure modal sound leans toward a wood block or marimba. Real impacts also have a short burst of broadband contact noise, the "crack", which is also the part a phone speaker plays best. The slam has 15 dB less energy at 250 Hz to 1 kHz than below 250 Hz, so most of it is lost on the phone. |
| 12 | Latches are two clicks at a random gap. | `latch`: frame, panel, bolt click, second click 28 to 45 ms later whatever the speed. `unlatch`: two clicks and a panel tap. | The mechanism is missing: the bolt riding the strike plate, the snap, the door settling. The timing does not follow how fast the door came in. |
| 13 | The slam is a single moment. | Frame, panel, latch, four hinge rattles. Always at volume 1. | No air being pushed, no rebound off the frame, no difference between a slam and a very hard slam. |
| 14 | One room for every door. | `RoomReverb` is four combs and two allpasses with fixed size 0.8 and damping 0.4; doors only change the wet level (oak 0.12, castle 0.32). No early reflections. | A castle hall is the oak hallway turned up. Four combs also ring audibly on sharp clicks. |
| 15 | Mono. | `AVAudioFormat(... channels: 1)`. | Dead centre on headphones. Nothing comes from where it happens on the door, although `KnockSpot` already knows where the finger landed. |
| 16 | The inside scene is silent and does not change the acoustics. | The sound profile comes from door style and hardware only. | Opening onto a beach sounds the same as opening onto a brick wall. |
| 17 | Haptics are generic. | `RootView` uses `.sensoryFeedback` with stock `.impact` weights. | The phone is the door, so the felt impact is half of the sound. Stock taps do not follow the speed or the door's weight. |
| 18 | Stolen voices are cut dead. | `strike` reuses the voice closest to finishing; `start` calls `modes.silence()`. | A possible click when many hits stack (barn slam: up to 12 strikes). Minor. |

## Principles for part 2

- One number for "how hard": every event carries its real speed into the synth, and that one value sets loudness, brightness, contact time and timing together.
- Each hit is body plus contact noise, not body alone.
- Every event must be audible on the phone speaker on its own, and balanced against the slam.
- Clean headroom first. Saturation becomes a choice, not the default.
- The door and the place it stands in are separate things: the door's materials, and the room.

## Plan

### Step 7. Gain staging and loudness targets (small, do first)

- Bring the mix down so a single event reaches the clipper at or below 0 dBFS. Put a simple peak limiter (fast attack, about 80 ms release, fixed state) in front of the `tanh`, which stays as a safety net. Retune `SpeakerVoicing`'s make-up gain against it.
- Set targets on the phone measure, relative to that door's slam: knock −4 dB, firm latch −6, open stop −8, gentle latch and unlatch −12, creak at most −10. Keep doors within 6 dB of each other on the full sequence.
- `make sounds` prints the table and marks rows that miss.
- Risk: some of today's punch is the clipper. A/B on the device; if knocks lose weight, add a deliberate, mild saturation on the knock path only.

### Step 8. Better impacts (medium)

All in `ImpactVoice` and `ImpactSpec`, so every recipe gains at once:

- Contact noise: a band-passed noise burst with its own short envelope (2 to 20 ms), level, band and length set per material. Wood: short and mid-band. Steel bolt: very short and bright. Rubber stop: long and dull.
- Hardness follows force: a harder hit shortens the contact and tilts gain toward the high modes.
- Use all eight lanes: widen `ModeSet` from six modes to eight, with two close-spaced pairs on metal parts for a slight beat.
- Fade a stolen voice over about 2 ms instead of silencing it.

### Step 9. Carry speed through the events (small)

- `DoorEvent.closed` carries the closing speed next to its `CloseKind`. The kind still picks the recipe and the haptic; the speed sets intensity inside it. `hitOpenStop` already has a speed.
- `DoorSoundPlaying.play` takes an intensity that the synth maps through step 8, instead of a volume.
- Pure change in `DoorMotionInterpreter`, with tests.

### Step 10. Rewrite the recipes (medium)

- **Latch.** Leaf meets the stop, the bolt rides the strike plate (a short rising scrape), snaps home (the click), and the leaf settles with a small second touch. The gap between contact and click shrinks as speed rises. Gentle: more scrape, soft click. Firm: tight and bright.
- **Unlatch.** Handle and spindle turn (two soft spring ticks), bolt draws back (click), then the leaf lets go of the stop (a low, quiet release). Castle keeps its drawn iron bolt.
- **Slam.** Air pushed ahead of the leaf (a short noise swell in the 300 to 800 Hz band before the hit), the hit with a strong contact crack, a quieter rebound 70 to 110 ms later, then the hardware rattling down. Scales above the slam threshold, so a hard slam is more than a slam.
- **Open stop.** Give it a body the phone can play, and make it the door's own: rubber on wood for oak and cottage, wood on wood for the barn, an iron ring on stone for the castle, an actuator end-stop with the servo winding down for the spaceship, a sprung steel stop for metal. Add the leaf's small shudder after it.
- **Knocks.** Least change: they benefit from steps 7 and 8. Check that the fist and knuckle characters survive the new gain staging.

### Step 11. A real room per door (medium)

- Replace `RoomReverb` with an eight-line feedback delay network plus a few early reflection taps and a pre-delay. Buffers still allocated up front.
- Per door: size, decay time, damping, early pattern. Oak: carpeted hallway, about 0.4 s. Cottage: small and dry. Barn: wide, short, diffuse. Castle: stone hall, about 1.8 s with a late slap. Spaceship: small bright metal airlock. Metal: concrete stairwell, about 1.2 s.
- The inside scene becomes a second space that mixes in as the door opens, following the angle: living room is soft and short, great hall is long, beach, forest and space have no reflections at all, brick wall is a hard, close slap.

### Step 12. Stereo, with sounds where they happen (medium)

- Render two channels. Dry sounds are placed by where they are on the door: hinge and creak toward the crease, latch toward the handle edge, knocks where the finger landed. Keep the width modest. The room is decorrelated left and right.
- `SpeakerVoicing` runs per channel with a linked compressor.
- Needs a check on a real Duo, folded and unfolded and in both orientations, for which speaker ends up on which side. If that cannot be made reliable, use placement on headphones only and keep the speakers centred with a stereo room.

### Step 13. Haptics that match the sound (medium)

- Replace the stock `.sensoryFeedback` taps with Core Haptics patterns built from the same event and intensity: sharpness from the material, strength from the speed, a short decaying rumble under a slam, a double tap for the latch (contact, click).
- Try light ticks on creak slips at slow speed, rate-limited. Keep it only if it feels like a hinge and not like a buzz.
- Lives outside `Duor/Audio/DSP` (no UIKit there), driven by the controller's events, behind a protocol so tests and devices without haptics are unaffected.

### Step 14. Optional: the scene heard through the doorway (larger, decision needed)

A quiet synthesized bed for the inside scene, muffled behind a shut door and opening up with the angle: a fire and a clock in the living room, a draught in the great hall, surf on the beach, wind in leaves in the forest, near silence in space, nothing behind the brick wall. All of it is noise and impacts the synth can already make, apart from birdsong. It changes what the app is more than any other step, so it needs a yes first, and probably its own on/off setting (strings in 15 languages, App Store listings).

## How we know part 2 worked

Added to the checks in part 1:

- Single events reach the clipper at or below 0 dBFS; the loudness table meets its targets for all six doors, voiced and flat.
- Every event is within 14 dB of its door's slam on the phone measure.
- Brightness (spectral centroid) and loudness both rise steadily with closing speed, with no jump at the gentle, firm and slam boundaries larger than the recipe change intends.
- Measured decay time per door matches its room; castle is clearly longest.
- Stereo sums to mono without losing more than 3 dB on any sound.
- No sample-to-sample jump above a set limit when 200 commands are fired at once.
- Worst case stays under 2 % of a core in Release.
- By ear: the same blind A/B as part 1, per sound, on the Duo speaker and on headphones.

## Order and what ships when (replaces the order in part 1)

1. **1.0.1, the fixes.** The quick wins listed below. Nothing in it needs a new model or a new architecture.
2. **1.1, the new sound.** Steps 2 to 5 (creak model, tight spots, movement bed, retune) with the limiter from step 7 and steps 8 to 11 (impacts, recipes, rooms). These share the retuning pass over all doors, so doing them together means tuning once.
3. **1.2, the feel.** Steps 12 and 13 (stereo, haptics). Both need time on a real device.
4. **Later, if wanted.** Step 6 (Hinges setting) and step 14 (scene ambience).

By value for effort, most first: gain staging, open stop, contact noise with speed-driven hardness, rooms, haptics, stereo, ambience.

## Quick wins (the 1.0.1 list)

Each is a parameter change or a few lines, and together they answer the original feedback. In order:

| # | Quick win | From | What changes | Fixes |
|---|---|---|---|---|
| Q1 | Turn the creak down about 8 dB. | Step 1 | `level` in each `CreakProfile`. | The creak being louder than the slam (finding 3). The single biggest improvement for one number per door. |
| Q2 | Creak fades on fast swings. | Step 1 | The intensity curve in `CreakVoice.render`: peak at slow to medium speed, fall off above about 90°/s. | Loudest when it should be quietest (finding 3). |
| Q3 | Take the pitch away from the speed. | Step 1 | Lower `ratePerDegree` and `maxRate`, raise `jitter`, in each profile. | The kazoo glide (finding 1). |
| Q4 | Soften each slip. | Step 1 | A short half-sine pulse of varying length instead of a one-sample impulse, plus longer body decays and quieter squeal formants. | The buzz and the nasal tone (findings 1 and 2). |
| Q5 | Make the open stop audible. | Step 10 | Add a mid-band strike to `openStop` and raise its level toward the −8 dB target. | Opening fully has no audible ending (finding 9). |
| Q6 | Level the doors. | Step 7 | One trim per `SoundProfile` so full sequences sit within 6 dB of each other. No limiter yet. | Volume jumping when switching doors (finding 9). |
| Q7 | Fade stolen voices. | Step 8 | About 2 ms ramp in `ImpactVoice` instead of `modes.silence()`. | Possible clicks on stacked hits (finding 18). |
| Q8 | Carry closing speed into the latch and slam. | Step 9 | `DoorEvent.closed` keeps its speed; volume follows it continuously inside each kind. | Stepped, same-sounding closes (finding 10). Loudness only for now; brightness comes with step 8. |

To judge them, do the small part of step 0 first: the swing gestures and the creak and loudness numbers in `make sounds`. The A/B launch argument can wait for 1.1.

Not quick, though it may look it: the limiter in step 7. It changes how every hit's attack sounds and needs an A/B on the device, so it moves to 1.1.

## Which model for which step

Suggested split when the work is done with Claude Code. The stronger model is worth it where the design is the hard part; the rest is plumbing.

| Use | Steps | Why |
|---|---|---|
| Most capable model (Fable 5.2) | 2 (slip model), 7's limiter and rebalancing, 8 (impacts), 11 (reverb), 12 (stereo), and the retuning in 5 and 10 | New real-time DSP that must stay stable and allocation-free, changes that reach every sound at once, and long render, measure, adjust loops over six doors and five metals. |
| A cheaper model (Sonnet 5.5) | All quick wins Q1 to Q8, 0 (render tool), 3 (angle and friction map), 4 (movement bed), 9 (speed in events), 13 (haptic patterns), and the settings, translation and App Store work in 6 and 14 | Parameter changes, small pure changes with tests, and wiring. |

Either way, the measured targets can be checked by the model; whether it sounds nice is decided by ear on a real Duo.

## Open questions for part 2

- Is it acceptable for knocks to lose a little raw loudness in exchange for a cleaner attack, if the A/B shows that trade?
- Scene ambience (step 14): wanted, or does it take the app away from being "just a door"?
- Should the inside scene change the acoustics (step 11) even if ambience is not added? Recommended: yes.
- Stereo placement on the Duo's own speakers depends on a device check nobody has done yet.
