import Foundation
import AVFoundation
import Observation

/// The voice-first heart of the app. One spoken string is mirrored on screen
/// and can always be replayed — "Say that again" is instant and 100% reliable.
@Observable
final class SpeechManager {
    private let synthesizer = AVSpeechSynthesizer()

    /// The last thing we said. The screen mirrors this; "Say that again" replays it.
    private(set) var lastSpoken: String = ""

    init() {
        // Speak even when the silent switch is on, and duck other audio.
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: [.duckOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        lastSpoken = text
        synthesizer.stopSpeaking(at: .immediate)   // never let lines overlap

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.42                        // a touch slower, for clarity
        utterance.postUtteranceDelay = 0.2
        utterance.voice = preferredVoice()

        synthesizer.speak(utterance)
    }

    func repeatLast() {
        speak(lastSpoken)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Prefer an enhanced/premium en-US voice when the person has one installed;
    /// otherwise fall back to the default system voice.
    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let enhanced = AVSpeechSynthesisVoice.speechVoices().first {
            $0.language.hasPrefix("en") && $0.quality != .default
        }
        return enhanced ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}
