import Foundation
import AVFoundation
import Observation
import Speech

/// Turns the microphone into finished sentences.
///
/// Debug version: logs the complete audio pipeline:
/// permission → AVAudioSession → AVAudioEngine → converter → SpeechAnalyzer → transcript.
@Observable
@MainActor
final class ListeningService {

    enum State: Equatable {
        case idle
        case preparing
        case listening
        case paused
        case unavailable(String)

        var isRunning: Bool {
            switch self {
            case .listening, .paused:
                true
            default:
                false
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var isHearingSpeech = false

    private var analyzer: SpeechAnalyzer?
    private var microphone: MicrophoneTap?
    private let context = AnalysisContext()

    private var resultsTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?

    private(set) var liveTranscript = ""

    private var onTurn: ((String) -> Void)?

    // MARK: - Vocabulary

    func primeVocabulary(
        people: [Person],
        topics: [ComfortTopic]
    ) {
        var phrases: [String] = []

        phrases.append(contentsOf: people.map(\.name))
        phrases.append(contentsOf: people.map(\.relationship))
        phrases.append(contentsOf: topics.map(\.title))

        let cleaned = phrases
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter {
                !$0.isEmpty
            }

        context.contextualStrings = [
            .general: Array(Set(cleaned).prefix(100))
        ]

        print("🧠 Vocabulary loaded:", cleaned)
    }

    // MARK: - Lifecycle

    func start(onTurn: @escaping (String) -> Void) async {
        guard state == .idle else { return }

        print("🎤 STARTING LISTENING")

        state = .preparing
        self.onTurn = onTurn
        self.liveTranscript = ""

        do {
            // MARK: Microphone permission

            let permission = AVAudioApplication.shared.recordPermission

            print("🎙️ MICROPHONE PERMISSION:", permission)

            guard permission == .granted else {
                state = .unavailable("Microphone permission is required.")
                return
            }

            // MARK: Speech transcriber

            guard let locale = await SpeechTranscriber.supportedLocale(
                equivalentTo: Locale.current
            ) else {
                state = .unavailable("Speech transcription is not available.")
                return
            }

            print("🌎 SPEECH LOCALE:", locale)

            let transcriber = SpeechTranscriber(
                locale: locale,
                preset: .progressiveTranscription
            )

            // NOTE: SpeechDetector removed — it was likely suppressing
            // all transcription output. Add it back only after basic
            // transcription is confirmed working.
            let modules: [any SpeechModule] = [
                transcriber
            ]

            // MARK: Speech assets

            print("📦 INSTALLING SPEECH ASSETS")

            if let installationRequest =
                try await AssetInventory.assetInstallationRequest(
                    supporting: modules
                ) {
                try await installationRequest.downloadAndInstall()
            }

            print("✅ SPEECH ASSETS READY")

            // MARK: Analyzer format

            guard let format =
                await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: modules
                ) else {
                state = .unavailable(
                    "No compatible audio format is available."
                )
                return
            }

            print("🎧 ANALYZER FORMAT:")
            print("   sample rate:", format.sampleRate)
            print("   channels:", format.channelCount)
            print("   common format:", format.commonFormat.rawValue)
            print("   interleaved:", format.isInterleaved)

            // MARK: Audio session

            let session = AVAudioSession.sharedInstance()

            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.defaultToSpeaker, .allowBluetooth]
            )

            try session.setActive(true)

            print("🔊 AUDIO SESSION READY")
            print("   sample rate:", session.sampleRate)
            print("   input:", session.currentRoute.inputs)
            print("   output:", session.currentRoute.outputs)

            // MARK: Analyzer

            let analyzer = SpeechAnalyzer(
                modules: modules
            )

            try await analyzer.setContext(context)

            // MARK: Microphone

            let microphone = MicrophoneTap(
                analyzerFormat: format
            )

            self.analyzer = analyzer
            self.microphone = microphone

            // Start consuming transcription results BEFORE starting
            // the analyzer, so we don't miss early results.
            consume(transcriber)

            // Start microphone.
            try microphone.start()

            print("🎤 MICROPHONE STARTED")

            state = .listening

            print("🟢 LISTENING")

            // Start the analyzer.
            try await analyzer.start(
                inputSequence: microphone.inputs
            )

            print("🛑 ANALYZER FINISHED")

        } catch {
            print("❌ LISTENING ERROR:", error)

            await tearDown()

            state = .unavailable(
                "Listening unavailable: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Pause / Resume

    func pause() {

        guard state == .listening else {
            print("⏸️ PAUSE IGNORED — state:", state)
            return
        }

        print("⏸️ Listening paused")

        state = .paused
        isHearingSpeech = false
    }

    func resume() {

        guard state == .paused else {
            print("▶️ RESUME IGNORED — state:", state)
            return
        }

        print("▶️ Listening resumed")

        resumedAt = .now
        state = .listening
    }

    /// When the microphone last reopened.
    ///
    /// Transcription lags the audio it describes, so a result delivered just
    /// after this covers sound from while the companion was still speaking.
    /// Without echo cancellation that sound is usually our own voice, and
    /// acting on it means answering ourselves.
    private var resumedAt: Date?
    private let echoTail: TimeInterval = 1.0

    private var isWithinEchoTail: Bool {
        guard let resumedAt else { return false }
        return Date.now.timeIntervalSince(resumedAt) < echoTail
    }

    // MARK: - Stop

    func stop() async {

        print("🛑 STOPPING LISTENING")

        await tearDown()

        state = .idle

        do {
            try AVAudioSession.sharedInstance()
                .setActive(false)
        } catch {
            print("⚠️ Could not deactivate audio session:", error)
        }

        print("🛑 Listening stopped")
    }

    // MARK: - Tear Down

    private func tearDown() async {

        print("🧹 Tearing down audio pipeline...")

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

        print("🧹 Audio pipeline torn down")
    }

    // MARK: - Results

    private func consume(_ transcriber: SpeechTranscriber) {
        resultsTask = Task { [weak self] in
            guard let self else { return }

            print("📝 TRANSCRIPTION CONSUMER STARTED — awaiting results…")

            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else {
                        print("📝 Transcription task cancelled")
                        return
                    }

                    let text = String(result.text.characters)
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )

                    print("🗣️ TRANSCRIPT RESULT")
                    print("   text:", text)
                    print("   final:", result.isFinal)

                    // Update UI with live transcription.
                    self.liveTranscript = text

                    // Still speaking / intermediate transcription.
                    if !result.isFinal {
                        self.isHearingSpeech = true
                        continue
                    }

                    // User finished speaking.
                    self.isHearingSpeech = false

                    guard self.state == .listening,
                          !text.isEmpty else {
                        continue
                    }

                    // Audio captured while we were talking, arriving late.
                    if self.isWithinEchoTail {
                        print("🔇 DISCARDED (echo tail):", text)
                        continue
                    }

                    print("✅ FINAL TRANSCRIPT:", text)

                    // Send the user's spoken query to the model.
                    self.onTurn?(text)
                }

                print("📝 transcriber.results sequence ended")

            } catch {
                print("❌ TRANSCRIPTION ERROR:", error)
                print("   localizedDescription:", error.localizedDescription)

                self.state = .unavailable(
                    "Transcription stopped unexpectedly."
                )
            }
        }
    }

    // MARK: - Permission

    private func isMicrophoneAuthorized() async -> Bool {

        let permission =
            AVAudioApplication.shared.recordPermission

        print("🎤 Current microphone permission:", permission)

        switch permission {

        case .granted:
            return true

        case .undetermined:

            print("🎤 Requesting microphone permission...")

            let granted =
                await AVAudioApplication.requestRecordPermission()

            print(
                granted
                    ? "✅ Microphone permission granted"
                    : "❌ Microphone permission denied"
            )

            return granted

        default:
            return false
        }
    }
}


// MARK: - MicrophoneTap

/// Pulls audio from AVAudioEngine and converts it into
/// the format expected by SpeechAnalyzer.
private final class MicrophoneTap: @unchecked Sendable {

    let inputs: AsyncStream<AnalyzerInput>

    private let engine = AVAudioEngine()
    private let analyzerFormat: AVAudioFormat

    private let continuation:
        AsyncStream<AnalyzerInput>.Continuation

    private var converter: AVAudioConverter?

    // Throttle logs so the console stays readable.
    private var bufferCount = 0
    private let logEveryN = 20

    init(analyzerFormat: AVAudioFormat) {
        self.analyzerFormat = analyzerFormat

        var continuation:
            AsyncStream<AnalyzerInput>.Continuation!

        self.inputs = AsyncStream { continuation = $0 }

        self.continuation = continuation
    }

    func start() throws {
        let input = engine.inputNode

        let format = input.outputFormat(forBus: 0)

        print("🎤 INPUT FORMAT")
        print("   sample rate:", format.sampleRate)
        print("   channels:", format.channelCount)
        print("   common format:", format.commonFormat.rawValue)
        print("   interleaved:", format.isInterleaved)

        guard format.sampleRate > 0,
              format.channelCount > 0 else {
            throw ListeningError.noInput
        }

        guard let converter = AVAudioConverter(
            from: format,
            to: analyzerFormat
        ) else {
            throw ListeningError.unsupportedFormat
        }

        self.converter = converter

        print("🔄 CONVERTER CREATED")
        print("   from:", format)
        print("   to:", analyzerFormat)

        input.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: format
        ) { [weak self] buffer, _ in

            guard let self else { return }

            guard buffer.frameLength > 0 else {
                return
            }

            self.bufferCount += 1
            let shouldLog = (self.bufferCount % self.logEveryN == 1)

            if shouldLog {
                print("🎤 GOT AUDIO BUFFER #\(self.bufferCount)")
                print("   frames:", buffer.frameLength)
                print("   sample rate:", buffer.format.sampleRate)
                print("   channels:", buffer.format.channelCount)

                let rms = Self.rms(of: buffer)
                print("   input RMS:", rms)
            }

            guard let converted = self.resample(buffer) else {
                if shouldLog {
                    print("⚠️ CONVERSION RETURNED NIL")
                }
                return
            }

            if shouldLog {
                print("✅ CONVERTED AUDIO")
                print("   frames:", converted.frameLength)
                print("   sample rate:", converted.format.sampleRate)
                print("   channels:", converted.format.channelCount)
                print("   output RMS:", Self.rms(of: converted))
            }

            self.continuation.yield(
                AnalyzerInput(buffer: converted)
            )
        }

        engine.prepare()

        try engine.start()

        print("🎙️ AVAudioEngine STARTED")
    }

    func stop() {
        print("🛑 STOPPING MICROPHONE")

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        continuation.finish()
    }

    // MARK: - Resample

    private func resample(
        _ buffer: AVAudioPCMBuffer
    ) -> AVAudioPCMBuffer? {

        guard let converter else {
            return nil
        }

        let ratio =
            analyzerFormat.sampleRate /
            buffer.format.sampleRate

        // Extra headroom: the converter can produce more frames than
        // the naive ratio implies, especially when downsampling.
        let outputCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * ratio
        ) + 1024

        guard let output = AVAudioPCMBuffer(
            pcmFormat: analyzerFormat,
            frameCapacity: outputCapacity
        ) else {
            return nil
        }

        var didProvideInput = false
        var error: NSError?

        let status = converter.convert(
            to: output,
            error: &error
        ) { _, outStatus in

            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true

            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            print("❌ CONVERTER ERROR:", error)
            return nil
        }

        guard status == .haveData || status == .inputRanDry else {
            print("⚠️ CONVERTER STATUS UNEXPECTED:", status.rawValue)
            return nil
        }

        guard output.frameLength > 0 else {
            return nil
        }

        return output
    }

    // MARK: - RMS helper

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else {
            return 0
        }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<n {
            let s = channel[i]
            sum += s * s
        }
        return sqrt(sum / Float(n))
    }
}

// MARK: - Errors

private enum ListeningError: Error {
    case noInput
    case unsupportedFormat
}
