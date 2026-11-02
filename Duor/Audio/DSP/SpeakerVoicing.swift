import Foundation

/// A second-order filter (RBJ audio EQ cookbook), transposed direct form II.
nonisolated struct Biquad: Sendable {
    enum Kind: Sendable {
        case lowPass
        case highPass
        case bandPass
        case peak
        case highShelf
    }

    private var b0: Float = 1
    private var b1: Float = 0
    private var b2: Float = 0
    private var a1: Float = 0
    private var a2: Float = 0
    private var z1: Float = 0
    private var z2: Float = 0

    init(_ kind: Kind, frequency: Float, q: Float, gainDB: Float = 0, sampleRate: Float) {
        let omega = 2 * Float.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let cosine = cosf(omega)
        let alpha = sinf(omega) / (2 * q)
        let amplitude = powf(10, gainDB / 40)
        var b = SIMD3<Float>(1, 0, 0)
        var a = SIMD3<Float>(1, 0, 0)
        switch kind {
        case .lowPass:
            b = SIMD3((1 - cosine) / 2, 1 - cosine, (1 - cosine) / 2)
            a = SIMD3(1 + alpha, -2 * cosine, 1 - alpha)
        case .highPass:
            b = SIMD3((1 + cosine) / 2, -(1 + cosine), (1 + cosine) / 2)
            a = SIMD3(1 + alpha, -2 * cosine, 1 - alpha)
        case .bandPass:
            b = SIMD3(alpha, 0, -alpha)
            a = SIMD3(1 + alpha, -2 * cosine, 1 - alpha)
        case .peak:
            b = SIMD3(1 + alpha * amplitude, -2 * cosine, 1 - alpha * amplitude)
            a = SIMD3(1 + alpha / amplitude, -2 * cosine, 1 - alpha / amplitude)
        case .highShelf:
            let shelf = 2 * amplitude.squareRoot() * alpha
            b = SIMD3(
                amplitude * ((amplitude + 1) + (amplitude - 1) * cosine + shelf),
                -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosine),
                amplitude * ((amplitude + 1) + (amplitude - 1) * cosine - shelf))
            a = SIMD3(
                (amplitude + 1) - (amplitude - 1) * cosine + shelf,
                2 * ((amplitude - 1) - (amplitude + 1) * cosine),
                (amplitude + 1) - (amplitude - 1) * cosine - shelf)
        }
        b0 = b.x / a.x
        b1 = b.y / a.x
        b2 = b.z / a.x
        a1 = a.y / a.x
        a2 = a.z / a.x
    }

    mutating func process(_ input: Float) -> Float {
        let output = b0 * input + z1
        z1 = b1 * input - a1 * output + z2
        z2 = b2 * input - a2 * output
        return output
    }
}

/// Voices the output for the iPhone's own small speakers.
///
/// Phone speakers barely move air below about 150 Hz, and pushing them there only distorts. Most
/// of a wooden knock or a slam lives right there, so on the built-in speakers a door sounds thin
/// and quiet. This stage (after duomin's speaker stage):
///
/// - **Virtual bass.** The lows are rectified, which makes their octave and overtones, and the
///   band the speaker plays is mixed back in. The ear fills in the missing fundamental, so a deep
///   knock still sounds deep.
/// - A steep (24 dB/octave) **cut** below what the speaker plays, which frees its excursion for
///   what it can play.
/// - A little low-mid **body**, and a slightly softer **top**, where small speakers get harsh.
/// - A quick **compressor** with make-up gain: hits are short, so it catches the attack and lifts
///   the ring that follows, which is most of what makes a knock sound solid.
///
/// Off, it passes the signal through untouched. Switching glides over about 50 ms, so it never
/// clicks.
nonisolated struct SpeakerVoicing: Sendable {
    /// Where the voicing is heading. The mix follows it smoothly.
    var isOn: Bool

    private var mix: Float
    private let glide: Float

    private var bassLow: Biquad
    private var bassHigh: Biquad
    private var harmonicBand: Biquad
    private var cut1: Biquad
    private var cut2: Biquad
    private var body: Biquad
    private var air: Biquad

    private var envelope: Float = 0
    private let attack: Float
    private let release: Float

    /// How much of the rectified lows' overtones goes back in.
    static let virtualBass: Float = 0.6
    /// Below this the speaker is cut off (Hz).
    static let cutoff: Float = 150
    /// Compressor: level where it starts working, its ratio, and the make-up gain after it. Tuned
    /// with `make sounds` ("on phone"): knocks come across about 3.5 dB louder on a phone speaker,
    /// slams over 5 dB, while the soft clipper after it works no harder than it does flat.
    static let threshold: Float = 0.8
    static let ratio: Float = 3
    static let makeUp: Float = 1.5

    init(sampleRate: Float, isOn: Bool = false) {
        self.isOn = isOn
        mix = isOn ? 1 : 0
        glide = 1 - expf(-1 / (0.05 * sampleRate))
        bassLow = Biquad(.lowPass, frequency: 220, q: 0.707, sampleRate: sampleRate)
        bassHigh = Biquad(.highPass, frequency: 45, q: 0.707, sampleRate: sampleRate)
        harmonicBand = Biquad(.bandPass, frequency: 400, q: 0.7, sampleRate: sampleRate)
        // Two stages with these Qs make a 4th-order Butterworth.
        cut1 = Biquad(.highPass, frequency: Self.cutoff, q: 0.541, sampleRate: sampleRate)
        cut2 = Biquad(.highPass, frequency: Self.cutoff, q: 1.307, sampleRate: sampleRate)
        body = Biquad(.peak, frequency: 380, q: 0.9, gainDB: 3, sampleRate: sampleRate)
        air = Biquad(.highShelf, frequency: 9_000, q: 0.707, gainDB: -2, sampleRate: sampleRate)
        attack = 1 - expf(-1 / (0.002 * sampleRate))
        release = 1 - expf(-1 / (0.12 * sampleRate))
    }

    /// One sample. Real-time safe.
    mutating func process(_ input: Float) -> Float {
        mix += ((isOn ? 1 : 0) - mix) * glide
        if !isOn && mix < 0.0005 {
            mix = 0
            return input
        }

        // Rectifying a low tone makes its octave and overtones; the band keeps what the speaker plays.
        let lows = bassHigh.process(bassLow.process(input))
        var voiced = input + harmonicBand.process(abs(lows) * 2) * Self.virtualBass
        voiced = cut2.process(cut1.process(voiced))
        voiced = air.process(body.process(voiced))

        let level = abs(voiced)
        envelope += (level - envelope) * (level > envelope ? attack : release)
        var gain = Self.makeUp
        if envelope > Self.threshold {
            gain *= powf(Self.threshold / envelope, 1 - 1 / Self.ratio)
        }
        return input + (voiced * gain - input) * mix
    }
}
