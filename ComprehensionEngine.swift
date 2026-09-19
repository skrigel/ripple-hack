import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The "what did they mean" layer — the model pointed inward.
///
/// There are two engines that may hold a model, split by direction.
/// `PhrasingEngine` faces outward and decides *how to say* something already
/// known to be true. This one faces inward and decides *what was meant* and
/// *what was talked about*.
///
/// The safety property is different here, and stricter. Nothing this engine
/// returns is ever spoken or stored. Its outputs are a routing decision (an
/// intent) and lookup keys (a name, a topic), and a key means nothing until it
/// matches a record in the store. A hallucinated name resolves to no one and
/// the question degrades to `.unclear`; a hallucinated topic is dropped on the
/// floor. On any failure the app falls back to deterministic behaviour.
@Observable
@MainActor
final class ComprehensionEngine {

    enum Capability {
        case onDevice      // Foundation Models available — may classify and extract
        case deterministic // pattern matching only; the app is fully usable
    }

    let capability: Capability

    init() {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), case .available = SystemLanguageModel.default.availability {
            capability = .onDevice
        } else {
            capability = .deterministic
        }
        #else
        capability = .deterministic
        #endif
    }

    // MARK: - Understanding a question

    /// Works out what was asked.
    ///
    /// Tries the deterministic matcher first — it covers the questions people
    /// actually ask, with no latency and no failure mode — and only falls to
    /// the model for phrasings the table has not seen.
    func interpret(_ utterance: String, people: [Person]) async -> QueryIntent {
        if let matched = QueryInterpreter.match(utterance, people: people) {
            return matched
        }
        return await classify(utterance, people: people)
    }

    /// The model as a router: it picks a case, never composes an answer.
    private func classify(_ utterance: String, people: [Person]) async -> QueryIntent {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), capability == .onDevice else { return .unclear }
        do {
            let session = LanguageModelSession(instructions: Self.routingInstructions)
            let roster = people.map(\.name).joined(separator: ", ")
            let result = try await session.respond(
                to: """
                People in their life: \(roster.isEmpty ? "(none recorded)" : roster)
                They said: "\(utterance)"
                Which kind of question is this?
                """,
                generating: ClassifiedQuery.self
            )
            return resolve(result.content, people: people)
        } catch {
            return .unclear
        }
        #else
        return .unclear
        #endif
    }

    // MARK: - Understanding a conversation

    /// Extracts one beat from a handful of turns, for folding into the digest.
    ///
    /// Returns `nil` when there was nothing worth recording. The deterministic
    /// pass alone — matching against the comfort topics a caregiver entered —
    /// is often enough, and it is all that happens when there is no model.
    func extractBeat(
        from turns: [String],
        people: [Person],
        topics: [ComfortTopic],
        usesModel: Bool
    ) async -> ConversationBeat? {
        guard !turns.isEmpty else { return nil }
        let text = turns.joined(separator: " ")

        // Topics the caregiver already told us this person lights up about.
        let known = QueryInterpreter.resolveTopics(in: text, topics: topics).map(\.title)
        let named = people.filter { QueryInterpreter.normalize(text).contains(QueryInterpreter.normalize($0.name)) }

        guard usesModel, capability == .onDevice else {
            guard !known.isEmpty || !named.isEmpty else { return nil }
            return ConversationBeat(topics: known, peopleNamed: named.map(\.name))
        }

        let extracted = await modelBeat(text: text, people: people)
        guard let extracted else {
            guard !known.isEmpty || !named.isEmpty else { return nil }
            return ConversationBeat(topics: known, peopleNamed: named.map(\.name))
        }

        // The deterministic finds are trusted outright; the model's are extra.
        return ConversationBeat(
            topics: known + extracted.topics,
            peopleNamed: Set(named.map(\.name) + extracted.peopleNamed).sorted(),
            tone: extracted.tone
        )
    }

    // MARK: - Summarizing a finished transcript

    /// Summarizes a whole session's transcript and judges whether it is
    /// significant enough to remember — the gate before anything is written
    /// to the event log. Returns `nil` off-device or on any failure, so the
    /// caller always has a deterministic fallback to reach for.
    func summarizeSignificance(transcript: String, people: [Person]) async -> TranscriptSummary? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), capability == .onDevice else { return nil }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let session = LanguageModelSession(instructions: Self.summaryInstructions)
            let roster = people.map(\.name).joined(separator: ", ")
            let result = try await session.respond(
                to: """
                People in their life: \(roster.isEmpty ? "(none recorded)" : roster)
                Transcript of a conversation:
                \(trimmed)
                """,
                generating: TranscriptSummary.self
            )
            return result.content
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    private func modelBeat(text: String, people: [Person]) async -> ConversationBeat? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else { return nil }
        do {
            let session = LanguageModelSession(instructions: Self.extractionInstructions)
            let roster = people.map(\.name).joined(separator: ", ")
            // Non-streaming on purpose: folds run in the background between
            // turns, where streaming is more likely to be rate limited.
            let result = try await session.respond(
                to: """
                People in their life: \(roster.isEmpty ? "(none recorded)" : roster)
                Part of a conversation:
                \(text)
                """,
                generating: ExtractedBeat.self
            )
            return ConversationBeat(
                topics: result.content.topics.compactMap(Self.cleanTopic),
                peopleNamed: result.content.peopleMentioned,
                tone: BeatTone(rawValue: result.content.tone.rawValue) ?? .calm
            )
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Topics are labels, not sentences. Anything long enough to be a claim is
    /// discarded rather than trimmed — it would be a statement about the
    /// person's life that no record backs up.
    private static func cleanTopic(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ")
        guard !trimmed.isEmpty, words.count <= 4, trimmed.count <= 40 else { return nil }
        return trimmed
    }

    // MARK: - Turning model output into store references

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private func resolve(_ classified: ClassifiedQuery, people: [Person]) -> QueryIntent {
        switch classified.intent {
        case .whereAmI: return .whereAmI
        case .whatTime: return .whatTime
        case .whatHappenedToday: return .whatHappenedToday
        case .whatsComingUp: return .whatsComingUp
        case .whoIsHere: return .whoIsHere
        case .amISafe: return .amISafe
        case .justTalking: return .comfortChat(nil)
        case .unclear: return .unclear
        case .aboutSomeone:
            // The name only earns meaning by matching the store.
            let target = QueryInterpreter.normalize(classified.personName)
            guard !target.isEmpty,
                  let person = people.first(where: { QueryInterpreter.normalize($0.name) == target })
            else { return .unclear }
            return .aboutPerson(person.id)
        }
    }

    private static let routingInstructions = """
    You sort questions from an older person into fixed categories. You never \
    answer the question and never write a sentence for them to read. Choose the \
    single closest category. If the question does not clearly fit one, choose \
    unclear — that is a good answer, not a failure. When the question is about \
    a particular person, copy their name exactly from the list you are given, \
    and leave the name empty if it is not on that list.
    """

    private static let extractionInstructions = """
    You note what a conversation was about. You never write a summary sentence, \
    never quote, and never record anything personal, medical, or sensitive. \
    List only short subject labels of one to three words, such as "the garden" \
    or "her trip". If a stretch of talk had no clear subject, return no topics. \
    Only list names that appear in the list you are given. Judge tone from how \
    the person sounds: warm, calm, unsettled, or confused.
    """

    private static let summaryInstructions = """
    You summarize a conversation with an older person, for their caregiver. \
    Write one or two short, plain sentences describing what was talked about, \
    in the third person. Mark it significant only if it contains a specific \
    event, plan, visit, or piece of news worth remembering later — ordinary \
    greetings, small talk, or chat with no clear subject is not significant.
    """
    #endif
}

// MARK: - Constrained model output
//
// Constrained decoding guarantees the shape of what comes back: a case of a
// known enum, and strings that are treated as lookup keys, never as content.

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
enum GenerableIntent {
    case whereAmI
    case whatTime
    case whatHappenedToday
    case whatsComingUp
    case whoIsHere
    case aboutSomeone
    case amISafe
    case justTalking
    case unclear
}

@available(iOS 26, *)
@Generable
struct ClassifiedQuery {
    @Guide(description: "The single closest matching kind of question")
    var intent: GenerableIntent

    @Guide(description: "If the question is about one person, their name copied exactly from the list provided. Otherwise empty.")
    var personName: String
}

@available(iOS 26, *)
@Generable
enum GenerableTone {
    case warm, calm, unsettled, confused
}

@available(iOS 26, *)
@Generable
struct ExtractedBeat {
    @Guide(description: "Up to three short subject labels, one to three words each, such as \"the garden\"")
    var topics: [String]

    @Guide(description: "Names of people talked about, copied exactly from the list provided")
    var peopleMentioned: [String]

    @Guide(description: "How this part of the conversation sounded")
    var tone: GenerableTone
}

@available(iOS 26, *)
extension GenerableTone {
    var rawValue: String {
        switch self {
        case .warm: "warm"
        case .calm: "calm"
        case .unsettled: "unsettled"
        case .confused: "confused"
        }
    }
}

/// A finished transcript, reduced to the two things the event log needs: a
/// plain sentence, and whether it clears the bar to be remembered at all.
@available(iOS 26, *)
@Generable
struct TranscriptSummary {
    @Guide(description: "One or two short, plain sentences summarizing what was talked about, in the third person")
    var summary: String

    @Guide(description: "True only if this contains a specific event, plan, visit, or piece of news worth remembering later")
    var isSignificant: Bool
}
#endif
