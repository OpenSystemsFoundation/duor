// The render tool's only link to the synth's control API, so the scenarios stay the same when it changes.

extension DoorSynth {
    func setSwingForTool(angle: Float, velocity: Float) {
        setSwing(angle: angle, velocity: velocity)
    }
}
