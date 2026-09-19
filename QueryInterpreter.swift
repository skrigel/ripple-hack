import Foundation

/// What the person wants to know — a small, closed vocabulary.
///
/// This is the whole output of understanding a question. An intent carries at
/// most a `UUID` into the store; it never carries prose. Whatever produced it,
/// deterministic matching or the model, the answer is built afterwards by
/// `GroundingService` from records that were already true.
enum QueryIntent: Equatable {
    case whereAmI
    case whatTime
    case whatHappenedToday
    case whatsComingUp
    case whoIsHere
    case aboutPerson(UUID)
    case amISafe
    case comfortChat(UUID?)
    case repeatThat
    /// Fear or disorientation. Always answered verbatim, never by the model.
    case distress
    /// Nothing matched. Answered with a gentle, true redirect.
    case unclear

    /// The sensitive intents, which skip the phrasing engine entirely.
    var isVerbatim: Bool {
        switch self {
        case .distress, .amISafe, .repeatThat: true
        default: false
        }
    }
}

/// The deterministic first pass at understanding a question.
///
/// Pure, side-effect-free, and model-free: the same utterance always yields the
/// same intent. These patterns cover the questions people actually ask, so the
/// common path has no latency and no failure mode. Only when this returns `nil`
/// is it worth asking `ComprehensionEngine` to classify.
enum QueryInterpreter {

    /// The best matching intent, or `nil` when nothing matched confidently.
    static func match(_ utterance: String, people: [Person]) -> QueryIntent? {
        let text = normalize(utterance)
        guard !text.isEmpty else { return nil }

        // Distress is tested first: it outranks whatever else was said.
        if contains(text, Phrases.distress) { return .distress }

        if contains(text, Phrases.repeatThat) { return .repeatThat }
        if contains(text, Phrases.whereAmI) { return .whereAmI }
        if contains(text, Phrases.amISafe) { return .amISafe }
        if contains(text, Phrases.whatTime) { return .whatTime }
        if contains(text, Phrases.whatHappened) { return .whatHappenedToday }
        if contains(text, Phrases.comingUp) { return .whatsComingUp }

        // "who is david" resolves to a person; "who's here" does not.
        if contains(text, Phrases.aboutPerson), let person = resolvePerson(in: text, people: people) {
            return .aboutPerson(person.id)
        }
        if contains(text, Phrases.whoIsHere) { return .whoIsHere }

        return nil
    }

    /// Finds the person a question refers to, by name or by relationship.
    ///
    /// Deliberately strict. Naming the wrong person is far worse than admitting
    /// we did not catch who was meant, so there is no fuzzy fallback here.
    static func resolvePerson(in text: String, people: [Person]) -> Person? {
        let haystack = normalize(text)

        // Longest name first, so "mary anne" wins over "mary".
        let byName = people
            .filter { !$0.name.isEmpty && haystack.containsWord(normalize($0.name)) }
            .max { $0.name.count < $1.name.count }
        if let byName { return byName }

        return people
            .filter { !$0.relationship.isEmpty && haystack.contains(normalize($0.relationship)) }
            .max { $0.relationship.count < $1.relationship.count }
    }

    /// Matches spoken text against the comfort topics a caregiver entered.
    /// Used both for steering a conversation and for model-free beat extraction.
    static func resolveTopics(in text: String, topics: [ComfortTopic]) -> [ComfortTopic] {
        let haystack = normalize(text)
        return topics.filter { !$0.title.isEmpty && haystack.contains(normalize($0.title)) }
    }

    // MARK: - Matching

    private static func contains(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    /// Lowercased, punctuation-free, single-spaced — so "Where am I?" and
    /// "where am i" are the same question.
    ///
    /// Apostrophes are deleted rather than spaced, so "I'm" and "what's"
    /// collapse to "im" and "whats" and the phrase table needs only one form.
    static func normalize(_ text: String) -> String {
        let withoutApostrophes = text.lowercased().filter { !"'\u{2019}`".contains($0) }
        let stripped = withoutApostrophes.map { character -> Character in
            character.isLetter || character.isNumber || character.isWhitespace ? character : " "
        }
        return String(stripped)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    // MARK: - The phrase table
    //
    // Kept as data rather than a switch so the vocabulary can grow from
    // watching real speech without touching the matching logic.

    private enum Phrases {
        static let distress = [
            "im scared", "i am scared", "frightened", "help me",
            "somethings wrong", "i want to go home", "i dont know where",
            "im lost", "i am lost", "im frightened",
        ]
        static let repeatThat = [
            "say that again", "repeat that", "what did you say", "again please",
        ]
        static let whereAmI = [
            "where am i", "where is this", "whose house", "what is this place",
            "am i home", "is this my home", "what room",
        ]
        static let amISafe = [
            "am i safe", "am i okay", "am i alright", "is everything okay",
        ]
        static let whatTime = [
            "what time", "what day", "what is the date", "whats the date",
            "is it morning", "is it night",
        ]
        static let whatHappened = [
            "what happened", "what did i do", "what have i done", "whats happened",
            "how was my day", "what did i have",
        ]
        static let comingUp = [
            "coming up", "whats next", "what is next", "anyone coming",
            "anybody coming", "who is coming", "whos coming",
            "what am i doing later", "later today",
        ]
        static let aboutPerson = [
            "who is", "whos", "tell me about", "how do i know",
            "remind me who", "what about",
        ]
        static let whoIsHere = [
            "whos here", "who is here", "who is with me",
            "am i alone", "is anyone here", "whos looking after",
        ]
    }
}

private extension String {
    /// Whole-word containment, so "ann" does not match inside "anniversary".
    func containsWord(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let words = split(separator: " ").map(String.init)
        let target = word.split(separator: " ").map(String.init)
        guard !target.isEmpty, target.count <= words.count else { return false }
        for start in 0...(words.count - target.count)
        where Array(words[start..<start + target.count]) == target {
            return true
        }
        return false
    }
}
