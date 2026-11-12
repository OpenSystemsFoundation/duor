/// Everything that makes one door sound like itself.
///
/// Frequencies are tuned for a phone speaker, which reproduces little below ~250 Hz:
/// the body of each sound sits around 200 Hz to 1.2 kHz, with lower modes kept for headphones.
nonisolated struct SoundProfile: Sendable {
    /// The door leaf: thuds, latches and slams.
    var panel: ModeSet
    /// The leaf as a knuckle hears it: the same wood, heavily damped by the hand. Knocks.
    var knock: ModeSet
    /// The leaf meeting the frame. Closing thumps and slams.
    var frame: ModeSet
    /// Steel latch bolt and strike plate. Clicks.
    var latch: ModeSet
    /// Hinge knuckles and plates. Rattle after a slam.
    var hinge: ModeSet
    var creak: CreakProfile
    /// Air and hinge roll under the creak while the door moves.
    var bed = SwingBedProfile()
    /// Reverb wet level.
    var room: Float
    /// The door's signature extras.
    var character = SoundCharacter()
    /// How a knuckle meets this door.
    var knockTouch = KnockTouch()
    /// The noise of each part's surfaces meeting, next to its ring.
    var contact = ContactSet()
    /// The room the door stands in. `room` sets how loud it is.
    var space = RoomAcoustics.hallway
    /// What is beyond the door, heard as it opens. Set from the inside scene.
    var scene = SceneAcoustics.livingRoom
    /// What the open leaf runs into.
    var stop = DoorStop.rubber
    /// This door's balance between its own sounds.
    var levels = EventLevels()
    /// Output level of this door against the others (linear), so switching doors doesn't change
    /// the volume: a full knock, open, slam sequence of every door lands within a few dB.
    var trim: Float = 1
}

/// How loud a door's sounds are next to its slam (linear). Tuned with `make sounds` against the
/// loudness targets on the phone measure: a knock 4 dB under the slam, the open stop 8, the
/// unlatch 12. Closes follow the closing speed (`DoorStrength.force`); only how heavy the full slam
/// lands can be set per door.
nonisolated struct EventLevels: Sendable {
    var knock: Float = 1
    var unlatch: Float = 1
    var stop: Float = 1
    /// How much heavier this door's full slam lands than its closing speed alone says. Comes in
    /// with the slam (`DoorStrength.slamWeight`), so a firm close is left where it is.
    var slam: Float = 1
    /// A door with a damper has no slam to measure against, so its closes are set as a whole.
    var softClose: Float = 1
}

/// The door stop an open leaf swings into, and what the leaf does there.
nonisolated struct DoorStop: Sendable {
    /// The stop itself as a struck object. Its body is kept where a phone speaker plays
    /// (300 Hz to 1 kHz), so opening the door fully has an audible end.
    var modes: ModeSet
    /// Seconds of contact: long for rubber, short for iron.
    var contactTime: Float
    /// Loudness of the stop's own sound, and of the thud the leaf gives.
    var level: Float
    var leaf: Float
    /// A loose stop bounces after the hit: how often, and the first gap in seconds.
    var bounces = 0
    var bounceGap: Float = 0.07
    /// The leaf's small shudder after it.
    var shudder: Float = 0.12
    /// An actuator instead of a swing: its motor winds down against the end stop (0 = none).
    var windDown: Float = 0
    /// Part of the door's hardware, so it changes with the metal.
    var isHardware = false

    /// A rubber bumper on the skirting board: a dull, round "bup" with next to no ring.
    static let rubber = DoorStop(
        modes: [
            ModeSpec(260, 0.021, 0.70),
            ModeSpec(390, 0.018, 1.00),
            ModeSpec(540, 0.016, 0.85),
            ModeSpec(730, 0.013, 0.60),
            ModeSpec(980, 0.010, 0.40),
            ModeSpec(1350, 0.008, 0.25),
            ModeSpec(1900, 0.006, 0.14),
            ModeSpec(2700, 0.005, 0.08),
        ], contactTime: 0.006, level: 1, leaf: 0.7, shudder: 0.1)

    /// A forged iron ring on a stone wall: a clank that rings, and the ring dancing on the stone.
    static let ironRing = DoorStop(
        modes: [
            ModeSpec(510, 0.150, 0.80),
            ModeSpec(524, 0.140, 0.50),
            ModeSpec(1120, 0.120, 1.00),
            ModeSpec(1151, 0.110, 0.60),
            ModeSpec(1840, 0.090, 0.70),
            ModeSpec(2720, 0.070, 0.50),
            ModeSpec(3900, 0.050, 0.35),
            ModeSpec(5300, 0.035, 0.22),
        ], contactTime: 0.0006, level: 0.7, leaf: 0.5, bounces: 3, bounceGap: 0.085, shudder: 0.2, isHardware: true)

    /// A sprung steel stop: a short "dwong" as the spring takes the leaf, and one flutter.
    static let spring = DoorStop(
        modes: [
            ModeSpec(335, 0.180, 0.90),
            ModeSpec(344, 0.170, 0.60),
            ModeSpec(690, 0.130, 1.00),
            ModeSpec(708, 0.120, 0.55),
            ModeSpec(1160, 0.090, 0.60),
            ModeSpec(1730, 0.070, 0.40),
            ModeSpec(2500, 0.050, 0.28),
            ModeSpec(3600, 0.035, 0.18),
        ], contactTime: 0.0012, level: 0.8, leaf: 0.6, bounces: 1, bounceGap: 0.055, shudder: 0.15, isHardware: true)
}

/// The contact noise of each part of a door (see `ContactNoise`): what is heard of the surfaces
/// themselves in the first milliseconds of a hit. The defaults are an oak door with steel hardware.
nonisolated struct ContactSet: Sendable {
    /// Something hard meeting the leaf: short and mid-band.
    var panel = ContactNoise(level: 0.22, frequency: 1_000, q: 0.8, duration: 0.005)
    /// A knuckle on the leaf: skin softens it, so quieter and shorter than wood on wood.
    var knock = ContactNoise(level: 0.12, frequency: 1_700, q: 0.8, duration: 0.003)
    /// The leaf landing in the frame all along its edge: lower and a little longer.
    var frame = ContactNoise(level: 0.28, frequency: 700, q: 0.7, duration: 0.008)
    /// The steel bolt on its strike plate: very short, and the brightest of them, but kept under
    /// the band where a click stings (2 to 5 kHz).
    var latch = ContactNoise(level: 0.22, frequency: 2_400, q: 1, duration: 0.0025)
    /// Hinge knuckles knocking on the pin.
    var hinge = ContactNoise(level: 0.15, frequency: 2_000, q: 1.2, duration: 0.0025)
    /// The door stop the open leaf runs into. Rubber: long and dull.
    var stop = ContactNoise(level: 0.6, frequency: 420, q: 0.7, duration: 0.018)

    /// The same surfaces on a bigger or smaller, harder or softer door.
    func scaled(pitch: Float, duration: Float = 1, level: Float = 1) -> ContactSet {
        var copy = self
        func scale(_ noise: inout ContactNoise) {
            noise.frequency *= pitch
            noise.duration *= duration
            noise.level *= level
        }
        scale(&copy.panel)
        scale(&copy.knock)
        scale(&copy.frame)
        scale(&copy.stop)
        return copy
    }
}

/// How a knock lands: soft or hard knuckle, how much bright snap, how much deep thump.
nonisolated struct KnockTouch: Sendable {
    /// Knuckle contact time in seconds. Longer is softer and darker.
    var contact: ClosedRange<Float> = 0.0008...0.0012
    /// Level and pitch of the knuckle's own sharp snap on top.
    var snapLevel: Float = 0.3
    var snapPitch: Float = 3.2
    /// A deep thump from the whole door moving in its frame (0 = none). Heavy doors have it.
    var thump: Float = 0
}

/// What makes a door type recognizable beyond its wood.
nonisolated struct SoundCharacter: Sendable {
    /// Window panes that rattle on knocks and closes (0 = no glass).
    var glassRattle: Float = 0
    /// Loose boards that clatter after a hit (0 = solid).
    var looseBoards: Float = 0
    /// A big iron bolt instead of a small latch: lower, longer, slower clanks.
    var heavyBolt = false
    /// A soft-close damper and magnetic catch: no slams, a soft thud and a click.
    var softClose = false
    /// An airlock: a pneumatic hiss when the hatch unseals and seals (0 = none).
    var airlockHiss: Float = 0
    /// A powered panel that slides into the wall instead of a leaf on a latch: it opens with its
    /// locks drawing back, a rush of air and the panel running along its track, and closes into
    /// a padded, sealed thud. (How loud its air is: `airlockHiss`.)
    var slides = false
    /// The motor of a powered door, heard running up as it opens and down as it shuts or reaches
    /// its end stop: a warm tone that glides (0 = none).
    var motor: Float = 0
    /// Two soft notes when a powered door opens (rising) and shuts (falling). 0 = no chime.
    var chime: Float = 0
}

extension SoundProfile {
    /// Solid oak, iron hinges, steel latch: the reference wood every other door is derived from.
    nonisolated static let oakWood = SoundProfile(
        panel: [
            ModeSpec(110, 0.080, 0.35),
            ModeSpec(205, 0.070, 0.70),
            ModeSpec(320, 0.055, 1.00),
            ModeSpec(480, 0.045, 0.80),
            ModeSpec(730, 0.030, 0.55),
            ModeSpec(1150, 0.018, 0.30),
            ModeSpec(1640, 0.012, 0.18),
            ModeSpec(2350, 0.007, 0.10),
        ],
        knock: [
            ModeSpec(160, 0.028, 0.30),
            ModeSpec(270, 0.024, 0.85),
            ModeSpec(400, 0.020, 1.00),
            ModeSpec(580, 0.015, 0.75),
            ModeSpec(860, 0.011, 0.50),
            ModeSpec(1350, 0.007, 0.35),
            ModeSpec(1900, 0.005, 0.24),
            ModeSpec(2650, 0.004, 0.15),
        ],
        frame: [
            ModeSpec(70, 0.140, 0.60),
            ModeSpec(130, 0.110, 0.80),
            ModeSpec(190, 0.090, 0.90),
            ModeSpec(280, 0.070, 0.70),
            ModeSpec(420, 0.050, 0.50),
            ModeSpec(640, 0.035, 0.30),
            ModeSpec(930, 0.026, 0.20),
            ModeSpec(1380, 0.018, 0.12),
        ],
        // A latch bolt is small steel mounted in wood: it clacks, it doesn't ring. Its two lowest
        // modes come as close pairs (bolt and strike plate), which beat for a moment. The modes
        // fall away steeply above them (about 9 dB per octave): a click that is mostly 1 to 2 kHz
        // sounds like a latch, one that is mostly 3 to 6 kHz like a pin dropped on a tile.
        latch: [
            ModeSpec(1450, 0.014, 1.00),
            ModeSpec(1492, 0.013, 0.60),
            ModeSpec(2200, 0.011, 0.70),
            ModeSpec(2256, 0.010, 0.45),
            ModeSpec(3250, 0.009, 0.36),
            ModeSpec(4500, 0.007, 0.16),
            ModeSpec(6000, 0.005, 0.07),
            ModeSpec(7800, 0.004, 0.03),
        ],
        // Two leaves on one pin: the lowest modes are pairs a few hertz apart.
        hinge: [
            ModeSpec(980, 0.050, 0.80),
            ModeSpec(1004, 0.046, 0.50),
            ModeSpec(1530, 0.040, 0.80),
            ModeSpec(1561, 0.037, 0.50),
            ModeSpec(2380, 0.030, 0.36),
            ModeSpec(3310, 0.025, 0.18),
            ModeSpec(4700, 0.018, 0.08),
            ModeSpec(6100, 0.012, 0.04),
        ],
        creak: CreakProfile(
            // The pin scraping in its knuckle: broad and quiet, so no slip sounds like a voice.
            formants: [
                ModeSpec(1170, 0.0050, 0.53),
                ModeSpec(1562, 0.0040, 0.46),
                ModeSpec(2448, 0.0030, 0.42),
                ModeSpec(3102, 0.0025, 0.28),
            ],
            // The leaf's own modes, ringing longer than the scrape: the creak's pitch is the door's.
            // Deliberately not in simple ratios (the panel's 205 : 320 : 480 are close to 2 : 3),
            // or a slip rings as a chord with a clear note. Heavily damped, as dry wood is.
            body: [
                ModeSpec(224, 0.0060, 0.40),
                ModeSpec(290, 0.0060, 0.44),
                ModeSpec(431, 0.0055, 0.42),
                ModeSpec(783, 0.0050, 0.32),
            ],
            stickDistance: 1.5,
            easeSpeed: 60,
            slideSpeed: 80,
            slideFullSpeed: 220,
            pulse: 0.0004...0.0014,
            roughness: 0.5,
            scrape: 2.5,
            scrapeDecay: 0.014,
            hiss: 0.02,
            level: 0.031,
            // Two modest tight spots.
            friction: FrictionMap(
                recipe: .init(count: 2, width: 5...9, strength: 0.45...0.65, floor: 0.12), seed: 0x0A4)
        ),
        room: 0.12
    )
}

// MARK: - Variations

/// How a hardware metal changes the latch, hinges, door stop and creak: brass is warmer and rings
/// longer, polished steel is brighter and harder, copper is soft and dead, bronze low and bell-like.
nonisolated struct MetalTone: Sendable {
    var pitch: Float
    var decay: Float
    /// How hard the metal's surfaces meet: scales the crack of its contact noise, and shortens it.
    /// What tells a click on chrome from one on copper before either has rung.
    var bite: Float = 1

    static let iron = MetalTone(pitch: 1, decay: 1)
    static let brass = MetalTone(pitch: 0.86, decay: 1.45, bite: 0.8)
    static let chrome = MetalTone(pitch: 1.22, decay: 1.25, bite: 1.3)
    static let copper = MetalTone(pitch: 0.82, decay: 0.8, bite: 0.6)
    static let bronze = MetalTone(pitch: 0.72, decay: 1.3, bite: 0.75)
}

extension SoundProfile {
    /// Small window panes loose in their putty: a soft, shimmering "tink" (close pairs of modes)
    /// around 1.5 kHz rather than the ring of a wine glass, with only a trace of sparkle on top.
    nonisolated static let glass: ModeSet = [
        ModeSpec(1380, 0.040, 1.00),
        ModeSpec(1404, 0.037, 0.60),
        ModeSpec(1960, 0.035, 0.70),
        ModeSpec(1988, 0.032, 0.42),
        ModeSpec(2750, 0.030, 0.30),
        ModeSpec(3700, 0.025, 0.15),
        ModeSpec(4900, 0.020, 0.07),
        ModeSpec(6400, 0.015, 0.03),
    ]
}

extension InlineArray where Element == ModeSpec {
    /// The same object, bigger or smaller (pitch) and more or less damped (decay).
    nonisolated func scaled(pitch: Float, decay: Float = 1, gain: Float = 1) -> Self {
        var copy = self
        for index in copy.indices {
            copy[index].frequency *= pitch
            copy[index].decay *= decay
            copy[index].gain *= gain
        }
        return copy
    }
}

extension SoundProfile {
    /// This door with different hardware: retunes the latch, hinges and the hinge's squeal.
    nonisolated func with(metal: MetalTone) -> SoundProfile {
        var profile = self
        // Softer metals click a little lower, too, and with less of a crack.
        let bite = min(max(metal.bite, 0.3), 2)
        profile.contact.latch.frequency *= metal.pitch
        profile.contact.hinge.frequency *= metal.pitch
        profile.contact.latch.level *= bite
        profile.contact.hinge.level *= bite
        profile.contact.latch.duration /= bite
        profile.contact.hinge.duration /= bite
        profile.latch = latch.scaled(pitch: metal.pitch, decay: metal.decay)
        profile.hinge = hinge.scaled(pitch: metal.pitch, decay: metal.decay)
        profile.creak.formants = creak.formants.scaled(pitch: metal.pitch.squareRoot())
        // A stop that is hardware (the castle's ring, the steel door's spring) is of the same metal.
        if stop.isHardware {
            profile.stop.modes = stop.modes.scaled(pitch: metal.pitch, decay: metal.decay)
            profile.contact.stop.frequency *= metal.pitch
            profile.contact.stop.level *= bite
        }
        // Other hardware sits a little differently on the same door: its tight spots move a few degrees.
        profile.creak.friction = creak.friction.shuffled(seed: UInt32(metal.pitch * 1_000 + metal.decay * 7), by: 6)
        return profile
    }

    /// Solid oak with a friendly fist knock: a soft, warm "thump-thump". Long, padded contact,
    /// heavily damped, a little frame thud, no snap.
    nonisolated static let oak: SoundProfile = {
        var profile = SoundProfile.oakWood
        profile.knock = oakWood.knock.scaled(pitch: 0.95, decay: 0.7, gain: 1.4)
        profile.knockTouch = KnockTouch(contact: 0.0019...0.0025, snapLevel: 0, snapPitch: 1, thump: 0.12)
        // A fist is padded: hardly any crack.
        profile.contact.knock = ContactNoise(level: 0.07, frequency: 1_100, q: 0.7, duration: 0.004)
        // The oak door's trim came down to make room for its slam; its swing sound stays where it was.
        profile.creak.level = 0.04
        profile.bed.airLevel = 0.036
        profile.bed.rollLevel = 0.023
        profile.space = .hallway
        profile.levels = EventLevels(knock: 1.1, unlatch: 1.5, stop: 1.45)
        profile.trim = 0.78
        return profile
    }()

    /// A light painted pine door: higher, a little hollower, a lighter creak.
    nonisolated static let pine: SoundProfile = {
        var profile = SoundProfile.oakWood
        profile.panel = oakWood.panel.scaled(pitch: 1.2, decay: 1.15)
        profile.frame = oakWood.frame.scaled(pitch: 1.12, decay: 0.9)
        profile.creak.formants = [
            ModeSpec(1489, 0.0050, 0.46),
            ModeSpec(1918, 0.0040, 0.47),
            ModeSpec(2624, 0.0030, 0.37),
            ModeSpec(3501, 0.0025, 0.21),
        ]
        profile.creak.body = [
            ModeSpec(235, 0.0050, 0.45),
            ModeSpec(375, 0.0050, 0.45),
            ModeSpec(679, 0.0047, 0.44),
            ModeSpec(969, 0.0043, 0.44),
        ]
        // A light leaf on small hinges: finer, quicker slips.
        profile.creak.stickDistance = 1.0
        // (Its rasp keeps a little more top than the other wood doors': with less, its fine slips
        // start to read as a tone.)
        profile.creak.raspFrequency = 2_400
        profile.creak.level = 0.07
        // One light spot.
        profile.creak.friction = FrictionMap(
            recipe: .init(count: 1, width: 5...8, strength: 0.3...0.45, floor: 0.08), seed: 0xC07)
        profile.bed.airFrequency = 750
        profile.bed.airLevel = 0.025
        profile.room = 0.1
        profile.character.glassRattle = 0.4
        // A crisp knuckle knock: the reference wood's knock with its sharp snap.
        profile.knock = oakWood.knock
        profile.knockTouch = KnockTouch()
        // Light, painted wood: a higher, thinner tick.
        profile.contact = ContactSet().scaled(pitch: 1.25, duration: 0.85, level: 0.9)
        // A small rubber stop, and a light leaf that makes less of it.
        profile.stop.modes = DoorStop.rubber.modes.scaled(pitch: 1.2, decay: 0.9)
        profile.levels = EventLevels(knock: 0.88, unlatch: 1.6, stop: 1.8)
        profile.space = .cottage
        profile.trim = 0.68
        return profile
    }()

    /// A big weathered barn door: low and woody, a long groaning creak, a wide space.
    nonisolated static let barn: SoundProfile = {
        var profile = SoundProfile.oakWood
        profile.panel = oakWood.panel.scaled(pitch: 0.75, decay: 1.4)
        profile.knock = oakWood.knock.scaled(pitch: 0.8, decay: 1.3, gain: 1.1)
        profile.frame = oakWood.frame.scaled(pitch: 0.8, decay: 1.3)
        profile.hinge = oakWood.hinge.scaled(pitch: 0.85, decay: 1.3)
        profile.creak.formants = [
            ModeSpec(851, 0.0050, 0.44),
            ModeSpec(1569, 0.0040, 0.44),
            ModeSpec(2222, 0.0030, 0.33),
            ModeSpec(2541, 0.0025, 0.25),
        ]
        profile.creak.body = [
            ModeSpec(155, 0.0065, 0.45),
            ModeSpec(234, 0.0065, 0.45),
            ModeSpec(455, 0.0060, 0.40),
            ModeSpec(524, 0.0055, 0.41),
        ]
        // Big strap hinges on a heavy leaf: slow, heavy slips that go on to a higher speed.
        profile.creak.stickDistance = 2.4
        profile.creak.easeSpeed = 50
        profile.creak.slideSpeed = 90
        profile.creak.slideFullSpeed = 240
        profile.creak.pulse = 0.0006...0.002
        profile.creak.scrapeDecay = 0.018
        profile.creak.rasp = 44
        profile.creak.raspFrequency = 1_900
        profile.creak.lowCut = 140
        profile.creak.hiss = 0.006
        profile.creak.level = 0.028
        // Wide, strong spots.
        profile.creak.friction = FrictionMap(
            recipe: .init(count: 3, width: 10...16, strength: 0.6...0.9, floor: 0.25), seed: 0xBA2)
        profile.bed.airFrequency = 480
        profile.bed.airQ = 0.5
        profile.bed.airLevel = 0.04
        profile.bed.rollLevel = 0.018
        profile.room = 0.2
        profile.character.looseBoards = 0.7
        // Big rough boards: lower, longer, louder. No rubber here: the leaf swings into a post.
        profile.contact = ContactSet().scaled(pitch: 0.75, duration: 1.4, level: 1.2)
        profile.contact.stop = ContactNoise(level: 0.7, frequency: 650, q: 0.7, duration: 0.011)
        // Wood on wood: the boards clack against the post, and the whole leaf shakes.
        profile.stop = DoorStop(
            modes: profile.knock.scaled(pitch: 1.3, decay: 1.4), contactTime: 0.0015, level: 0.9, leaf: 0.7,
            shudder: 0.2)
        profile.levels = EventLevels(knock: 0.8, unlatch: 1.7, stop: 0.46)
        profile.space = .barn
        profile.trim = 0.64
        return profile
    }()

    /// A massive castle door in a stone hall: deep thuds, slow loud groan, long echo.
    nonisolated static let castle: SoundProfile = {
        var profile = SoundProfile.oakWood
        profile.panel = oakWood.panel.scaled(pitch: 0.6, decay: 1.8)
        // Heavy and dark: a low, slow "thoom" of a massive leaf, almost no snap.
        profile.knock = oakWood.knock.scaled(pitch: 0.58, decay: 2, gain: 1.5)
        profile.frame = oakWood.frame.scaled(pitch: 0.6, decay: 1.8)
        profile.hinge = oakWood.hinge.scaled(pitch: 0.7, decay: 1.6)
        profile.creak.formants = [
            ModeSpec(917, 0.0050, 0.52),
            ModeSpec(1229, 0.0040, 0.44),
            ModeSpec(1766, 0.0030, 0.34),
            ModeSpec(2495, 0.0025, 0.21),
        ]
        profile.creak.body = [
            ModeSpec(141, 0.0055, 0.36),
            ModeSpec(207, 0.0055, 0.38),
            ModeSpec(398, 0.0050, 0.38),
            ModeSpec(473, 0.0050, 0.32),
        ]
        // Iron pintles carrying a massive leaf: the slowest, deepest groan.
        profile.creak.stickDistance = 3.2
        profile.creak.easeSpeed = 45
        profile.creak.slideSpeed = 90
        profile.creak.slideFullSpeed = 240
        profile.creak.pulse = 0.0006...0.0018
        profile.creak.scrape = 3
        profile.creak.scrapeDecay = 0.020
        profile.creak.rasp = 56
        profile.creak.raspFrequency = 1_900
        profile.creak.lowCut = 120
        profile.creak.hiss = 0.006
        profile.creak.level = 0.027
        profile.creak.friction = FrictionMap(
            recipe: .init(count: 3, width: 12...18, strength: 0.7...0.95, floor: 0.3), seed: 0xCA5)
        profile.bed.airFrequency = 420
        profile.bed.airQ = 0.5
        profile.bed.airLevel = 0.048
        profile.bed.rollLevel = 0.02
        profile.bed.rollPerDegree = 0.25
        profile.room = 0.32
        profile.character.heavyBolt = true
        profile.knockTouch = KnockTouch(contact: 0.0018...0.0024, snapLevel: 0.05, snapPitch: 2, thump: 0.4)
        // Massive oak on stone: a low, heavy contact; a big iron bolt; an iron ring for a stop.
        profile.contact = ContactSet().scaled(pitch: 0.6, duration: 1.7, level: 1.2)
        profile.contact.knock = ContactNoise(level: 0.06, frequency: 800, q: 0.7, duration: 0.005)
        profile.contact.latch = ContactNoise(level: 0.35, frequency: 1_700, q: 1.1, duration: 0.004)
        profile.contact.stop = ContactNoise(level: 1, frequency: 1_100, q: 1, duration: 0.007)
        profile.stop = .ironRing
        profile.levels = EventLevels(knock: 0.98, unlatch: 0.66, stop: 0.5, slam: 0.84)
        profile.space = .stoneHall
        profile.trim = 0.5
        return profile
    }()

    /// A starship's door of thin aluminum: light "dunk" rings instead of wood, a servo hum instead
    /// of a creak, and a powered panel that slides: it opens with a rush of air and its motor
    /// running up, and shuts into a padded, sealed thud instead of a slam. An original sound in
    /// the style of film and television starships, not a copy of any one of them.
    nonisolated static let spaceship: SoundProfile = {
        var profile = SoundProfile.oakWood
        // Thin aluminum hull panel: bright, inharmonic, rings a little.
        profile.panel = [
            ModeSpec(390, 0.09, 0.5),
            ModeSpec(910, 0.08, 0.9),
            ModeSpec(928, 0.075, 0.55),
            ModeSpec(1540, 0.07, 1.0),
            ModeSpec(1566, 0.065, 0.6),
            ModeSpec(2320, 0.055, 0.4),
            ModeSpec(3350, 0.04, 0.2),
            ModeSpec(4700, 0.03, 0.1),
        ]
        profile.knock = [
            ModeSpec(420, 0.07, 0.55),
            ModeSpec(980, 0.06, 1.0),
            ModeSpec(998, 0.056, 0.6),
            ModeSpec(1650, 0.05, 0.85),
            ModeSpec(1677, 0.047, 0.5),
            ModeSpec(2480, 0.04, 0.55),
            ModeSpec(3600, 0.03, 0.35),
            ModeSpec(5100, 0.02, 0.2),
        ]
        // A light aluminum frame: a hollow "tunk" rather than a woody thud.
        profile.frame = [
            ModeSpec(160, 0.06, 0.5),
            ModeSpec(380, 0.06, 0.9),
            ModeSpec(720, 0.05, 1.0),
            ModeSpec(733, 0.047, 0.55),
            ModeSpec(1150, 0.04, 0.7),
            ModeSpec(1171, 0.037, 0.4),
            ModeSpec(1800, 0.03, 0.3),
            ModeSpec(2700, 0.02, 0.15),
        ]
        profile.latch = oakWood.latch.scaled(pitch: 1.15, decay: 1.3)
        profile.hinge = oakWood.hinge.scaled(pitch: 1.25, decay: 1.2)
        // A smooth servo hum: a steady pulse through near-harmonic resonances, no grit, and most
        // of it in the two lowest: the hum of something hydraulic, not the whine of a drill.
        profile.creak.formants = [
            ModeSpec(700, 0.015, 0.6),
            ModeSpec(1400, 0.012, 0.4),
            ModeSpec(2100, 0.010, 0.18),
            ModeSpec(2800, 0.008, 0.07),
        ]
        profile.creak.body = [
            ModeSpec(350, 0.020, 0.3),
            ModeSpec(700, 0.015, 0.2),
            ModeSpec(1050, 0.010, 0.1),
            ModeSpec(1400, 0.02, 0),
        ]
        profile.creak.servo = ServoHum(baseRate: 150, ratePerDegree: 1.8, maxRate: 600)
        profile.creak.hiss = 0
        profile.creak.closingPitch = 0.92
        profile.creak.level = 0.006
        // The servo hums the whole way: no tight spots. A light hatch moves little air.
        profile.creak.friction = .uniform(1)
        profile.bed.airFrequency = 900
        profile.bed.airLevel = 0.008
        profile.bed.rollLevel = 0.006
        profile.room = 0.14
        profile.knockTouch = KnockTouch(contact: 0.0009...0.0013, snapLevel: 0.1, snapPitch: 2)
        profile.character.softClose = true
        profile.character.airlockHiss = 0.6
        // A starship's door: it slides, a motor drives it, and it answers with two soft notes.
        profile.character.slides = true
        profile.character.motor = 1
        profile.character.chime = 0.5
        // Thin aluminum: bright, short ticks, and a damped end stop.
        profile.contact.panel = ContactNoise(level: 0.2, frequency: 1_500, q: 1, duration: 0.003)
        profile.contact.knock = ContactNoise(level: 0.14, frequency: 3_000, q: 1, duration: 0.0025)
        profile.contact.frame = ContactNoise(level: 0.22, frequency: 1_000, q: 0.8, duration: 0.006)
        profile.contact.stop = ContactNoise(level: 0.2, frequency: 900, q: 0.7, duration: 0.012)
        // The actuator runs the hatch against its end stop and winds down.
        profile.stop = DoorStop(
            modes: profile.frame, contactTime: 0.005, level: 0.7, leaf: 0.3, shudder: 0.05, windDown: 0.5)
        profile.levels = EventLevels(knock: 0.57, unlatch: 0.3, stop: 0.38, softClose: 1.05)
        profile.space = .airlock
        profile.trim = 1.4
        return profile
    }()

    /// A steel door in a concrete stairwell: plates that ring briefly, a booming slam, and a hinge
    /// that squeals (metallic and tonal, but low and breathy enough not to hurt).
    nonisolated static let steel: SoundProfile = {
        var profile = SoundProfile.oakWood
        profile.panel = [
            ModeSpec(180, 0.16, 0.7),
            ModeSpec(420, 0.13, 1.0),
            ModeSpec(428, 0.12, 0.6),
            ModeSpec(690, 0.11, 0.9),
            ModeSpec(702, 0.10, 0.5),
            ModeSpec(1150, 0.08, 0.6),
            ModeSpec(1720, 0.05, 0.35),
            ModeSpec(2650, 0.035, 0.2),
        ]
        profile.knock = [
            ModeSpec(230, 0.12, 0.5),
            ModeSpec(520, 0.10, 0.9),
            ModeSpec(530, 0.092, 0.55),
            ModeSpec(860, 0.08, 1.0),
            ModeSpec(875, 0.074, 0.6),
            ModeSpec(1350, 0.06, 0.8),
            ModeSpec(2100, 0.045, 0.5),
            ModeSpec(3200, 0.03, 0.35),
        ]
        profile.frame = [
            ModeSpec(110, 0.14, 0.7),
            ModeSpec(240, 0.12, 1.0),
            ModeSpec(245, 0.11, 0.6),
            ModeSpec(380, 0.10, 0.9),
            ModeSpec(388, 0.092, 0.5),
            ModeSpec(620, 0.08, 0.6),
            ModeSpec(950, 0.05, 0.35),
            ModeSpec(1500, 0.035, 0.2),
        ]
        profile.hinge = oakWood.hinge.scaled(pitch: 0.95, decay: 1.15, gain: 0.8)
        profile.latch = oakWood.latch.scaled(pitch: 0.8, decay: 1.4, gain: 0.85)
        // A lower, breathier squeal: wider resonances and a rougher stick-slip, so it groans
        // rather than pierces.
        profile.creak.formants = [
            ModeSpec(1050, 0.006, 0.6),
            ModeSpec(1750, 0.005, 0.6),
            ModeSpec(2600, 0.004, 0.35),
            ModeSpec(3600, 0.003, 0.15),
        ]
        profile.creak.body = [
            ModeSpec(420, 0.030, 0.7),
            ModeSpec(690, 0.025, 0.6),
            ModeSpec(1150, 0.020, 0.2),
            ModeSpec(1720, 0.015, 0.1),
        ]
        // Steel on steel sticks in tiny steps, fast enough to fall in step with the plate's lowest
        // modes: that is the squeal. Less dry rasp than wood, and the plate rings on.
        profile.creak.stickDistance = 0.2
        profile.creak.squeal = 0.65
        profile.creak.scrape = 1
        profile.creak.rasp = 10
        profile.creak.raspFrequency = 2_400
        profile.creak.lowCut = 250
        profile.creak.hiss = 0.02
        profile.creak.level = 0.024
        // One spot where it squeals.
        profile.creak.friction = FrictionMap(
            recipe: .init(count: 1, width: 6...10, strength: 0.7...0.9, floor: 0.1), seed: 0x57E)
        profile.bed.airFrequency = 560
        profile.bed.airLevel = 0.032
        profile.bed.rollLevel = 0.022
        profile.room = 0.18
        profile.knockTouch = KnockTouch(contact: 0.0006...0.0009, snapLevel: 0.15, snapPitch: 2.2)
        // Steel plate: a hard, bright clank, and a sprung steel stop.
        profile.contact.panel = ContactNoise(level: 0.26, frequency: 1_400, q: 0.9, duration: 0.004)
        profile.contact.knock = ContactNoise(level: 0.16, frequency: 2_600, q: 0.9, duration: 0.003)
        profile.contact.frame = ContactNoise(level: 0.3, frequency: 900, q: 0.7, duration: 0.007)
        profile.contact.stop = ContactNoise(level: 0.7, frequency: 1_200, q: 1, duration: 0.006)
        profile.stop = .spring
        profile.levels = EventLevels(knock: 0.42, unlatch: 1.65, stop: 0.25, slam: 0.85)
        profile.space = .stairwell
        profile.trim = 0.8
        return profile
    }()

    /// Rushing air: broad resonances that turn noise into a soft "pfff", most of it between 1 and
    /// 2 kHz. (A hiss that is mostly 3 to 6 kHz is the sound of a leak, and sharp on a phone.)
    nonisolated static let air: ModeSet = [
        ModeSpec(620, 0.0028, 0.4),
        ModeSpec(900, 0.0025, 0.7),
        ModeSpec(1300, 0.0022, 1.0),
        ModeSpec(1800, 0.0020, 0.9),
        ModeSpec(2500, 0.0018, 0.55),
        ModeSpec(3400, 0.0015, 0.3),
        ModeSpec(4600, 0.0012, 0.15),
        ModeSpec(6200, 0.0010, 0.07),
    ]
}
