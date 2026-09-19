import Foundation
import Observation
import SwiftData

/// Owns one conversation, start to finish.
///
/// Four things contend for one microphone and one voice — listening,
/// understanding, answering, speaking — so exactly one object drives them, in
/// one explicit order. A turn runs: hear a finished sentence, close the mic,
/// work out what was asked, build the true answer, warm it, speak it, reopen
/// the mic.
///
/// A session only ever begins because the person asked for it. There is no
/// wake word and nothing is heard in between. It ends when they end it, when
/// the quiet runs long, or when the privacy window closes — and on the way out
/// it writes a single plain recap into the event log.
@Observable
@MainActor
final class CompanionSession {

    enum Phase: Equatable {
        case closed
        case opening
        case listening
        /// Working out what was asked. The microphone is closed.
        case thinking
        case speaking
        /// Closed to input, finishing the recap.
        case wrappingUp
    }

    private(set) var phase: Phase = .closed

    /// What the companion last said, mirrored on screen.
    private(set) var transcriptLine: String = ""

    /// Set when listening could not start. The conversation still works by
    /// tapping questions; only the microphone is missing.
    private(set) var listeningProblem: String?

    var isOpen: Bool { phase != .closed }

    let listening: ListeningService
    private let speech: SpeechManager
    private let comprehension: ComprehensionEngine
    private let phrasing: PhrasingEngine
    private let settings: SummarizationSettings

    // Conversation state. Raw turns live here and nowhere else, and are never
    // written to the store. `pendingTurns` is held only until the next fold;
    // `fullTranscript` spans the whole session so the close-time significance
    // check can read it, and is discarded the moment the session closes.
    private var conversation: Conversation?
    private var digest = ConversationDigest()
    private var pendingTurns: [String] = []
    private var pendingCharacters = 0
    private var fullTranscript: [String] = []
    /// How many times the person actually said something. A session where
    /// nobody spoke is not a conversation and leaves no trace.
    private var turnsHeard = 0
    /// Refreshed on each turn so folds and answers see the current store.
    private var store: ConversationStore?

    private var foldChain: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?

    init(
        speech: SpeechManager,
        comprehension: ComprehensionEngine,
        phrasing: PhrasingEngine,
        listening: ListeningService? = nil,
        settings: SummarizationSettings? = nil
    ) {
        self.speech = speech
        self.comprehension = comprehension
        self.phrasing = phrasing
        self.listening = listening ?? ListeningService()
        self.settings = settings ?? .default

        // Speaking and listening take turns rather than overlap, so the
        // microphone reopens only once the voice has actually stopped.
        speech.onFinishedSpeaking = { [weak self] in
            self?.handleFinishedSpeaking()
        }
    }

    // MARK: - Opening and closing

    /// Begins a conversation. The one thing the app ever asks the person to do.
    func open(store: ConversationStore) async {
        guard phase == .closed else { return }
        phase = .opening
        listeningProblem = nil
        digest = ConversationDigest()
        pendingTurns = []
        pendingCharacters = 0
        fullTranscript = []
        turnsHeard = 0
        self.store = store

        let conversation = Conversation(startedAt: .now, participants: [])
        store.context.insert(conversation)
        self.conversation = conversation

        listening.primeVocabulary(people: store.people, topics: store.comfortTopics)

        // Listening starts first so the audio session is already in its
        // conversation configuration. Switching category underneath a line
        // that is mid-sentence clips it and churns the microphone.
        await listening.start { [weak self] turn in
            self?.receive(turn, store: store)
        }

        if case .unavailable(let reason) = listening.state {
            listeningProblem = reason
        }

        say(GroundingService.conversationOpener(facts: store.groundingDigest().facts),
            priority: .ambient)

        startExpiryTimer(store: store)
        restartSilenceTimer(store: store)
    }

    /// Ends the conversation and writes what it was about into the log.
    func close(store: ConversationStore) async {
        guard phase != .closed, phase != .wrappingUp else { return }
        phase = .wrappingUp

        expiryTask?.cancel()
        silenceTask?.cancel()
        expiryTask = nil
        silenceTask = nil

        await listening.stop()

        // Let any fold already running finish, then fold the tail, so the last
        // thing said still counts toward the recap.
        await foldChain?.value
        fold(store: store, force: true)
        await foldChain?.value

        if let conversation {
            if turnsHeard == 0 {
                // Opened and never spoken into. Leaving a "you had a chat"
                // entry would be a memory of something that did not happen.
                store.context.delete(conversation)
            } else {
                await writeRecap(for: conversation, store: store)
            }
        }

        conversation = nil
        self.store = nil
        pendingTurns = []
        pendingCharacters = 0
        fullTranscript = []
        turnsHeard = 0
        phase = .closed
    }

    /// Judges the whole transcript once, and only writes a summary — to the
    /// conversation and to the event log — when the model actually judged it
    /// significant. With no model verdict there is nothing to say that is not
    /// already sitting in the store as plain facts (who, when), so nothing
    /// beyond that bookkeeping gets written. The transcript itself never
    /// reaches the store; it lives only long enough for this one call.
    private func writeRecap(for conversation: Conversation, store: ConversationStore) async {
        let participants = digest.mentionedPeople(from: store.people)
        let transcript = fullTranscript.joined(separator: " ")
        let judged = await comprehension.summarizeSignificance(transcript: transcript, people: store.people)

        conversation.endedAt = .now
        conversation.participants = participants
        conversation.lastModified = .now

        guard let judged else { return }
        let summary = judged.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard judged.isSignificant, !summary.isEmpty else { return }

        conversation.summary = summary

        // The recap joins the one event log, so the day reads as one story.
        let event = Event(
            title: summary,
            when: conversation.startedAt,
            source: .conversation,
            conversationID: conversation.id,
            participants: participants
        )
        store.context.insert(event)
    }

    // MARK: - One turn

    private func receive(_ turn: String, store: ConversationStore) {
        guard phase == .listening || phase == .opening else { return }
        self.store = store

        turnsHeard += 1
        pendingTurns.append(turn)
        pendingCharacters += turn.count
        fullTranscript.append(turn)
        restartSilenceTimer(store: store)

        phase = .thinking
        listening.pause()

        Task { await respond(to: turn, store: store) }
    }

    private func respond(to turn: String, store: ConversationStore) async {
        let intent = await comprehension.interpret(turn, people: store.people)
        guard phase == .thinking else { return }

        let grounded = GroundingService.answer(
            for: intent,
            digest: store.groundingDigest(),
            people: store.people,
            lastSpoken: speech.lastSpoken
        )

        // Frightened or verbatim moments never touch the phrasing model.
        let line = intent.isVerbatim ? grounded : await phrasing.warmlyRephrase(grounded)
        guard phase == .thinking else { return }

        say(line, priority: intent == .distress ? .grounding : .reply)
    }

    private func say(_ line: String, priority: SpeechManager.Priority) {
        transcriptLine = line
        phase = .speaking
        // Half-duplex: stop taking input rather than transcribe our own voice.
        listening.pause()
        speech.speak(line, priority: priority)
    }

    /// The voice has stopped, so the microphone can reopen. This is also the
    /// dead time a fold belongs in — the person is thinking, nothing is
    /// blocked on it, and the model call costs no perceived latency.
    private func handleFinishedSpeaking() {
        guard phase == .speaking else { return }
        phase = .listening
        listening.resume()
        if let store { fold(store: store) }
    }

    // MARK: - Rolling the digest forward

    /// Folds buffered turns into the digest when there are enough of them.
    ///
    /// Folds are serialised: two at once would race on `digest` and the merge
    /// order would stop being deterministic.
    private func fold(store: ConversationStore, force: Bool = false) {
        let ready = pendingTurns.count >= settings.turnsPerBeat
            || pendingCharacters >= settings.charactersPerBeat
        guard force || ready, !pendingTurns.isEmpty else { return }

        let batch = pendingTurns
        pendingTurns = []
        pendingCharacters = 0

        let people = store.people
        let topics = store.comfortTopics
        let usesModel = settings.usesModelExtraction
        let previous = foldChain

        foldChain = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let beat = await self.comprehension.extractBeat(
                from: batch, people: people, topics: topics, usesModel: usesModel
            )
            guard let beat else { return }
            self.digest.fold(beat, known: people)
        }
    }

    // MARK: - Timers

    /// The privacy window. Non-negotiable: the session closes itself.
    private func startExpiryTimer(store: ConversationStore) {
        expiryTask?.cancel()
        let window = settings.sessionWindow
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard !Task.isCancelled, let self else { return }
            await self.close(store: store)
        }
    }

    /// A quiet room means the conversation is over, whether or not anyone said so.
    ///
    /// Before anyone has spoken the wait is short — the person probably opened
    /// this by accident, or changed their mind. Once a conversation is under
    /// way it is much longer, because searching for a word takes time and
    /// being cut off mid-thought is exactly the experience to avoid.
    private func restartSilenceTimer(store: ConversationStore) {
        silenceTask?.cancel()
        let timeout = turnsHeard == 0 ? settings.openingSilenceTimeout : settings.silenceTimeout
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self else { return }
            await self.close(store: store)
        }
    }
}

/// The slice of the store a conversation needs, gathered once by the view.
///
/// `CompanionSession` stays out of SwiftData's way: the view owns the queries
/// and hands over plain arrays plus the context to write back through.
@MainActor
struct ConversationStore {
    let context: ModelContext
    let facts: GroundingFacts?
    let events: [Event]
    let people: [Person]
    let comfortTopics: [ComfortTopic]

    /// The wider window the companion may draw on — more than Home shows.
    func groundingDigest(at date: Date = .now) -> GroundingDigest {
        GroundingDigest(
            facts: facts ?? ConversationStore.placeholderFacts,
            events: events,
            comfortTopics: comfortTopics,
            at: date
        )
    }

    /// Only reachable if the store was never seeded. Says nothing it cannot
    /// know, rather than inventing a place or a person to call.
    private static let placeholderFacts = GroundingFacts(
        userName: "there",
        homeLabel: "home",
        roomLabel: "your room",
        currentCaregiverName: "Someone",
        currentCaregiverRelationship: "looking after you",
        primaryContactName: "your emergency contact",
        primaryContactRelationship: "your contact",
        primaryContactPhone: ""
    )
}
