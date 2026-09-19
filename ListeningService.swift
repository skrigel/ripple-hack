import Foundation
import AVFoundation
import Observation
import Speech

/// Turns the microphone into finished sentences.
///
/// It knows nothing about meaning: it reports what was said and stays quiet
/// otherwise. Listening only ever runs inside a conversation the person
/// started deliberately — there is no wake word and nothing is heard between
/// sessions.
///
/// Everything here is optional. If the microphone is refused, the language is
/// unsupported, or the speech assets will not install, the app falls back to
/// the tapped questions in `AssistantSheet` and loses nothing it must have.
@Observable
@MainActor
final class ListeningService {

    enum State: Equatable {
        case idle
        /// First run may need to download speech assets for the language.
        case preparing
        case listening
        /// Audio is still flowing but we are ignoring it, because we are talking.
        case paused
        case unavailable(String)

        var isRunning: Bool {
            switch self {
            case .listening, .paused: true
            default: false
            }
        }
    }

    private(set) var state: State = .idle

    /// Whether a voice is being picked up right now. Deliberately not exposed
    /// as text: a sentence that rewrites itself while someone reads it is
    /// disorienting, so the tentative transcript drives an indicator only.
    private(set) var isHearingSpeech = false

    private var analyzer: SpeechAnalyzer?
    private var microphone: MicrophoneTap?
    private let context = AnalysisContext()

    private var resultsTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?

    /// Called with each completed utterance, on the main actor.
    private var onTurn: ((String) -> Void)?

    // MARK: - Vocabulary

    /// Bias recognition toward the words that actually occur in this person's
    /// life, so "David" and "Cornwall" are heard as themselves. The framework
    /// asks for at most 100 short phrases.
    func primeVocabulary(people: [Person], topics: [ComfortTopic]) {
        var phrases: [String] = []
        phrases.append(contentsOf: people.map(\.name))
        phrases.append(contentsOf: people.map(\.relationship))
        phrases.append(contentsOf: topics.map(\.title))

        let cleaned = phrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        context.contextualStrings = [.general: Array(Set(cleaned).prefix(100))]
    }

    // MARK: - Lifecycle

    func start(onTurn: @escaping (String) -> Void) async {
        guard !state.isRunning, state != .preparing else { return }
        self.onTurn = onTurn
        state = .preparing

        guard await isMicrophoneAuthorized() else {
            state = .unavailable("I need permission to hear you.")
            return
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            state = .unavailable("I can't listen in this language yet.")
            return
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let detector = SpeechDetector()
        let modules: [any SpeechModule] = [detector, transcriber]

        do {
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await installation.downloadAndInstall()
            }

            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
                state = .unavailable("I can't listen on this device.")
                return
            }

            // Recording changes the session out from under the synthesiser,
            // so set the shared configuration before the engine starts.
            AudioSessionCoordinator.configureForConversation()

            let analyzer = SpeechAnalyzer(modules: modules)
            try await analyzer.setContext(context)

            let microphone = MicrophoneTap(analyzerFormat: format)
            self.analyzer = analyzer
            self.microphone = microphone

            consume(transcriber)

            try await analyzer.start(inputSequence: microphone.inputs)
            try microphone.start()

            state = .listening
        } catch {
            await tearDown()
            state = .unavailable("I couldn't start listening just now.")
        }
    }

    /// Stop acting on what we hear, without tearing the pipeline down. Used
    /// while the companion is speaking, so it does not transcribe itself.
    func pause() {
        guard state == .listening else { return }
        state = .paused
        isHearingSpeech = false
    }

    func resume() {
        guard state == .paused else { return }
        state = .listening
    }

    func stop() async {
        await tearDown()
        state = .idle
        AudioSessionCoordinator.configureForPlayback()
    }

    private func tearDown() async {
        resultsTask?.cancel()
        analysisTask?.cancel()
        resultsTask = nil
        analysisTask = nil

        microphone?.stop()
        await analyzer?.cancelAndFinishNow()

        microphone = nil
        analyzer = nil
        onTurn = nil
        isHearingSpeech = false
    }

    // MARK: - Results

    private func consume(_ transcriber: SpeechTranscriber) {
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self, !Task.isCancelled else { return }

                    // Tentative results only tell us someone is talking.
                    guard result.isFinal else {
                        if self.state == .listening { self.isHearingSpeech = true }
                        continue
                    }

                    self.isHearingSpeech = false
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    // Anything heard while we were talking is discarded, not
                    // queued: it is usually our own voice coming back.
                    guard self.state == .listening, !text.isEmpty else { continue }
                    self.onTurn?(text)
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.state = .unavailable("Listening stopped unexpectedly.")
            }
        }
    }

    private func isMicrophoneAuthorized() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        default: return false
        }
    }
}

/// Pulls audio off the microphone and converts it into analyzer inputs.
///
/// The tap runs on a realtime audio thread, so this deliberately owns its own
/// state and hands finished `AnalyzerInput` values across through a stream
/// rather than reaching back into the main actor.
///
/// The framework's own converters need a newer OS than this app targets, so
/// the resampling is done here with `AVAudioConverter`.
private final class MicrophoneTap: @unchecked Sendable {
    let inputs: AsyncStream<AnalyzerInput>

    private let engine = AVAudioEngine()
    private let analyzerFormat: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private var converter: AVAudioConverter?

    init(analyzerFormat: AVAudioFormat) {
        self.analyzerFormat = analyzerFormat
        (inputs, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
    }

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // The input node reports a zero format when no route is ready yet —
        // installing a tap on it produces empty buffers rather than an error.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw ListeningError.noInput
        }
        converter = AVAudioConverter(from: format, to: analyzerFormat)
        guard converter != nil else { throw ListeningError.unsupportedFormat }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            // The tap delivers empty buffers around route changes and while
            // the session is being reconfigured. Feeding one to the analyzer
            // trips an assertion inside CoreAudio, so drop them here.
            guard let self, buffer.frameLength > 0 else { return }
            guard let converted = self.resample(buffer), converted.frameLength > 0 else { return }
            self.continuation.yield(AnalyzerInput(buffer: converted))
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation.finish()
    }

    /// Converts one tap buffer into the analyzer's format. Runs on the audio
    /// thread, where the incoming buffer is only valid for this call.
    private func resample(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return nil }

        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else {
            return nil
        }

        // The input block is asked repeatedly; hand over this buffer once and
        // then report that nothing more has arrived yet.
        var supplied = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }

        guard conversionError == nil, output.frameLength > 0 else { return nil }
        return output
    }
}

private enum ListeningError: Error {
    case noInput
    case unsupportedFormat
}
