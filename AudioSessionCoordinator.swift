import Foundation
import AVFoundation

/// One place that owns the audio session category.
///
/// Speaking and listening want different configurations, and the capture
/// pipeline reconfigures the session out from under us when it starts. Both
/// sides route through here so the last writer is always deliberate.
enum AudioSessionCoordinator {

    /// Speaking only — the app's resting state.
    ///
    /// `.playback` speaks even when the silent switch is on, which matters:
    /// a grounding line the person cannot hear is a line that did not happen.
    static func configureForPlayback() {
        apply(category: .playback, mode: .spokenAudio, options: [.duckOthers])
    }

    /// Speaking and listening together, during a conversation.
    ///
    /// Deliberately not `.voiceChat`: that engages voice-processing I/O, which
    /// is unreliable behind an `AVAudioEngine` tap and buys nothing here — the
    /// loop is half-duplex, so the microphone is already ignored while the
    /// companion is talking. `.defaultToSpeaker` keeps output on the
    /// loudspeaker rather than dropping to the earpiece when recording starts.
    static func configureForConversation() {
        apply(
            category: .playAndRecord,
            mode: .default,
            options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP]
        )
    }

    private static func apply(
        category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(category, mode: mode, options: options)
        try? session.setActive(true)
    }
}
