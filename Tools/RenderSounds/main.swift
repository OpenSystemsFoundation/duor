// Renders every door sound to WAV files and measures them, so the synth can be auditioned, tuned and
// compared before and after a change, on a Mac or on Linux.
//
//   make sounds                                   # writes build/sounds/*.wav, prints the tables
//   build/render-sounds build/sounds --json after.json --baseline before.json   # with deltas
//   build/render-sounds build/sounds --bench      # render cost only
//
// Compiled together with Duor/Audio/DSP/*.swift (no app or AVFoundation code).

import Foundation

let sampleRate: Float = 48_000
let blockSize = 256

var arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}
let outputDirectory = URL(fileURLWithPath: arguments.first { !$0.hasPrefix("--") } ?? "build/sounds")
let jsonPath = option("--json")
let baselinePath = option("--baseline")
let benchOnly = arguments.contains("--bench")
let writesFiles = !arguments.contains("--no-wav")

// MARK: - Driving the synth
//
// The only place that knows the synth's control API, so the scenarios below stay the same when it changes.

/// Something to do to the synth at a point in time.
struct Cue {
    var time: Float
    var action: (DoorSynth) -> Void
}

/// A one-shot sound at a given speed in degrees per second, mapped the way `DoorController` maps it.
func event(_ sound: DoorSound, speed: Float, at time: Float) -> Cue {
    Cue(time: time) { $0.play(sound, speed: speed) }
}

func knock(_ x: Float, _ y: Float, at time: Float, volume: Float = 1) -> Cue {
    Cue(time: time) { $0.knock(at: KnockSpot(x: x, y: y), volume: volume) }
}

/// The hinge angle over time, in degrees.
struct Gesture {
    var duration: Float
    var angle: (Float) -> Float
}

/// Eased move from one angle to another.
func move(_ from: Float, _ to: Float, over duration: Float) -> Gesture {
    Gesture(duration: duration) { t in
        let x = min(max(t / duration, 0), 1)
        return from + (to - from) * (x * x * (3 - 2 * x))
    }
}

func hold(_ angle: Float, for duration: Float) -> Gesture { Gesture(duration: duration) { _ in angle } }

func + (first: Gesture, second: Gesture) -> Gesture {
    Gesture(duration: first.duration + second.duration) { t in
        t < first.duration ? first.angle(t) : second.angle(t - first.duration)
    }
}

/// Feeds a gesture the way `DoorController` does: an update per hinge sample (`rate` per second, or
/// irregular), only once the angle moved 1.5° (the interpreter's jitter tolerance), with the
/// interpreter's smoothed velocity, and velocity 0 after 150 ms without movement.
func swing(_ gesture: Gesture, from start: Float, rate: Float = 60, irregular: Bool = false) -> [Cue] {
    var cues: [Cue] = []
    var random = NoiseSource(seed: 77)
    var t: Float = 0
    var anchorAngle = gesture.angle(0), anchorTime: Float = 0
    var velocity: Float = 0
    var lastSent: Float = -1
    while t <= gesture.duration + 0.3 {
        let angle = gesture.angle(min(t, gesture.duration))
        if abs(angle - anchorAngle) >= 1.5 {
            let gap = min(max(t - anchorTime, 1 / 240), 0.5)
            velocity += ((angle - anchorAngle) / gap - velocity) * 0.5
            anchorAngle = angle
            anchorTime = t
            if abs(velocity) >= 6 {
                let (a, v) = (angle, velocity)
                cues.append(Cue(time: start + t) { $0.setSwingForTool(angle: a, velocity: v) })
                lastSent = t
            }
        } else if lastSent >= 0, t - lastSent >= 0.15 {
            let a = angle
            cues.append(Cue(time: start + t) { $0.setSwingForTool(angle: a, velocity: 0) })
            lastSent = -1
            velocity = 0
        }
        t += irregular ? random.value(in: 0.004...0.09) : 1 / rate
    }
    if lastSent >= 0 {
        let a = gesture.angle(gesture.duration)
        cues.append(Cue(time: start + lastSent + 0.15) { $0.setSwingForTool(angle: a, velocity: 0) })
    }
    return cues
}

// MARK: - Rendering

func render(_ cues: [Cue], seconds: Float, profile: SoundProfile, speaker: Bool, seed: UInt32 = 42) -> [Float] {
    let synth = DoorSynth(sampleRate: sampleRate, profile: profile, seed: seed, speakerVoicing: speaker)
    let frameCount = Int(seconds * sampleRate)
    var samples = [Float](repeating: 0, count: frameCount)
    var pending = cues.sorted { $0.time < $1.time }[...]
    var frame = 0
    while frame < frameCount {
        let now = Float(frame) / sampleRate
        while let cue = pending.first, cue.time <= now {
            cue.action(synth)
            pending = pending.dropFirst()
        }
        let count = min(blockSize, frameCount - frame)
        samples.withUnsafeMutableBufferPointer { buffer in
            synth.render(into: UnsafeMutableBufferPointer(rebasing: buffer[frame..<frame + count]))
        }
        frame += count
    }
    return samples
}

struct Measurement: Codable {
    var peak: Float
    var rms: Float
    /// Level going into the final soft clipper, worked back from the output peak (tanh(0.9 x)).
    var clipperIn: Float
    var onPhone: Float
    var centroid: Float
    var presence: Float
    var t60: Float
    var ring: Float
    var largestStep: Float
    var periodicityMax: Float?
    var periodicityMedian: Float?
    var pitchLow: Float?
    var pitchHigh: Float?
    var sounding: Float?
    var finite: Bool
}

var results: [String: Measurement] = [:]
var order: [String] = []

@discardableResult
func measure(
    _ name: String, seconds: Float, cues: [Cue], profile: SoundProfile, speaker: Bool = false, continuous: Bool = false
) throws -> Measurement {
    let samples = render(cues, seconds: seconds, profile: profile, speaker: speaker)
    let peakValue = peak(samples)
    let spectrum = summarize(powerSpectrum(samples[...]))
    let decay = decayTimes(samples)
    var measurement = Measurement(
        peak: decibels(peakValue), rms: decibels(rms(samples[...])),
        clipperIn: decibels(atanh(min(peakValue, 0.999_999)) / 0.9), onPhone: decibels(phoneSpeakerRMS(samples)),
        centroid: spectrum.centroid, presence: spectrum.presence2to5k, t60: decay.t60, ring: decay.ring,
        largestStep: largestStep(samples), finite: samples.allSatisfy(\.isFinite))
    if continuous {
        let tonal = periodicity(samples)
        measurement.periodicityMax = tonal.maximum
        measurement.periodicityMedian = tonal.median
        measurement.pitchLow = tonal.pitchLow
        measurement.pitchHigh = tonal.pitchHigh
        measurement.sounding = tonal.soundingShare
    }
    results[name] = measurement
    order.append(name)
    if writesFiles { try writeWAV(samples, to: outputDirectory.appendingPathComponent("\(name).wav")) }
    return measurement
}

// MARK: - Scenarios

let doors: [(String, SoundProfile)] = [
    ("oak", .oak), ("cottage", .pine), ("barn", .barn), ("castle", .castle), ("spaceship", .spaceship),
    ("metal", .steel),
]
let metals: [(String, MetalTone)] = [
    ("iron", .iron), ("brass", .brass), ("chrome", .chrome), ("copper", .copper), ("bronze", .bronze),
]

/// Event speeds in degrees per second, typical for each kind of close (see `DoorMotionInterpreter`).
let gentleSpeed: Float = 50, firmSpeed: Float = 150, slamSpeed: Float = 320, hardSlamSpeed: Float = 600
let openStopSpeed: Float = 120

let events: [(String, Float, [Cue])] = [
    ("knock", 1.2, [knock(0.5, 0.5, at: 0.05)]),
    ("unlatch", 1.2, [event(.unlatch, speed: 30, at: 0.05)]),
    ("latch-gentle", 1.4, [event(.latch, speed: gentleSpeed, at: 0.05)]),
    ("latch-firm", 1.4, [event(.latch, speed: firmSpeed, at: 0.05)]),
    ("slam", 2.5, [event(.slam, speed: slamSpeed, at: 0.05)]),
    ("open-stop", 1.4, [event(.openStop, speed: openStopSpeed, at: 0.05)]),
]

let gestures: [(String, Gesture)] = [
    ("swing-slow", move(5, 120, over: 3)),
    ("swing-normal", move(5, 120, over: 1)),
    ("swing-fast", move(5, 150, over: 0.4)),
    ("swing-hesitate", move(5, 40, over: 0.8) + hold(40, for: 0.5) + move(40, 110, over: 0.8)),
    (
        "swing-wiggle",
        Gesture(duration: 2) { 60 + 10 * sin(2 * .pi * 1.5 * $0) }
    ),
    ("swing-open-close", move(5, 110, over: 1) + hold(110, for: 0.3) + move(110, 5, over: 0.8)),
]

/// Knock, knock. Open slowly, hit the stop, swing it shut fast: slam.
func sequence() -> [Cue] {
    [knock(0.5, 0.5, at: 0.1, volume: 0.9), knock(0.5, 0.45, at: 0.36), event(.unlatch, speed: 30, at: 1.3)]
        + swing(move(3, 150, over: 1.2), from: 1.35)
        + [event(.openStop, speed: openStopSpeed, at: 2.56)]
        + swing(move(150, 3, over: 0.45), from: 3.4)
        + [event(.slam, speed: slamSpeed, at: 3.86)]
}

func runScenarios() throws {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    for speaker in [false, true] {
        let prefix = speaker ? "speaker-" : ""
        for (door, profile) in doors {
            for (name, seconds, cues) in events {
                try measure(
                    "\(prefix)\(door)-\(name)", seconds: seconds, cues: cues, profile: profile, speaker: speaker)
            }
            for (name, gesture) in gestures {
                try measure(
                    "\(prefix)\(door)-\(name)", seconds: gesture.duration + 1.2, cues: swing(gesture, from: 0.1),
                    profile: profile, speaker: speaker, continuous: true)
            }
            try measure("\(prefix)\(door)-sequence", seconds: 5.5, cues: sequence(), profile: profile, speaker: speaker)
        }
    }
    // Hardware on the reference door.
    for (metal, tone) in metals {
        let profile = SoundProfile.oak.with(metal: tone)
        try measure("oak-\(metal)-latch-firm", seconds: 1.4, cues: events[3].2, profile: profile)
        try measure(
            "oak-\(metal)-swing-slow", seconds: 4.2, cues: swing(move(5, 120, over: 3), from: 0.1), profile: profile,
            continuous: true)
    }
    // How hard: closing at increasing speed should get louder and brighter, without big jumps.
    for speed: Float in [20, 40, 60, 89, 91, 120, 160, 200, 259, 261, 320, 450, 600] {
        let sound: DoorSound = speed >= 260 ? .slam : .latch
        try measure(
            "oak-close-\(Int(speed))", seconds: 2.5, cues: [event(sound, speed: speed, at: 0.05)], profile: .oak)
    }
    try measure(
        "oak-slam-hard", seconds: 2.5, cues: [event(.slam, speed: hardSlamSpeed, at: 0.05)], profile: .oak)
    // The same gesture fed at different hinge update rates should sound about the same.
    for (name, rate, irregular) in [
        ("20hz", Float(20), false), ("60hz", 60, false), ("120hz", 120, false), ("irregular", 60, true),
    ] {
        try measure(
            "oak-rate-\(name)", seconds: 2.4,
            cues: swing(move(5, 120, over: 1.2), from: 0.1, rate: rate, irregular: irregular),
            profile: .oak, continuous: true)
    }
    // Stacked hits: 200 commands at once.
    try measure(
        "oak-burst", seconds: 1.5, cues: (0..<200).map { _ in event(.slam, speed: slamSpeed, at: 0.05) }, profile: .oak)
}

// MARK: - Reports

func pad(_ text: String, _ width: Int) -> String { text.padding(toLength: width, withPad: " ", startingAt: 0) }
func number(_ value: Float, _ width: Int = 7, _ decimals: Int = 1) -> String {
    let text = String(format: "%.\(decimals)f", value)
    return String(repeating: " ", count: max(0, width - text.count)) + text
}

/// Target level of each event on the phone measure, relative to that door's slam (dB), from the design.
let loudnessTargets: [String: (Float, String)] = [
    "knock": (-4, "≈"), "latch-firm": (-6, "≈"), "open-stop": (-8, "≈"), "latch-gentle": (-12, "≈"),
    "unlatch": (-12, "≈"), "swing-normal": (-10, "≤"), "swing-slow": (-10, "≤"),
]

func report() {
    print("\n== Loudness on the phone measure (voiced), relative to the door's slam; target in brackets")
    print(pad("door", 10), events.map { pad($0.0, 15) }.joined(), pad("swing-slow", 15), pad("swing-normal", 15))
    for (door, _) in doors {
        guard let slam = results["speaker-\(door)-slam"]?.onPhone else { continue }
        var row = pad(door, 10)
        for name in events.map(\.0) + ["swing-slow", "swing-normal"] {
            guard let level = results["speaker-\(door)-\(name)"]?.onPhone else { continue }
            let relative = level - slam
            var mark = " "
            if let (target, kind) = loudnessTargets[name] {
                let miss = kind == "≤" ? relative > target + 0.5 : abs(relative - target) > 3
                mark = miss ? "!" : " "
                row += pad(number(relative, 6) + " (\(Int(target)))\(mark)", 15)
            } else {
                row += pad(number(relative, 6) + "  slam=\(Int(slam.rounded()))", 15)
            }
        }
        print(row)
    }

    print("\n== Peaks: worst output peak and level into the soft clipper (dBFS), per door, flat and voiced")
    for (door, _) in doors {
        for prefix in ["", "speaker-"] {
            let rows = results.filter { $0.key.hasPrefix("\(prefix)\(door)-") }
            guard let worst = rows.max(by: { $0.value.clipperIn < $1.value.clipperIn }) else { continue }
            print(
                pad("\(prefix)\(door)", 18), "peak", number(worst.value.peak), "  clipper in",
                number(worst.value.clipperIn),
                "  (\(worst.key))")
        }
    }

    print("\n== Door balance: full sequence RMS (flat / voiced phone measure)")
    let sequenceLevels = doors.compactMap { door, _ in results["\(door)-sequence"].map { (door, $0) } }
    for (door, value) in sequenceLevels {
        print(
            pad(door, 10), "rms", number(value.rms), "   on phone (voiced)",
            number(results["speaker-\(door)-sequence"]?.onPhone ?? 0))
    }
    if let high = sequenceLevels.map(\.1.rms).max(), let low = sequenceLevels.map(\.1.rms).min() {
        print("spread", number(high - low), "dB (target ≤ 6)")
    }

    print(
        "\n== Swing sound (flat): periodicity max/median (wood target < 0.5), pitch p10–p90, sounding share, rms, presence 2–5 kHz"
    )
    for (door, _) in doors {
        for (name, _) in gestures {
            guard let m = results["\(door)-\(name)"] else { continue }
            print(
                pad("\(door)-\(name)", 26), number(m.periodicityMax ?? 0, 5, 2), number(m.periodicityMedian ?? 0, 5, 2),
                number(m.pitchLow ?? 0, 6, 0), "–", number(m.pitchHigh ?? 0, 4, 0), "Hz",
                number((m.sounding ?? 0) * 100, 5, 0), "%", "  rms", number(m.rms), "  presence",
                number(m.presence * 100, 4, 0), "%")
        }
    }

    print("\n== How hard: oak closes by speed (rms, centroid, phone)")
    for speed in [20, 40, 60, 89, 91, 120, 160, 200, 259, 261, 320, 450, 600] {
        guard let m = results["oak-close-\(speed)"] else { continue }
        print(
            pad("\(speed)°/s", 8), "rms", number(m.rms), "  centroid", number(m.centroid, 6, 0), "Hz  on phone",
            number(m.onPhone))
    }

    print("\n== Decay (T60 estimate from the Schroeder curve) of the slam, flat")
    for (door, _) in doors {
        if let m = results["\(door)-slam"] {
            print(pad(door, 10), "T60", number(m.t60, 5, 2), "s   ring", number(m.ring, 5, 2), "s")
        }
    }

    print("\n== Update rate independence (oak swing, rms / sounding)")
    for name in ["20hz", "60hz", "120hz", "irregular"] {
        if let m = results["oak-rate-\(name)"] {
            print(pad(name, 10), "rms", number(m.rms), "  sounding", number((m.sounding ?? 0) * 100, 4, 0), "%")
        }
    }

    let nonFinite = results.filter { !$0.value.finite }.map(\.key)
    let over = results.filter { $0.value.peak > 0 }.map(\.key)
    print(
        "\n== Safety: non-finite renders:", nonFinite.isEmpty ? "none" : nonFinite.joined(separator: ", "),
        "  peaks ≥ 0 dBFS:", over.isEmpty ? "none" : over.joined(separator: ", "),
        "  burst largest step:", number(results["oak-burst"]?.largestStep ?? 0, 5, 3))
}

func compare(with path: String) throws {
    let before = try JSONDecoder().decode(
        [String: Measurement].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    print("\n== Before → after (\(path)): flat renders")
    print(pad("sound", 30), "  rms dB          on phone dB      centroid Hz       periodicity")
    for name in order where !name.hasPrefix("speaker-") {
        guard let old = before[name], let new = results[name] else { continue }
        var line = pad(name, 30)
        line += number(old.rms) + " →" + number(new.rms) + "  "
        line += number(old.onPhone) + " →" + number(new.onPhone) + "  "
        line += number(old.centroid, 6, 0) + " →" + number(new.centroid, 6, 0)
        if let a = old.periodicityMax, let b = new.periodicityMax {
            line += "  " + number(a, 5, 2) + " →" + number(b, 5, 2)
        }
        print(line)
    }
}

// MARK: - Render cost

/// Seconds of CPU per second of audio, in percent of one core, for a busy and a quiet case.
func benchmark() {
    func cost(_ label: String, seconds: Float = 20, setup: (DoorSynth, Int) -> Void) {
        let synth = DoorSynth(sampleRate: sampleRate, profile: .castle, seed: 3, speakerVoicing: true)
        var buffer = [Float](repeating: 0, count: blockSize)
        let blocks = Int(seconds * sampleRate) / blockSize
        let start = DispatchTime.now().uptimeNanoseconds
        for block in 0..<blocks {
            setup(synth, block)
            buffer.withUnsafeMutableBufferPointer { synth.render(into: $0) }
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        print(pad(label, 44), String(format: "%6.2f %% of a core", elapsed / Double(seconds) * 100))
    }
    print("\n== Render cost at 48 kHz, \(blockSize)-frame buffers, speaker voicing on (this machine)")
    cost("idle") { _, _ in }
    cost("swinging (continuous swing sound)") { synth, block in
        let t = Float(block * blockSize) / sampleRate
        synth.setSwingForTool(angle: 90 + 60 * sin(t), velocity: 60 * cos(t) * 2)
    }
    cost("worst case: every voice busy + swinging") { synth, block in
        if block % 8 == 0 {
            for _ in 0..<8 { synth.play(.slam, speed: hardSlamSpeed) }
        }
        let t = Float(block * blockSize) / sampleRate
        synth.setSwingForTool(angle: 90 + 60 * sin(t), velocity: 120 * cos(t))
    }
}

if !benchOnly {
    try runScenarios()
    report()
    if let jsonPath {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(results).write(to: URL(fileURLWithPath: jsonPath))
    }
    if let baselinePath { try compare(with: baselinePath) }
}
benchmark()
if !benchOnly, writesFiles { print("\nWrote WAV files to \(outputDirectory.path)") }
