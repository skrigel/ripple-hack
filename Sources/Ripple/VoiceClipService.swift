import Foundation
import AVFoundation
import Observation

/// Records and plays back the short clip of a real voice attached to a `Person`.
///
/// This is the one sound the app makes that it did not synthesize: a caregiver's
/// own recording, played verbatim. No model is anywhere near it — the clip *is*
/// the content, exactly as it was recorded, so there is nothing here that could
/// decide something untrue.
///
/// Recording and playback are exclusive, with each other and with themselves, so
/// a clip never overlaps a spoken line. `onBeforeAudio` lets the services
/// container silence the synthesizer first without this type knowing it exists.
@Observable
@MainActor
final class VoiceClipService {

    /// Past this, a clip has stopped being a greeting and become a recording
    /// someone forgot to end. `AVAudioRecorder` stops itself at the limit.
    static let maximumDuration: TimeInterval = 30

    /// The clip just captured, waiting for the caller to keep or discard it.
    /// Consumed exactly once, through `takeRecordedClip()`.
    private(set) var recordedClip: Data?

    private(set) var isRecording = false

    /// When the current recording began, so the UI can count up without this
    /// service having to own a timer.
    private(set) var recordingStartedAt: Date?

    /// Which clip is sounding, keyed by whatever the caller uses to tell its
    /// rows apart — a `Person.id` in the people list, a per-sheet id while
    /// previewing a draft. `nil` when nothing is playing.
    private(set) var playingID: UUID?

    /// Called before this service takes the audio route, so the container can
    /// stop the synthesizer. Set once, in `RippleServices`.
    var onBeforeAudio: (() -> Void)?

    private let delegate = ClipDelegate()
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var fileURL: URL?

    init() {
        delegate.onFinishRecording = { [weak self] in self?.collectRecording() }
        delegate.onFinishPlaying = { [weak self] in self?.clearPlayer() }
    }

    // MARK: - Recording

    /// Starts capturing into a temporary file.
    ///
    /// Microphone permission is asked for here rather than at launch: a
    /// caregiver who never records a clip is never prompted.
    func startRecording() async {
        guard !isRecording, await hasMicrophonePermission() else { return }

        onBeforeAudio?()
        stopPlayback()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-clip-\(UUID().uuidString).m4a")

        // Mono AAC at a speech-appropriate rate. A full-length clip lands around
        // 120 KB — small enough to sit in the store beside the photo.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]

        AudioSessionCoordinator.configureForRecording()

        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else {
            AudioSessionCoordinator.configureForPlayback()
            return
        }
        recorder.delegate = delegate

        guard recorder.record(forDuration: Self.maximumDuration) else {
            AudioSessionCoordinator.configureForPlayback()
            return
        }

        self.recorder = recorder
        self.fileURL = url
        isRecording = true
        recordingStartedAt = .now
    }

    /// Ends the recording early. Either way the clip arrives the same way —
    /// through the delegate, here or when the duration cap runs out.
    func stopRecording() {
        guard isRecording else { return }
        recorder?.stop()
    }

    /// Hands the captured clip to the caller and clears it, so one recording
    /// can never be picked up twice.
    func takeRecordedClip() -> Data? {
        defer { recordedClip = nil }
        return recordedClip
    }

    private func collectRecording() {
        isRecording = false
        recordingStartedAt = nil
        recorder = nil
        AudioSessionCoordinator.configureForPlayback()

        guard let url = fileURL else { return }
        fileURL = nil
        recordedClip = try? Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Playback

    /// Plays a clip, or stops it if that same clip is already playing, so one
    /// button can serve both — there is only ever one thing to stop.
    func play(_ data: Data, id: UUID) {
        guard !isRecording else { return }

        if playingID == id {
            stopPlayback()
            return
        }

        onBeforeAudio?()
        stopPlayback()
        AudioSessionCoordinator.configureForPlayback()

        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.delegate = delegate
        guard player.play() else { return }

        self.player = player
        playingID = id
    }

    func stopPlayback() {
        player?.stop()
        clearPlayer()
    }

    private func clearPlayer() {
        player = nil
        playingID = nil
    }

    // MARK: - Permission

    private func hasMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .undetermined: await AVAudioApplication.requestRecordPermission()
        default: false
        }
    }
}

/// `AVAudioRecorderDelegate` and `AVAudioPlayerDelegate` both need an
/// `NSObject`, which an `@Observable` class cannot be — the same split
/// `SpeechManager` makes for the synthesizer.
private final class ClipDelegate:
    NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate, @unchecked Sendable {

    var onFinishRecording: (() -> Void)?
    var onFinishPlaying: (() -> Void)?

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        MainActor.assumeIsolated { onFinishRecording?() }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        MainActor.assumeIsolated { onFinishRecording?() }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        MainActor.assumeIsolated { onFinishPlaying?() }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        MainActor.assumeIsolated { onFinishPlaying?() }
    }
}
