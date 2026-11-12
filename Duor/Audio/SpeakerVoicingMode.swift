import Foundation

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
