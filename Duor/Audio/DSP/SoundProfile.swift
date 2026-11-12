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
            ModeSpec(1150, 0.018, 0.35),
        ],
        knock: [
            ModeSpec(160, 0.028, 0.30),
            ModeSpec(270, 0.024, 0.85),
            ModeSpec(400, 0.020, 1.00),
            ModeSpec(580, 0.015, 0.75),
            ModeSpec(860, 0.011, 0.50),
            ModeSpec(1350, 0.007, 0.35),
        ],
        frame: [
            ModeSpec(70, 0.140, 0.60),
            ModeSpec(130, 0.110, 0.80),
            ModeSpec(190, 0.090, 0.90),
            ModeSpec(280, 0.070, 0.70),
            ModeSpec(420, 0.050, 0.50),
            ModeSpec(640, 0.035, 0.30),
        ],
        // A latch bolt is small steel mounted in wood: it clacks, it doesn't ring.
        latch: [
            ModeSpec(1450, 0.014, 1.00),
            ModeSpec(2300, 0.011, 0.80),
            ModeSpec(3400, 0.009, 0.60),
            ModeSpec(4700, 0.007, 0.45),
            ModeSpec(6200, 0.005, 0.30),
            ModeSpec(8100, 0.004, 0.20),
        ],
        hinge: [
            ModeSpec(980, 0.050, 0.80),
            ModeSpec(1530, 0.040, 1.00),
            ModeSpec(2380, 0.030, 0.70),
            ModeSpec(3310, 0.025, 0.50),
            ModeSpec(4700, 0.018, 0.30),
            ModeSpec(6100, 0.012, 0.20),
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

/// How a hardware metal changes the latch, hinges and creak: brass is warmer and rings longer,
/// polished steel is brighter, bronze and copper are softer.
nonisolated struct MetalTone: Sendable {
    var pitch: Float
    var decay: Float

    static let iron = MetalTone(pitch: 1, decay: 1)
    static let brass = MetalTone(pitch: 0.86, decay: 1.45)
    static let chrome = MetalTone(pitch: 1.22, decay: 1.25)
    static let copper = MetalTone(pitch: 0.8, decay: 0.95)
    static let bronze = MetalTone(pitch: 0.74, decay: 1.15)
}

extension SoundProfile {
    /// Thin window glass: rings bright and long.
    nonisolated static let glass: ModeSet = [
        ModeSpec(2100, 0.040, 0.80),
        ModeSpec(3300, 0.035, 1.00),
        ModeSpec(4700, 0.030, 0.80),
        ModeSpec(6100, 0.025, 0.60),
        ModeSpec(7900, 0.020, 0.40),
        ModeSpec(9800, 0.015, 0.30),
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
        profile.latch = latch.scaled(pitch: metal.pitch, decay: metal.decay)
        profile.hinge = hinge.scaled(pitch: metal.pitch, decay: metal.decay)
        profile.creak.formants = creak.formants.scaled(pitch: metal.pitch.squareRoot())
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
        return profile
    }()

    /// A light painted pine door: higher, a little hollower, a lighter creak.
    nonisolated static let pine: SoundProfile = {
        var profile = SoundProfile.oakWood
        profile.panel = oakWood.panel.scaled(pitch: 1.3, decay: 1.15)
        profile.frame = oakWood.frame.scaled(pitch: 1.2, decay: 0.9)
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
        profile.creak.level = 0.06
        // One light spot.
        profile.creak.friction = FrictionMap(
            recipe: .init(count: 1, width: 5...8, strength: 0.3...0.45, floor: 0.08), seed: 0xC07)
        profile.bed.airFrequency = 750
        profile.bed.airLevel = 0.025
        profile.room = 0.1
        profile.character.glassRattle = 0.6
        // A crisp knuckle knock: the reference wood's knock with its sharp snap.
        profile.knock = oakWood.knock
        profile.knockTouch = KnockTouch()
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
        profile.creak.raspFrequency = 2_600
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
        profile.creak.raspFrequency = 2_600
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
        return profile
    }()

    /// A spaceship hatch of thin aluminum: light, bright "dink" rings instead of wood, a quiet
    /// servo hum instead of a creak, a damper instead of a slam, and an airlock hiss.
    nonisolated static let spaceship: SoundProfile = {
        var profile = SoundProfile.oakWood
        // Thin aluminum hull panel: bright, inharmonic, rings a little.
        profile.panel = [
            ModeSpec(390, 0.09, 0.5),
            ModeSpec(910, 0.08, 0.9),
            ModeSpec(1540, 0.07, 1.0),
            ModeSpec(2320, 0.055, 0.7),
            ModeSpec(3350, 0.04, 0.45),
            ModeSpec(4700, 0.03, 0.3),
        ]
        profile.knock = [
            ModeSpec(420, 0.07, 0.55),
            ModeSpec(980, 0.06, 1.0),
            ModeSpec(1650, 0.05, 0.85),
            ModeSpec(2480, 0.04, 0.55),
            ModeSpec(3600, 0.03, 0.35),
            ModeSpec(5100, 0.02, 0.2),
        ]
        // A light aluminum frame: a hollow "tunk" rather than a woody thud.
        profile.frame = [
            ModeSpec(160, 0.06, 0.5),
            ModeSpec(380, 0.06, 0.9),
            ModeSpec(720, 0.05, 1.0),
            ModeSpec(1150, 0.04, 0.7),
            ModeSpec(1800, 0.03, 0.45),
            ModeSpec(2700, 0.02, 0.3),
        ]
        profile.latch = oakWood.latch.scaled(pitch: 1.15, decay: 1.3)
        profile.hinge = oakWood.hinge.scaled(pitch: 1.25, decay: 1.2)
        // A smooth servo hum: a steady pulse through near-harmonic resonances, no grit.
        profile.creak.formants = [
            ModeSpec(700, 0.015, 0.6),
            ModeSpec(1400, 0.012, 0.5),
            ModeSpec(2100, 0.010, 0.3),
            ModeSpec(2800, 0.008, 0.15),
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
        return profile
    }()

    /// A steel door in a concrete stairwell: plates that ring briefly, a booming slam, and a hinge
    /// that squeals (metallic and tonal, but low and breathy enough not to hurt).
    nonisolated static let steel: SoundProfile = {
        var profile = SoundProfile.oakWood
        profile.panel = [
            ModeSpec(180, 0.16, 0.7),
            ModeSpec(420, 0.13, 1.0),
            ModeSpec(690, 0.11, 0.9),
            ModeSpec(1150, 0.08, 0.6),
            ModeSpec(1720, 0.05, 0.35),
            ModeSpec(2650, 0.035, 0.2),
        ]
        profile.knock = [
            ModeSpec(230, 0.12, 0.5),
            ModeSpec(520, 0.10, 0.9),
            ModeSpec(860, 0.08, 1.0),
            ModeSpec(1350, 0.06, 0.8),
            ModeSpec(2100, 0.045, 0.5),
            ModeSpec(3200, 0.03, 0.35),
        ]
        profile.frame = [
            ModeSpec(110, 0.14, 0.7),
            ModeSpec(240, 0.12, 1.0),
            ModeSpec(380, 0.10, 0.9),
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
        profile.creak.raspFrequency = 3_200
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
        return profile
    }()

    /// Rushing air: broad, high resonances that turn noise into a hiss.
    nonisolated static let air: ModeSet = [
        ModeSpec(1800, 0.0025, 0.5),
        ModeSpec(2700, 0.0022, 0.8),
        ModeSpec(3800, 0.0020, 1.0),
        ModeSpec(5200, 0.0018, 0.9),
        ModeSpec(6800, 0.0015, 0.7),
        ModeSpec(8800, 0.0012, 0.5),
    ]
}
