import AVFoundation
import os

protocol DoorSoundPlaying: AnyObject {
    func apply(profile: SoundProfile)
    func play(_ sound: DoorSound, volume: Float)
    /// Signed hinge velocity in degrees per second. 0 lets the creak fade out.
    func setCreak(velocity: Double)
}

/// Runs `DoorSynth` through `AVAudioEngine` with an `AVAudioSourceNode`.
final class DoorAudioEngine: DoorSoundPlaying {
    private let engine = AVAudioEngine()
    private let synth: DoorSynth
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Duor", category: "audio")
    private var observers: [Task<Void, Never>] = []
    /// True while an asynchronous session activation is in flight, so overlapping calls don't stack up.
    private var isStarting = false

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
        synth = DoorSynth(sampleRate: Float(sampleRate))

        let source = Self.makeSourceNode(for: synth)
        engine.attach(source)
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
            try engine.connectNode(source, to: engine.mainMixerNode, format: format)
        } catch {
            logger.error("Audio engine setup failed: \(error.localizedDescription)")
        }
        startIfNeeded()
        observeRestarts()
    }

    func apply(profile: SoundProfile) {
        synth.setProfile(profile)
    }

    func play(_ sound: DoorSound, volume: Float) {
        startIfNeeded()
        synth.play(sound, volume: volume)
    }

    func setCreak(velocity: Double) {
        synth.setCreak(velocity: Float(velocity))
    }

    /// The render block runs on the real-time audio thread, so it is built outside the main actor.
    private nonisolated static func makeSourceNode(for synth: DoorSynth) -> AVAudioSourceNode {
        AVAudioSourceNode { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let data = buffers.first?.mData else { return noErr }
            let output = UnsafeMutableBufferPointer(
                start: data.assumingMemoryBound(to: Float.self), count: Int(frameCount))
            synth.render(into: output)
            return noErr
        }
    }

    /// The engine stops on route changes (headphones in/out) and interruptions (calls, Siri).
    private func observeRestarts() {
        let names: [Notification.Name] = [
            .AVAudioEngineConfigurationChange,
            AVAudioSession.interruptionNotification,
            AVAudioSession.mediaServicesWereResetNotification,
        ]
        observers = names.map { name in
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    self?.startIfNeeded()
                }
            }
        }
    }

    /// Activates the session without blocking the main thread, then starts the engine.
    /// The engine is only started after activation: starting it first would activate the
    /// session synchronously.
    private func startIfNeeded() {
        guard !engine.isRunning, !isStarting else { return }
        isStarting = true
        Task {
            defer { isStarting = false }
            do {
                guard try await AVAudioSession.sharedInstance().activate(options: []) else {
                    logger.error("Audio session was not activated")
                    return
                }
                try engine.start()
            } catch {
                logger.error("Audio engine start failed: \(error.localizedDescription)")
            }
        }
    }
}
