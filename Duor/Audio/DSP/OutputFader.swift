import Synchronization

/// Ramps the output to silence on the audio thread, so the engine can be stopped without a click
/// whatever is playing, and back up when it restarts (see `DoorAudioEngine.fadeOutAndStop`).
///
/// Stopping, or the app being frozen, mid-waveform leaves the speaker on a cut-off buffer: a
/// crackle. Fading first means the last buffer out is silence.
nonisolated final class OutputFader: Sendable {
    /// How long each ramp takes.
    static let fadeSeconds: Float = 0.005

    private let fadeRequested = Atomic<Bool>(false)
    private let silent = Atomic<Bool>(false)
    private let step: Float
    /// Only touched on the audio thread, in `apply`.
    private nonisolated(unsafe) var gain: Float = 1

    init(sampleRate: Float) {
        step = 1 / (Self.fadeSeconds * max(sampleRate, 1))
    }

    /// A whole buffer has gone out silent since the fade was asked for.
    var isSilent: Bool { silent.load(ordering: .acquiring) }

    func requestFade() {
        fadeRequested.store(true, ordering: .releasing)
    }

    /// Back to full level: the next buffers ramp up from silence, so sound left mid-ring when the
    /// output stopped doesn't start with a click.
    func reset() {
        silent.store(false, ordering: .relaxed)
        fadeRequested.store(false, ordering: .releasing)
    }

    /// After the synth has rendered a buffer. Real-time safe.
    func apply(to output: UnsafeMutableBufferPointer<Float>) {
        guard fadeRequested.load(ordering: .acquiring) else {
            guard gain < 1 else { return }
            for frame in output.indices {
                gain = min(1, gain + step)
                output[frame] *= gain
            }
            return
        }
        if gain == 0 {
            // The ramp ended in an earlier buffer, so this one is all silence.
            output.update(repeating: 0)
            silent.store(true, ordering: .releasing)
            return
        }
        for frame in output.indices {
            gain = max(0, gain - step)
            output[frame] *= gain
        }
    }
}
