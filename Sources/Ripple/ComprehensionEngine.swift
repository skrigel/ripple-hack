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

    // MARK: - Understanding a finished conversation

    /// Pulls candidate events out of a whole session's transcript in one
    /// pass, rather than piecing them together turn by turn — a full
    /// transcript keeps context (a plan mentioned early, dated later) that
    /// chunked extraction would lose. Returns an empty array off-device or on
    /// any failure; there is nothing to fall back to, which is fine — a
    /// session with no model available simply adds no events, same as one
    /// where nothing worth remembering was said.
    ///
    /// `knownContext` is `GroundingDigest.promptContext` — what a caregiver
    /// has already put on record. Telling the model this before it reads the
    /// transcript is the first hallucination guardrail: it is asked not to
    /// repeat or contradict what is already known, rather than being left to
    /// invent independently. The second guardrail is deterministic and lives
    /// in `CompanionSession.makeEvent` — this prompt is a nudge, not a proof.
    func extractEvents(transcript: String, people: [Person], knownContext: String) async -> [CandidateEvent] {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), capability == .onDevice else { return [] }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        do {
            let session = LanguageModelSession(instructions: Self.eventExtractionInstructions)
            let roster = people.map(\.name).joined(separator: ", ")
            let result = try await session.respond(
                to: """
                Already known and confirmed by a caregiver — do not repeat these as new \
                events, and do not say anything that contradicts them:
                \(knownContext.isEmpty ? "(nothing recorded yet)" : knownContext)

                People in their life: \(roster.isEmpty ? "(none recorded)" : roster)
                Transcript of a conversation:
                \(trimmed)
                """,
                generating: GenerableTranscriptEvents.self
            )
            return result.content.events.map(Self.portable)
        } catch {
            return []
        }
        #else
        return []
        #endif
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
        case .sharingAFeeling: return .feeling
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

    /// Strips a `@Generable` candidate down to the plain, always-available
    /// type `CompanionSession` actually consumes — the wire type is not safe
    /// to hand a caller that has no availability guard of its own.
    @available(iOS 26, *)
    private static func portable(_ generable: GenerableCandidateEvent) -> CandidateEvent {
        CandidateEvent(
            title: generable.title,
            timing: generable.timing == .past ? .past : .upcoming,
            statedWhen: generable.statedWhen,
            mentionedPeople: generable.mentionedPeople
        )
    }

    private static let routingInstructions = """
    You sort what an older person said into fixed categories. You never answer \
    them and never write a sentence for them to read.

    First decide whether they are asking for information at all. If they are \
    telling you how they feel — sad, lonely, tired, missing someone, or that \
    the day is hard — choose sharingAFeeling. Do this even when they mention a \
    person or a time, because they are not asking about that person or that \
    time. Never route a feeling to a category that would answer it with a fact; \
    being told who is visiting when you have said you are sad is worse than \
    being told nothing.

    Otherwise choose the single closest category. If it does not clearly fit \
    one, choose unclear — that is a good answer, not a failure. When they ask \
    about a particular person, copy that person's name exactly from the list \
    you are given, and leave the name empty if it is not on that list.
    """

    private static let eventExtractionInstructions = """
    You read a transcript of a conversation with an older person and pull out \
    distinct events worth remembering later: things that already happened, \
    plans, visits, or news. You are given what a caregiver has already \
    confirmed — never repeat one of those as if it were new, and never say \
    anything that disagrees with it. Skip greetings and small talk — if \
    nothing in the conversation is worth remembering, return no events. For \
    each one, write a short plain-language title in the third person, say \
    whether it already happened or is still to come, copy any specific day or \
    time that was stated exactly as said (leave it blank if none was given, \
    and never invent one), and list which people from the given list, if any, \
    it involves.
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
    /// Saying how they feel rather than asking anything. Without this case
    /// every option is a question, so the classifier has to force a feeling
    /// into one and the person gets a fact they did not ask for.
    case sharingAFeeling
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

/// Whether a candidate event was described as something that already
/// happened, or a plan for later. Never a date — see `GenerableCandidateEvent`.
@available(iOS 26, *)
@Generable
enum GenerableEventTiming {
    case past
    case upcoming
}

/// One event pulled from a transcript. `statedWhen` is a verbatim quote, not
/// a judgement — a caller resolves it into a real date deterministically, or
/// discards the candidate, rather than trusting the model's own date math.
///
/// This wire type is `@available(iOS 26, *)`, like every `@Generable` type,
/// so it is never handed to a caller directly — `ComprehensionEngine.portable`
/// converts it to the always-available `CandidateEvent` before it leaves
/// this file.
@available(iOS 26, *)
@Generable
struct GenerableCandidateEvent {
    @Guide(description: "A short, plain-language title, third person, e.g. \"Maya visited and brought photographs\"")
    var title: String

    @Guide(description: "Whether this was described as something that already happened, or a plan for later")
    var timing: GenerableEventTiming

    @Guide(description: "Only if a specific day or time was stated explicitly (e.g. \"Thursday at 3\", \"tomorrow morning\") — copy the phrase as said. Leave empty if no specific time was mentioned.")
    var statedWhen: String
}

/// The whole output for one session's transcript.
@available(iOS 26, *)
@Generable
struct GenerableTranscriptEvents {
    @Guide(description: "Every distinct event, plan, or piece of news mentioned in this conversation that's worth remembering later — omit greetings and small talk entirely")
    var events: [GenerableCandidateEvent]
}
#endif

// MARK: - Portable output
//
// `extractEvents` cannot return a `@Generable` type directly: those are all
// `@available(iOS 26, *)`, and a caller built for this app's iOS 17 minimum
// has no availability guard of its own to receive one. These plain mirrors
// are always available, at the cost of the small bridging step in `portable`.

/// Whether a candidate event was described as something that already
/// happened, or a plan for later. Never a date — see `CandidateEvent`.
enum EventTiming {
    case past
    case upcoming
}

/// One event pulled from a transcript, safe for any caller to hold.
struct CandidateEvent {
    var title: String
    var timing: EventTiming
    var statedWhen: String
}
