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
}

extension SoundProfile {
    /// Solid oak door, black iron hinges, steel latch.
    nonisolated static let oak = SoundProfile(
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
            formants: [
                ModeSpec(720, 0.006, 0.50),
                ModeSpec(1380, 0.005, 1.00),
                ModeSpec(2250, 0.004, 0.70),
                ModeSpec(3600, 0.003, 0.35),
            ],
            body: [
                ModeSpec(205, 0.050, 0.40),
                ModeSpec(320, 0.040, 0.50),
                ModeSpec(480, 0.030, 0.30),
            ],
            onsetSpeed: 3,
            fullSpeed: 45,
            baseRate: 40,
            ratePerDegree: 1.6,
            maxRate: 520,
            wander: 0.18,
            jitter: 0.035,
            hiss: 0.02,
            brighten: 0.12,
            closingPitch: 0.94,
            level: 0.2
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
        return profile
    }

    /// A light painted pine door: higher, a little hollower, a lighter creak.
    nonisolated static let pine: SoundProfile = {
        var profile = SoundProfile.oak
        profile.panel = oak.panel.scaled(pitch: 1.3, decay: 1.15)
        profile.knock = oak.knock.scaled(pitch: 1.25, decay: 1.2)
        profile.frame = oak.frame.scaled(pitch: 1.2, decay: 0.9)
        profile.creak.formants = oak.creak.formants.scaled(pitch: 1.15)
        profile.creak.body = oak.creak.body.scaled(pitch: 1.3)
        profile.creak.baseRate = 55
        profile.creak.ratePerDegree = 1.9
        profile.creak.level = 0.16
        profile.room = 0.1
        profile.character.glassRattle = 0.6
        // A soft knock: painted wood, a rounder knuckle, little snap, barely a rattle.
        profile.knock = oak.knock.scaled(pitch: 1.08, decay: 1.25, gain: 0.85)
        profile.knockTouch = KnockTouch(contact: 0.0017...0.0024, snapLevel: 0.07, snapPitch: 2.4)
        return profile
    }()

    /// A big weathered barn door: low and woody, a long groaning creak, a wide space.
    nonisolated static let barn: SoundProfile = {
        var profile = SoundProfile.oak
        profile.panel = oak.panel.scaled(pitch: 0.75, decay: 1.4)
        profile.knock = oak.knock.scaled(pitch: 0.8, decay: 1.3, gain: 1.1)
        profile.frame = oak.frame.scaled(pitch: 0.8, decay: 1.3)
        profile.hinge = oak.hinge.scaled(pitch: 0.85, decay: 1.3)
        profile.creak.formants = oak.creak.formants.scaled(pitch: 0.8)
        profile.creak.body = oak.creak.body.scaled(pitch: 0.8, decay: 1.4, gain: 1.6)
        profile.creak.baseRate = 26
        profile.creak.ratePerDegree = 1.1
        profile.creak.wander = 0.26
        profile.creak.jitter = 0.06
        profile.creak.level = 0.26
        profile.room = 0.2
        profile.character.looseBoards = 0.7
        return profile
    }()

    /// A massive castle door in a stone hall: deep thuds, slow loud groan, long echo.
    nonisolated static let castle: SoundProfile = {
        var profile = SoundProfile.oak
        profile.panel = oak.panel.scaled(pitch: 0.6, decay: 1.8)
        // Heavy and dark: a low, slow "thoom" of a massive leaf, almost no snap.
        profile.knock = oak.knock.scaled(pitch: 0.58, decay: 2, gain: 1.5)
        profile.frame = oak.frame.scaled(pitch: 0.6, decay: 1.8)
        profile.hinge = oak.hinge.scaled(pitch: 0.7, decay: 1.6)
        profile.creak.formants = oak.creak.formants.scaled(pitch: 0.65)
        profile.creak.body = oak.creak.body.scaled(pitch: 0.65, decay: 1.6, gain: 1.8)
        profile.creak.baseRate = 18
        profile.creak.ratePerDegree = 0.8
        profile.creak.wander = 0.3
        profile.creak.jitter = 0.07
        profile.creak.level = 0.3
        profile.room = 0.32
        profile.character.heavyBolt = true
        profile.knockTouch = KnockTouch(contact: 0.0018...0.0024, snapLevel: 0.05, snapPitch: 2, thump: 0.4)
        return profile
    }()

    /// A modern solid-core slab on well-oiled hinges: tight, clean, barely a whisper of creak.
    nonisolated static let modern: SoundProfile = {
        var profile = SoundProfile.oak
        profile.panel = oak.panel.scaled(pitch: 1.1, decay: 0.8)
        profile.knock = oak.knock.scaled(pitch: 1.15, decay: 0.75)
        profile.frame = oak.frame.scaled(pitch: 1.1, decay: 0.75)
        profile.creak.formants = oak.creak.formants.scaled(pitch: 1.3)
        profile.creak.baseRate = 70
        profile.creak.hiss = 0.04
        profile.creak.level = 0.05
        profile.room = 0.08
        profile.character.softClose = true
        return profile
    }()
}
