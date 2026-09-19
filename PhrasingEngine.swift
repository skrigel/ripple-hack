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

    #if canImport(FoundationModels)
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
#endif
