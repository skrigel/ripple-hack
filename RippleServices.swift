import Foundation
import Observation

/// The app's long-lived services, built once and passed around as one thing.
///
/// These were four separate environment values, which meant four chances to
/// forget one — and a forgotten `@Environment(SomeService.self)` is not a
/// warning, it is a crash the first time the view is built. Sheets are where
/// that bites, because they are built somewhere other than where they are
/// written. One container is one injection to get right.
///
/// The services know about each other in one direction only: `CompanionSession`
/// drives the voice, the ear, and the two engines. Nothing reaches back.
@Observable
@MainActor
final class RippleServices {
    let speech: SpeechManager
    let phrasing: PhrasingEngine
    let comprehension: ComprehensionEngine
    let session: CompanionSession
    let persona: PersonaSession

    init() {
        let speech = SpeechManager()
        let phrasing = PhrasingEngine()
        let comprehension = ComprehensionEngine()

        self.speech = speech
        self.phrasing = phrasing
        self.comprehension = comprehension
        self.session = CompanionSession(
            speech: speech, comprehension: comprehension, phrasing: phrasing
        )
        self.persona = PersonaSession()
    }
}
