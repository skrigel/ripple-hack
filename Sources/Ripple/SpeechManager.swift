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

    /// How the voice carries. Warmth comes from the pauses more than the speed:
    /// a line that breathes between sentences sounds thoughtful, where one that
    /// is merely slowed down sounds laboured.
    private enum Voicing {
        /// A little under the 0.5 default — unhurried without dragging.
        static let rate: Float = 0.46
        /// Slightly below natural pitch. Reads as calm rather than bright.
        static let pitch: Float = 0.97
        /// The beat between one sentence and the next.
        static let sentenceBreath: TimeInterval = 0.22
        /// The beat after a whole line, before the microphone reopens.
        static let endOfLinePause: TimeInterval = 0.2
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
    private let voice: AVSpeechSynthesisVoice?

    /// Sentences awaiting their turn, across however many lines are pending.
    private var queue: [Chunk] = []
    private var current: Chunk?

    init() {
        AudioSessionCoordinator.configureForPlayback()
        voice = Self.preferredVoice()

        delegate.onRange = { [weak self] range, spoken in
            guard let self, let chunk = self.current,
                  let bounds = Range(range, in: spoken) else { return }
            // `spoken` is only the sentence being voiced, so the part of the
            // line that came before it is prepended to keep the reveal whole.
            self.spokenPrefix = chunk.leading + String(spoken[spoken.startIndex..<bounds.upperBound])
        }
        delegate.onFinish = { [weak self] in self?.advance() }
        synthesizer.delegate = delegate
    }

    /// Speaks a line, or queues it behind what is already being said.
    func speak(_ text: String, priority: Priority = .reply) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        let chunks = Self.sentences(of: line)
        guard !chunks.isEmpty else { return }

        if priority == .grounding {
            // Nothing outranks orientation: drop what is queued and cut in.
            queue = chunks
            synthesizer.stopSpeaking(at: .immediate)
            if !isSpeaking { advance() }
            return
        }

        queue.append(contentsOf: chunks)
        if !isSpeaking { advance() }
    }

    func repeatLast() {
        speak(lastSpoken, priority: .grounding)
    }

    func stop() {
        queue.removeAll()
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        spokenPrefix = ""
    }

    // MARK: - Queue

    private func advance() {
        guard !queue.isEmpty else {
            current = nil
            isSpeaking = false
            onFinishedSpeaking?()
            return
        }

        let next = queue.removeFirst()
        current = next
        if next.isLineStart {
            lastSpoken = next.line
            spokenPrefix = ""
        }
        isSpeaking = true

        let utterance = AVSpeechUtterance(string: next.text)
        utterance.rate = Voicing.rate
        utterance.pitchMultiplier = Voicing.pitch
        utterance.preUtteranceDelay = next.isLineStart ? 0 : Voicing.sentenceBreath
        utterance.postUtteranceDelay = next.isLineEnd ? Voicing.endOfLinePause : 0
        utterance.voice = voice

        synthesizer.speak(utterance)
    }

    // MARK: - Sentences

    /// One sentence of a line, carrying enough of its context that the screen
    /// can keep revealing against the whole line while the voice works through
    /// it a sentence at a time.
    private struct Chunk {
        /// The sentence handed to the synthesizer.
        let text: String
        /// Everything in the line before this sentence, including the spacing.
        let leading: String
        /// The full line, mirrored on screen and replayed by "Say that again".
        let line: String
        let isLineStart: Bool
        let isLineEnd: Bool
    }

    /// Break a line at its sentence endings.
    ///
    /// A terminator only ends a sentence when whitespace or the end of the line
    /// follows it, which means a run like "..." breaks once, at the last dot,
    /// and a colon-separated clock time is never mistaken for one.
    private static func sentences(of line: String) -> [Chunk] {
        var pieces: [Substring] = []
        var start = line.startIndex
        var index = line.startIndex

        while index < line.endIndex {
            let next = line.index(after: index)
            if ".!?".contains(line[index]), next == line.endIndex || line[next].isWhitespace {
                pieces.append(line[start..<next])
                start = next
            }
            index = next
        }
        if start < line.endIndex { pieces.append(line[start...]) }

        let chunks: [(text: String, leading: String)] = pieces.compactMap { piece in
            guard let begin = piece.firstIndex(where: { !$0.isWhitespace }) else { return nil }
            let text = String(piece[begin...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return (text, String(line[line.startIndex..<begin]))
        }

        return chunks.enumerated().map { offset, chunk in
            Chunk(
                text: chunk.text,
                leading: chunk.leading,
                line: line,
                isLineStart: offset == 0,
                isLineEnd: offset == chunks.count - 1
            )
        }
    }

    // MARK: - Voice

    /// The warmest installed English voice.
    ///
    /// Ranked rather than taken first-found: the order `speechVoices()` returns
    /// is not guaranteed, so picking the first non-default one could land on a
    /// distant regional accent — a stranger's voice, for someone who needs a
    /// familiar one. Quality dominates, then a matching region.
    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let best = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.identifier.hasPrefix(noveltyPrefix) }
            .max { rank($0) < rank($1) }
        return best ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// The namespace the toy voices (Bells, Bubbles, Trinoids) live in. They
    /// would never win on quality, but they must not win by default either.
    private static let noveltyPrefix = "com.apple.speech.synthesis.voice."

    private static func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        var score = 0
        switch voice.quality {
        case .premium: score += 40
        case .enhanced: score += 20
        default: break
        }
        if voice.language == AVSpeechSynthesisVoice.currentLanguageCode() { score += 10 }
        return score
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
