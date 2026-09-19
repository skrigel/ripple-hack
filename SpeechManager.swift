import Foundation
import AVFoundation
import Observation

/// The voice-first heart of the app. One spoken string is mirrored on screen
/// and can always be replayed — "Say that again" is instant and 100% reliable.
///
/// Lines are queued rather than cut off, so a reply does not truncate the line
/// before it. The exception is a grounding line, which preempts: if someone is
/// frightened, whatever was being said stops mattering immediately.
@Observable
@MainActor
final class SpeechManager {

    /// What a line is for, which decides whether it can interrupt.
    enum Priority: Int, Comparable {
        /// Reassurance and orientation. Jumps the queue and stops the current line.
        case grounding = 2
        /// An answer to something that was asked.
        case reply = 1
        /// An opener or a gentle redirect — never interrupts anything.
        case ambient = 0

        static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The last thing we said. The screen mirrors this; "Say that again" replays it.
    private(set) var lastSpoken: String = ""

    private(set) var isSpeaking = false

    /// How much of the current line has been voiced, so the on-screen text can
    /// reveal in step with the audio rather than on a guessed timer.
    private(set) var spokenPrefix: String = ""

    /// Called on the main actor when the queue drains. The conversation loop
    /// uses this to reopen the microphone.
    var onFinishedSpeaking: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = VoiceDelegate()
    private var queue: [(text: String, priority: Priority)] = []

    init() {
        AudioSessionCoordinator.configureForPlayback()

        delegate.onRange = { [weak self] range, full in
            guard let self, let bounds = Range(range, in: full) else { return }
            self.spokenPrefix = String(full[full.startIndex..<bounds.upperBound])
        }
        delegate.onFinish = { [weak self] in self?.advance() }
        synthesizer.delegate = delegate
    }

    /// Speaks a line, or queues it behind what is already being said.
    func speak(_ text: String, priority: Priority = .reply) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        if priority == .grounding {
            // Nothing outranks orientation: drop what is queued and cut in.
            queue = [(line, priority)]
            synthesizer.stopSpeaking(at: .immediate)
            if !isSpeaking { advance() }
            return
        }

        queue.append((line, priority))
        if !isSpeaking { advance() }
    }

    func repeatLast() {
        speak(lastSpoken, priority: .grounding)
    }

    func stop() {
        queue.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        spokenPrefix = ""
    }

    // MARK: - Queue

    private func advance() {
        guard !queue.isEmpty else {
            isSpeaking = false
            onFinishedSpeaking?()
            return
        }

        let next = queue.removeFirst()
        lastSpoken = next.text
        spokenPrefix = ""
        isSpeaking = true

        let utterance = AVSpeechUtterance(string: next.text)
        utterance.rate = 0.42                        // a touch slower, for clarity
        utterance.postUtteranceDelay = 0.2
        utterance.voice = preferredVoice()

        synthesizer.speak(utterance)
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

/// `AVSpeechSynthesizerDelegate` needs an `NSObject`, which an `@Observable`
/// class cannot be, so the callbacks live here and are forwarded.
private final class VoiceDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onRange: ((NSRange, String) -> Void)?
    var onFinish: (() -> Void)?

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        MainActor.assumeIsolated { onRange?(characterRange, utterance.speechString) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        MainActor.assumeIsolated { onFinish?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        MainActor.assumeIsolated { onFinish?() }
    }
}
