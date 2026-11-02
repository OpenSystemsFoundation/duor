import AVFoundation
import UIKit
import os

protocol DoorSoundPlaying: AnyObject {
    func apply(profile: SoundProfile)
    func play(_ sound: DoorSound, volume: Float)
    func knock(at spot: KnockSpot, volume: Float)
    /// Signed hinge velocity in degrees per second. 0 lets the creak fade out.
    func setCreak(velocity: Double)
}

/// When to voice the sound for the phone's own speakers (`SpeakerVoicing`). Automatic unless the
/// `-speakerVoicing on|off` launch argument says otherwise (for comparing the two on a device).
enum SpeakerVoicingMode: String {
    /// Only on the built-in speaker, not headphones, Bluetooth or AirPlay.
    case auto
    case on
    case off

    static let storageKey = "speakerVoicing"

    static var current: SpeakerVoicingMode {
        UserDefaults.standard.string(forKey: storageKey).flatMap(SpeakerVoicingMode.init) ?? .auto
    }

    func isOn(builtInSpeaker: Bool) -> Bool {
        switch self {
        case .auto: builtInSpeaker
        case .on: true
        case .off: false
        }
    }
}

/// Runs `DoorSynth` through `AVAudioEngine` with an `AVAudioSourceNode`.
final class DoorAudioEngine: DoorSoundPlaying {
    private let engine = AVAudioEngine()
    private let synth: DoorSynth
    /// Ramps the output to silence before the engine stops (`fadeOutAndStop`).
    private let fader: OutputFader
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Duor", category: "audio")
    private var observers: [Task<Void, Never>] = []
    /// True while an asynchronous session activation is in flight, so overlapping calls don't stack up.
    private var isStarting = false
    /// True while the app is in the background: the engine stays stopped until it comes back.
    private var isInBackground = false
    private var lifecycleObservers: [any NSObjectProtocol] = []

    init() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Play with the silent switch on, and mix with music the user already has playing.
            try session.setCategory(.playback, options: [.mixWithOthers])
            // Short buffers keep the time from hinge movement to sound low.
            try session.setPreferredIOBufferDuration(0.005)
        } catch {
            logger.error("Audio session setup failed: \(error.localizedDescription)")
        }

        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = hardwareRate > 0 ? hardwareRate : 48_000
        synth = DoorSynth(sampleRate: Float(sampleRate), speakerVoicing: Self.wantsSpeakerVoicing())
        fader = OutputFader(sampleRate: Float(sampleRate))

        let source = Self.makeSourceNode(for: synth, fader: fader)
        engine.attach(source)
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
            try engine.connectNode(source, to: engine.mainMixerNode, format: format)
        } catch {
            logger.error("Audio engine setup failed: \(error.localizedDescription)")
        }
        startIfNeeded()
        observeRestarts()
        observeLifecycle()
    }

    isolated deinit {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func apply(profile: SoundProfile) {
        synth.setProfile(profile)
    }

    func play(_ sound: DoorSound, volume: Float) {
        startIfNeeded()
        synth.play(sound, volume: volume)
    }

    func knock(at spot: KnockSpot, volume: Float) {
        startIfNeeded()
        synth.knock(at: spot, volume: volume)
    }

    func setCreak(velocity: Double) {
        synth.setCreak(velocity: Float(velocity))
    }

    /// Whether the sound goes to the built-in speaker (and the mode allows voicing for it).
    private static func wantsSpeakerVoicing() -> Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return SpeakerVoicingMode.current.isOn(builtInSpeaker: outputs.contains { $0.portType == .builtInSpeaker })
    }

    /// Follows the route: voiced on the phone's speakers, flat on headphones, Bluetooth or AirPlay.
    private func updateSpeakerVoicing() {
        let isOn = Self.wantsSpeakerVoicing()
        synth.setSpeakerVoicing(isOn)
        logger.info("Speaker voicing \(isOn ? "on" : "off")")
    }

    /// The render block runs on the real-time audio thread, so it is built outside the main actor.
    private nonisolated static func makeSourceNode(for synth: DoorSynth, fader: OutputFader) -> AVAudioSourceNode {
        AVAudioSourceNode { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let data = buffers.first?.mData else { return noErr }
            let output = UnsafeMutableBufferPointer(
                start: data.assumingMemoryBound(to: Float.self), count: Int(frameCount))
            synth.render(into: output)
            fader.apply(to: output)
            return noErr
        }
    }

    /// Quitting the app kills the process mid-stream, and leaving it freezes the app mid-stream
    /// (Duor doesn't play in the background): either way the speaker is left on a cut-off buffer,
    /// a crackle. Fade out and stop first; iOS gives the app a moment for it. These observers run
    /// synchronously on the main queue, so the fade is done before the app is frozen or killed.
    private func observeLifecycle() {
        let center = NotificationCenter.default
        let leaving: [Notification.Name] = [
            UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification,
        ]
        lifecycleObservers =
            leaving.map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.isInBackground = true
                        self?.fadeOutAndStop()
                    }
                }
            } + [
                center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.isInBackground = false
                        self?.startIfNeeded()
                    }
                }
            ]
    }

    /// Fades the output to silence, then stops the engine: stopping mid-waveform is a click. Blocks
    /// until a silent buffer has gone out (a couple of render cycles), at most `limit` in case the
    /// output has stalled.
    private func fadeOutAndStop(limit: Duration = .milliseconds(250)) {
        guard engine.isRunning else { return }
        fader.requestFade()
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        while !fader.isSilent, clock.now < deadline {
            usleep(1_000)
        }
        engine.stop()
    }

    /// The engine stops on route changes (headphones in/out) and interruptions (calls, Siri). A new
    /// route may also need different voicing.
    private func observeRestarts() {
        let names: [Notification.Name] = [
            .AVAudioEngineConfigurationChange,
            AVAudioSession.interruptionNotification,
            AVAudioSession.mediaServicesWereResetNotification,
            AVAudioSession.routeChangeNotification,
        ]
        observers = names.map { name in
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    self?.updateSpeakerVoicing()
                    self?.startIfNeeded()
                }
            }
        }
    }

    /// Activates the session without blocking the main thread, then starts the engine.
    /// The engine is only started after activation: starting it first would activate the
    /// session synchronously.
    private func startIfNeeded() {
        guard !engine.isRunning, !isStarting, !isInBackground else { return }
        isStarting = true
        Task {
            defer { isStarting = false }
            do {
                guard try await AVAudioSession.sharedInstance().activate(options: []) else {
                    logger.error("Audio session was not activated")
                    return
                }
                // The app may have left while the session was activating.
                guard !isInBackground, !engine.isRunning else { return }
                // Sound left mid-ring by a fade-out ramps back up instead of starting with a click.
                fader.reset()
                // The route is only certain once the session is active.
                updateSpeakerVoicing()
                try engine.start()
            } catch {
                logger.error("Audio engine start failed: \(error.localizedDescription)")
            }
        }
    }
}
