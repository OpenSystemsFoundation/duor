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
