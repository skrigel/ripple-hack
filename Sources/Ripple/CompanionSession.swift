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
/// the quiet runs long, or when the privacy window closes — and on the way
/// out the whole transcript is read once, to pull out anything worth
/// remembering, and then discarded for good.
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

    // Conversation state. The transcript lives here and nowhere else: it is
    // read once, when the session closes, to find anything worth
    // remembering, and is discarded the moment that is done. It is never
    // itself written to the store.
    private var conversation: Conversation?
    private var fullTranscript: [String] = []
    /// How many times the person actually said something. A session where
    /// nobody spoke is not a conversation and leaves no trace.
    private var turnsHeard = 0
    /// Refreshed on each turn so answers see the current store.
    private var store: ConversationStore?

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

        if let conversation {
            if turnsHeard == 0 {
                // Opened and never spoken into. Leaving a "you had a chat"
                // entry would be a memory of something that did not happen.
                store.context.delete(conversation)
            } else {
                await writeEvents(for: conversation, store: store)
            }
        }

        conversation = nil
        self.store = nil
        fullTranscript = []
        turnsHeard = 0
        phase = .closed
    }

    /// Reads the whole transcript once and turns anything worth remembering
    /// into events. This is the only point the transcript is used before it
    /// is discarded — nothing here is written to the store as raw text.
    private func writeEvents(for conversation: Conversation, store: ConversationStore) async {
        let transcript = fullTranscript.joined(separator: " ")
        let participants = Self.mentionedPeople(in: transcript, from: store.people)

        conversation.endedAt = .now
        conversation.participants = participants
        conversation.lastModified = .now

        let candidates = await comprehension.extractEvents(transcript: transcript, people: store.people)
        for candidate in candidates {
            guard let event = Self.makeEvent(from: candidate, conversation: conversation, participants: participants)
            else { continue }
            store.context.insert(event)
        }
    }

    /// Turns one candidate into a real event, or discards it.
    ///
    /// A stated date is parsed deterministically — the model names *what*
    /// happened and *whether* it is past or upcoming, never *when*, exactly.
    /// An upcoming event with no resolvable date would sit in the store with
    /// no way to later tell whether it has happened yet, so it is dropped
    /// rather than guessed at. A past event with no resolvable date is still
    /// worth keeping — it happened, the exact time just was not caught — so
    /// it is kept with `when = nil`: invisible in the UI's dated views, but
    /// still there for the assistant to draw on.
    private static func makeEvent(
        from candidate: CandidateEvent,
        conversation: Conversation,
        participants: [Person]
    ) -> Event? {
        if let date = resolveDate(from: candidate.statedWhen) {
            return Event(title: candidate.title, when: date, source: .conversation,
                         conversationID: conversation.id, participants: participants)
        }
        guard candidate.timing == .past else { return nil }
        return Event(title: candidate.title, when: nil, source: .conversation,
                     conversationID: conversation.id, participants: participants)
    }

    /// Parses a stated phrase like "Thursday at 3" into a real date. Only
    /// ever asked to resolve a phrase the model copied verbatim from what was
    /// said — never anything it computed itself.
    private static func resolveDate(from phrase: String) -> Date? {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return detector.firstMatch(in: trimmed, range: range)?.date
    }

    /// Who the whole transcript touched on, deterministically. Applied to
    /// every event from the session — there is no per-event granularity.
    private static func mentionedPeople(in transcript: String, from people: [Person]) -> [Person] {
        let normalized = QueryInterpreter.normalize(transcript)
        return people.filter { !$0.name.isEmpty && normalized.contains(QueryInterpreter.normalize($0.name)) }
    }

    // MARK: - One turn

    private func receive(_ turn: String, store: ConversationStore) {
        guard phase == .listening || phase == .opening else { return }
        guard isSomeoneSpeaking(turn) else { return }
        self.store = store

        turnsHeard += 1
        fullTranscript.append(turn)
        restartSilenceTimer(store: store)

        phase = .thinking
        listening.pause()

        Task { await respond(to: turn, store: store) }
    }

    private func respond(to turn: String, store: ConversationStore) async {
        let intent = await comprehension.interpret(turn, people: store.people)
        guard phase == .thinking else { return }

        let digest = store.groundingDigest()
        let grounded = GroundingService.answer(
            for: intent,
            digest: digest,
            people: store.people,
            lastSpoken: speech.lastSpoken
        )

        let line: String
        if intent.isVerbatim {
            // Frightened or verbatim moments never touch the phrasing model.
            line = grounded
        } else if intent.wantsCompanionship {
            // Nothing in the store answers this, so acknowledge the person
            // rather than deflecting. Every name we know is passed in to be
            // rejected: questions about people have a grounded path, so a name
            // here would be an unearned claim about who is around.
            line = await phrasing.converse(
                about: turn,
                neverMention: store.people.map(\.name) + [
                    digest.facts.currentCaregiverName,
                    digest.facts.primaryContactName,
                ],
                fallback: grounded
            )
        } else {
            line = await phrasing.warmlyRephrase(grounded)
        }
        guard phase == .thinking else { return }

        say(line, priority: intent == .distress ? .grounding : .reply)
    }

    /// Whether this transcript is actually a person talking to us.
    ///
    /// Two things arrive that are not. A near-empty result is room noise the
    /// transcriber tried to make words of. And because the loop runs without
    /// echo cancellation, audio captured while the companion was talking can
    /// be delivered just after the microphone reopens — the app hearing
    /// itself, then answering itself, with nobody having said anything.
    private func isSomeoneSpeaking(_ turn: String) -> Bool {
        let heard = QueryInterpreter.normalize(turn)
        guard heard.count >= 2, heard.contains(where: \.isLetter) else { return false }

        // Only compare longer utterances; a genuine "yes" can legitimately
        // appear inside a line we just spoke.
        guard heard.count >= 8 else { return true }
        let spoken = QueryInterpreter.normalize(speech.lastSpoken)
        guard !spoken.isEmpty else { return true }
        return !spoken.contains(heard) && !heard.contains(spoken)
    }

    private func say(_ line: String, priority: SpeechManager.Priority) {
        transcriptLine = line
        phase = .speaking
        // Half-duplex: stop taking input rather than transcribe our own voice.
        listening.pause()
        speech.speak(line, priority: priority)
    }

    /// The voice has stopped, so the microphone can reopen.
    private func handleFinishedSpeaking() {
        guard phase == .speaking else { return }
        phase = .listening
        listening.resume()
    }

    // MARK: - Timers

    /// The privacy window. Non-negotiable: the session closes itself.
    private func startExpiryTimer(store: ConversationStore) {
        expiryTask?.cancel()
        let window = sessionWindow(for: store)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard !Task.isCancelled, let self else { return }
            await self.close(store: store)
        }
    }

    /// Caregiver-configured session length, read live so a caregiver's edit
    /// takes effect on the next conversation without restarting the app.
    /// Falls back to the default only if the store was never seeded.
    private func sessionWindow(for store: ConversationStore) -> TimeInterval {
        guard let minutes = store.facts?.sessionTimeoutMinutes, minutes > 0 else {
            return settings.sessionWindow
        }
        return minutes * 60
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

/// How long a session may run, and how patient it is with silence, before it
/// closes itself for privacy.
struct SummarizationSettings: Codable, Equatable {
    /// The session auto-closes after this long, for privacy.
    var sessionWindow: TimeInterval
    /// Give up this quickly if nobody says anything at all — an accidental tap
    /// should not hold the microphone open.
    var openingSilenceTimeout: TimeInterval
    /// Auto-close once a conversation under way has gone quiet this long.
    /// Generous on purpose: finding a word can take a while.
    var silenceTimeout: TimeInterval

    static let `default` = SummarizationSettings(
        sessionWindow: Conversation.sessionWindow,
        openingSilenceTimeout: 10,
        silenceTimeout: 90
    )
}

/// The slice of the store a conversation needs, read live.
///
/// These are deliberately computed rather than arrays handed over once. A
/// session captures this value when it opens and keeps it for the whole
/// conversation, so a snapshot taken before `@Query` had loaded would stay
/// empty for the entire session — and an empty `people` means "who is David"
/// matches nobody and degrades to a shrug. Reading through the context each
/// time costs a cheap fetch and cannot go stale.
@MainActor
struct ConversationStore {
    let context: ModelContext

    var facts: GroundingFacts? {
        fetch(FetchDescriptor<GroundingFacts>()).first
    }

    // Unsorted: `when` is optional now, so `SortDescriptor` can't sort by it
    // directly. `GroundingService`/`GroundingDigest` re-sort after filtering
    // to known dates.
    var events: [Event] {
        fetch(FetchDescriptor<Event>())
    }

    var people: [Person] {
        fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    var comfortTopics: [ComfortTopic] {
        fetch(FetchDescriptor<ComfortTopic>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

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
