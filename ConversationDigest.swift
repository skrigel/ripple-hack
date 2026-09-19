import Foundation

/// What a chunk of conversation was about, in slots rather than prose.
///
/// The comprehension layer fills one of these in from a handful of turns. It
/// is extraction, not writing: the model picks out topics and names, and
/// everything it returns is checked against the store before it counts.
struct ConversationBeat: Equatable {
    var topics: [String]
    var peopleNamed: [String]
    var tone: BeatTone

    init(topics: [String] = [], peopleNamed: [String] = [], tone: BeatTone = .calm) {
        self.topics = topics
        self.peopleNamed = peopleNamed
        self.tone = tone
    }
}

/// How a stretch of conversation felt.
///
/// Caregiver-facing only. Tone is the model's read on a person's state, not a
/// fact from the store, so it may inform a caregiver and must never reach a
/// spoken line or the person's own log.
enum BeatTone: String, Codable, CaseIterable {
    case warm, calm, unsettled, confused

    var isUnsettled: Bool { self == .unsettled || self == .confused }
}

/// The rolling state of a conversation, folded forward one beat at a time.
///
/// The alternative — re-summarising prose on every pass — compounds its own
/// errors, and the recap it produces ends up spoken back to the person as
/// truth. So nothing here is ever rewritten. Beats are merged by plain set
/// logic, which means a 20-minute chat and a 2-minute chat cost the same
/// memory and neither can drift.
struct ConversationDigest: Codable, Equatable {

    /// A subject that came up, with how often it did.
    struct Topic: Codable, Equatable {
        var text: String
        var mentions: Int
    }

    private(set) var topics: [Topic] = []
    private(set) var peopleIDs: Set<UUID> = []
    private(set) var beatCount = 0
    private(set) var unsettledBeats = 0

    /// More subjects than this and a recap stops being a recap. Extra topics
    /// are dropped rather than crowding out the ones already established.
    static let topicCap = 6

    init() {}

    var isEmpty: Bool { topics.isEmpty && peopleIDs.isEmpty }

    /// Whether the conversation was substantial enough to describe. Below this
    /// there is no subject to name, and the recap falls back to the plain line.
    func hasSubstance(minimumBeats: Int) -> Bool {
        beatCount >= minimumBeats && !topics.isEmpty
    }

    // MARK: - Folding

    /// Merges one beat in. Deterministic and order-stable: the same beats in
    /// the same order always give the same digest.
    mutating func fold(_ beat: ConversationBeat, known people: [Person]) {
        beatCount += 1
        if beat.tone.isUnsettled { unsettledBeats += 1 }

        // A name means nothing until the store recognises it. Unknown names
        // are dropped, never kept as loose strings.
        for name in beat.peopleNamed {
            let normalized = QueryInterpreter.normalize(name)
            guard !normalized.isEmpty else { continue }
            if let match = people.first(where: { QueryInterpreter.normalize($0.name) == normalized }) {
                peopleIDs.insert(match.id)
            }
        }

        for topic in beat.topics { mergeTopic(topic) }
    }

    /// Folds a topic in, collapsing near-duplicates so "her garden" and "the
    /// garden" become one subject mentioned twice rather than two subjects.
    private mutating func mergeTopic(_ raw: String) {
        let incoming = Self.topicKey(raw)
        guard !incoming.isEmpty else { return }

        if let index = topics.firstIndex(where: {
            let existing = Self.topicKey($0.text)
            return existing == incoming || existing.contains(incoming) || incoming.contains(existing)
        }) {
            topics[index].mentions += 1
            // Prefer the shorter wording — it reads better in a recap.
            if raw.count < topics[index].text.count { topics[index].text = raw }
            return
        }

        guard topics.count < Self.topicCap else { return }
        topics.append(Topic(text: raw, mentions: 1))
    }

    /// Normalised form used only for comparing topics: articles and possessives
    /// dropped, so they do not split one subject into several.
    private static func topicKey(_ text: String) -> String {
        let words = QueryInterpreter.normalize(text).split(separator: " ").map(String.init)
        let leaders: Set<String> = ["the", "a", "an", "her", "his", "their", "my", "our", "your"]
        return words.drop(while: { leaders.contains($0) }).joined(separator: " ")
    }

    // MARK: - Reading back

    /// The subjects worth naming, most-dwelt-on first, ties broken by which
    /// came up earliest. A recap names two or three things, never six.
    func topTopics(limit: Int = 3) -> [String] {
        topics.enumerated()
            .sorted { left, right in
                left.element.mentions == right.element.mentions
                    ? left.offset < right.offset
                    : left.element.mentions > right.element.mentions
            }
            .prefix(limit)
            .map(\.element.text)
    }

    /// People the conversation touched on, in the store's own order.
    func mentionedPeople(from people: [Person]) -> [Person] {
        people.filter { peopleIDs.contains($0.id) }
    }
}

/// Caregiver-owned controls for how conversations are captured.
///
/// Defaults are the private ones: nothing is written down unless the chat had
/// a subject, and raw turns are discarded as they are folded. No setting here
/// can affect `GroundingFacts` — those are needed at any moment and are never
/// governed by a preference.
struct SummarizationSettings: Codable, Equatable {
    /// The session auto-closes after this long, for privacy.
    var sessionWindow: TimeInterval
    /// Give up this quickly if nobody says anything at all — an accidental tap
    /// should not hold the microphone open.
    var openingSilenceTimeout: TimeInterval
    /// Auto-close once a conversation under way has gone quiet this long.
    /// Generous on purpose: finding a word can take a while.
    var silenceTimeout: TimeInterval
    /// Turns buffered before a fold is worth doing.
    var turnsPerBeat: Int
    /// Fold early once the buffer reaches roughly this many characters.
    var charactersPerBeat: Int
    /// Fewer folded beats than this and the recap stays the plain line.
    var minimumBeats: Int
    /// Whether the model may extract topics. Off means comfort-topic matching
    /// only — the app still works, it just notices less.
    var usesModelExtraction: Bool

    static let `default` = SummarizationSettings(
        sessionWindow: Conversation.sessionWindow,
        openingSilenceTimeout: 10,
        silenceTimeout: 90,
        turnsPerBeat: 6,
        charactersPerBeat: 600,
        minimumBeats: 2,
        usesModelExtraction: true
    )
}
