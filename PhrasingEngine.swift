import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The "how to say it" layer — the *only* place a language model lives.
///
/// Deterministic code (see `GroundingService`) has already decided what is true.
/// This engine merely warms the tone of a known fact. It follows the build
/// plan's template-first gradient and degrades gracefully to templates-only on
/// devices without Apple Intelligence, so the app always fully works.
@Observable
@MainActor
final class PhrasingEngine {

    enum Capability {
        case onDevice      // Foundation Models available — may warm the tone
        case templatesOnly // sensitive/verbatim path; the app is fully usable
    }

    let capability: Capability

    init() {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), case .available = SystemLanguageModel.default.availability {
            capability = .onDevice
        } else {
            capability = .templatesOnly
        }
        #else
        capability = .templatesOnly
        #endif
    }

    /// Warm the tone of an already-true grounding line. Never invents facts:
    /// the source line is passed in, and on any failure we return it unchanged.
    func warmlyRephrase(_ groundedLine: String) async -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), capability == .onDevice else { return groundedLine }
        do {
            let session = LanguageModelSession(instructions: Self.toneInstructions)
            let result = try await session.respond(
                to: "Rephrase this warmly for an older person, keeping every fact "
                    + "exactly the same and staying to one or two short sentences:\n\(groundedLine)",
                generating: SpokenLine.self
            )
            let speech = result.content.speech.trimmingCharacters(in: .whitespacesAndNewlines)
            return speech.isEmpty ? groundedLine : speech
        } catch {
            // Graceful degradation — the deterministic line is always safe to speak.
            return groundedLine
        }
        #else
        return groundedLine
        #endif
    }

    /// Acknowledges what was said, then offers to tell them something.
    ///
    /// Reached only when nothing in the store answers the question. Everything
    /// else this engine says has a true sentence behind it; this does not, so
    /// it is not allowed to say anything *about* them. It gets the words they
    /// spoke and nothing else — no name, no place, no one on duty — because
    /// context it cannot verify is context it will assert. Given "who is
    /// looking after me" it once replied that someone was here who was not.
    ///
    /// The shape is fixed rather than requested: acknowledge the feeling, then
    /// ask. Neither half has room for a claim. Anything that fails `vetted`
    /// becomes `fallback`, which is true.
    func converse(
        about utterance: String,
        neverMention forbiddenNames: [String],
        fallback: String
    ) async -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), capability == .onDevice else { return fallback }
        let asked = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty else { return fallback }

        do {
            let session = LanguageModelSession(instructions: Self.conversationInstructions)
            let result = try await session.respond(
                to: "They just said: \"\(asked)\"",
                generating: EmpatheticReply.self
            )
            let reply = result.content
            let spoken = [reply.acknowledgement, reply.offer]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return Self.vetted(spoken, forbiddenNames: forbiddenNames) ?? fallback
        } catch {
            return fallback
        }
        #else
        return fallback
        #endif
    }

    /// Rejects a free-form reply that strays outside what it is allowed to say.
    ///
    /// A name is the sharpest failure: naming someone implies something about
    /// where they are or what they did, and this reply knows neither. Questions
    /// about people have a grounded path of their own, so a name appearing here
    /// is always unearned.
    ///
    /// Digits are the other tell — there is no clock or calendar behind this
    /// reply, so a number in it was invented. Length is the third: a long
    /// answer has started explaining something it cannot know.
    static func vetted(_ raw: String, forbiddenNames: [String] = []) -> String? {
        let speech = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !speech.isEmpty, speech.count <= 240 else { return nil }
        guard !speech.contains(where: \.isNumber) else { return nil }

        let words = Set(QueryInterpreter.normalize(speech).split(separator: " ").map(String.init))
        for name in forbiddenNames {
            let parts = QueryInterpreter.normalize(name).split(separator: " ").map(String.init)
            guard !parts.isEmpty else { continue }
            if parts.contains(where: words.contains) { return nil }
        }
        return speech
    }

    #if canImport(FoundationModels)
    private static let conversationInstructions = """
    You are a calm, warm companion speaking aloud to an older person who may be \
    confused. They have said something you have no information about.

    You know nothing whatsoever about this person, where they are, who is with \
    them, or what has happened to them. Do not name anyone. Do not say that \
    anybody is here, is coming, has visited, or will help. Do not mention the \
    time, a meal, a plan, or their health. You would be guessing, and they \
    would believe you.

    Do exactly two things. First, acknowledge how they seem to feel, in one \
    short, kind sentence. Then ask one short question offering to tell them \
    something or to talk with them. Never correct them and never argue.
    """

    private static let toneInstructions = """
    You are a calm, warm companion for an older person who may be confused. \
    Speak gently and briefly. Never add facts, times, names, or events that are \
    not already in the text you are given. Never correct or argue. Keep it to one \
    or two short spoken sentences.
    """
    #endif
}

#if canImport(FoundationModels)
/// Structured output whose payload is a spoken sentence — constrained decoding
/// guarantees a clean, well-formed result to feed the synthesizer and the label.
@available(iOS 26, *)
@Generable
struct SpokenLine {
    @Guide(description: "One or two warm, short sentences to speak aloud")
    var speech: String
}

/// The reply given when nothing is known: feeling, then offer.
///
/// Split into two fields so the shape is structural rather than requested.
/// There is nowhere in here to put a claim about the person's life.
@available(iOS 26, *)
@Generable
struct EmpatheticReply {
    @Guide(description: "One short, kind sentence acknowledging how they seem to feel. No names, no facts, no times.")
    var acknowledgement: String

    @Guide(description: "One short question offering to tell them something or talk with them. No names, no facts, no times.")
    var offer: String
}
#endif
