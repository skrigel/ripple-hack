import Foundation

/// Deterministic, side-effect-free phrasing of *what is true right now*.
///
/// This is the "what's true" layer from the build plan: plain Swift decides the
/// facts; the model (if present) only warms the tone afterward. The most
/// sensitive lines are produced here, verbatim, and never touch a model.
enum GroundingService {

    // MARK: Header

    /// "Tuesday, July 8"
    static func headerDate(at date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    /// "Good afternoon, Margaret"
    static func greeting(for name: String, at date: Date, calendar: Calendar = .current) -> String {
        "Good \(partOfDay(at: date, calendar: calendar)), \(name)"
    }

    // MARK: "Right now" card

    /// A short clock string, e.g. "2:14".
    static func clock(at date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }

    /// "Tuesday afternoon"
    static func weekdayAndPartOfDay(at date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEE"
        return "\(formatter.string(from: date)) \(partOfDay(at: date, calendar: calendar))"
    }

    /// The warm summary line: what just happened and what's coming, or nothing.
    /// Both halves come from the event log — never from the model.
    static func presentSummary(
        recent: Event?,
        upcoming: Event?,
        at date: Date,
        calendar: Calendar = .current
    ) -> String {
        let pieces = [
            recent.map { "\(sentenceCased($0.title)) \(relativePast(from: $0.when, to: date))." },
            upcoming.map { "\($0.title) at \(timeOfDay($0.when, calendar: calendar)) — \(relativeFuture(from: date, to: $0.when))." },
        ].compactMap { $0 }

        return pieces.isEmpty ? "Nothing is needed right now. You are safe and settled." : pieces.joined(separator: " ")
    }

    // MARK: List intros

    static let todayIntro = "Here is your day."
    static let recentIntro = "Here is what has happened over the past few days."

    // MARK: Retrieval
    //
    // An upcoming event is not a different kind of record — it is just an
    // `Event` whose `when` has not arrived yet. These are the only places that
    // distinction is drawn, and all of them are plain date comparisons.

    /// Everything on a given day, soonest first. Includes later-today events.
    static func events(_ events: [Event], on day: Date, calendar: Calendar = .current) -> [Event] {
        events
            .filter { calendar.isDate($0.when, inSameDayAs: day) }
            .sorted { $0.when < $1.when }
    }

    /// What has already happened, most recent first. Not shown on Home, but
    /// kept so the app can answer "what happened last week".
    static func past(_ events: [Event], before date: Date, limit: Int = .max) -> [Event] {
        events
            .filter { $0.when < date }
            .sorted { $0.when > $1.when }
            .prefix(limit)
            .map { $0 }
    }

    /// How many days back the Past tab reaches. The store keeps more than this
    /// — the window is a kindness on screen, not a limit on what the app knows.
    /// A wall of months would read as a ledger to answer to.
    static let recentWindowDays = 7

    /// Days before today, within the recent window, most recent first.
    static func recent(
        _ events: [Event],
        before date: Date,
        within days: Int = recentWindowDays,
        calendar: Calendar = .current
    ) -> [Event] {
        let startOfToday = calendar.startOfDay(for: date)
        let earlier = past(events, before: startOfToday)
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: startOfToday) else {
            return earlier
        }
        return earlier.filter { $0.when >= cutoff }
    }

    /// What is still to come, soonest first.
    static func upcoming(_ events: [Event], after date: Date, limit: Int = .max) -> [Event] {
        events
            .filter { $0.when > date }
            .sorted { $0.when < $1.when }
            .prefix(limit)
            .map { $0 }
    }

    /// The day's single timeline, merging the event log with any conversation
    /// that is still running.
    ///
    /// A *finished* conversation is deliberately excluded: on close it writes
    /// its recap into the event log as an `Event`, so including it here too
    /// would show the same chat twice.
    static func timeline(
        events: [Event],
        conversations: [Conversation],
        on day: Date,
        calendar: Calendar = .current
    ) -> [TimelineEntry] {
        let dayEvents = self.events(events, on: day, calendar: calendar).map(TimelineEntry.event)
        let ongoing = conversations
            .filter { $0.isOngoing && calendar.isDate($0.startedAt, inSameDayAs: day) }
            .map(TimelineEntry.conversation)
        return (dayEvents + ongoing).sorted { $0.when < $1.when }
    }

    // MARK: The spoken grounding line (Home, on open)

    /// The instant, precomputed present-orientation line spoken on open.
    /// Verbatim — no model call, no spinner.
    static func spokenGrounding(facts: GroundingFacts, at date: Date, calendar: Calendar = .current) -> String {
        "It's \(partOfDay(at: date, calendar: calendar)), about \(timeOfDay(date, calendar: calendar)). "
        + "You are at \(facts.homeLabel), \(facts.userName), and everything is okay."
    }

    /// The same line, extended with the most recent thing that happened — the
    /// "where am I, what's happened" answer in one breath.
    static func spokenGrounding(
        facts: GroundingFacts,
        recent: Event?,
        at date: Date,
        calendar: Calendar = .current
    ) -> String {
        let base = spokenGrounding(facts: facts, at: date, calendar: calendar)
        guard let recent else { return base }
        return base + " \(sentenceCased(recent.title)) \(relativePast(from: recent.when, to: date))."
    }

    // MARK: Conversations

    /// How a finished session reads back in the log. Ongoing sessions are
    /// described as still happening rather than summarised.
    static func conversationLine(_ conversation: Conversation, at date: Date = .now) -> String {
        if conversation.isOngoing {
            let names = conversation.participants.map(\.name)
            return names.isEmpty ? "You're talking with me now." : "You're talking with \(list(names)) now."
        }
        return conversation.summary.isEmpty
            ? "You had a conversation \(relativePast(from: conversation.startedAt, to: date))."
            : conversation.summary
    }

    // MARK: Spoken answers
    //
    // One function per intent. Every sentence below is assembled from records
    // that were already true — the interpreter only chose which one to build.

    /// The true answer to a understood question.
    ///
    /// `lastSpoken` is passed in rather than read from the voice so this stays
    /// pure: the same inputs always produce the same sentence.
    static func answer(
        for intent: QueryIntent,
        digest: GroundingDigest,
        people: [Person],
        lastSpoken: String = "",
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let facts = digest.facts
        switch intent {
        case .whereAmI:
            return "You're at \(facts.homeLabel), \(facts.userName) — in \(facts.roomLabel). "
                + "It's \(weekdayAndPartOfDay(at: date, calendar: calendar))."

        case .whatTime:
            let base = "It's \(timeOfDay(date, calendar: calendar)), on a \(weekdayAndPartOfDay(at: date, calendar: calendar))."
            guard let next = digest.upcoming.first else { return base }
            return base + " \(sentenceCased(next.title)) is at \(timeOfDay(next.when, calendar: calendar))."

        case .whatHappenedToday:
            return happenedToday(digest, at: date, calendar: calendar)

        case .whatsComingUp:
            return comingUp(digest, at: date, calendar: calendar)

        case .whoIsHere:
            return whoIsHere(facts: facts, people: people)

        case .aboutPerson(let id):
            guard let person = people.first(where: { $0.id == id }) else {
                return unsure(digest, facts: facts)
            }
            return about(person)

        case .amISafe:
            return "You are safe, \(facts.userName). You're at \(facts.homeLabel), "
                + "\(facts.roomLabel). Everything is okay."

        case .comfortChat(let id):
            let topic = id.flatMap { identifier in digest.comfortTopics.first { $0.id == identifier } }
                ?? digest.comfortTopics.first
            guard let topic else {
                return "I'd love to hear about your day, \(facts.userName). What's on your mind?"
            }
            return "Tell me about \(lowercasedFirst(topic.title)), \(facts.userName). I'd love to hear about it."

        case .repeatThat:
            return lastSpoken.isEmpty
                ? "I hadn't said anything yet, \(facts.userName). You're at \(facts.homeLabel), and all is well."
                : lastSpoken

        case .distress:
            return reassurance(facts: facts)

        case .unclear:
            return unsure(digest, facts: facts)
        }
    }

    /// How a conversation opens. Short on purpose: the person pressed the
    /// button because they have something to ask, so this gets out of the way.
    static func conversationOpener(facts: GroundingFacts) -> String {
        "I'm listening, \(facts.userName)."
    }

    /// The verbatim line for a frightened moment. Facts and a person to call —
    /// nothing else, and never near a model.
    static func reassurance(facts: GroundingFacts) -> String {
        "You are safe, \(facts.userName). You're at \(facts.homeLabel), and I'm right here with you. "
            + "\(facts.currentCaregiverName) is \(lowercasedFirst(facts.currentCaregiverRelationship)), "
            + "and \(facts.primaryContactName) is just a phone call away."
    }

    /// Who this person is to them, in the caregiver's own words.
    static func about(_ person: Person) -> String {
        var line = "\(person.name) is \(lowercasedFirst(person.relationship))."
        if !person.recentContext.isEmpty { line += " \(sentenceCased(person.recentContext))." }
        if let memory = person.memories.first { line += " You two share \(lowercasedFirst(memory))." }
        return line
    }

    /// When we did not catch the question. True, calm, and hands back a thread
    /// worth pulling rather than admitting failure.
    static func unsure(_ digest: GroundingDigest, facts: GroundingFacts) -> String {
        let base = "I'm not quite sure about that one, \(facts.userName) — but you're safe here at \(facts.homeLabel)."
        guard let topic = digest.comfortTopics.first else { return base }
        return base + " Shall we talk about \(lowercasedFirst(topic.title))?"
    }

    private static func happenedToday(
        _ digest: GroundingDigest, at date: Date, calendar: Calendar
    ) -> String {
        let done = digest.today.filter { $0.hasHappened(by: date) }
        guard !done.isEmpty else {
            return "You're just getting started today, \(digest.facts.userName). It's been a quiet morning."
        }
        let phrases = done.map { "\(lowercasedFirst($0.title)) at \(timeOfDay($0.when, calendar: calendar))" }
        return "You've had a good day so far. " + sentenceCased(list(phrases)) + "."
    }

    private static func comingUp(
        _ digest: GroundingDigest, at date: Date, calendar: Calendar
    ) -> String {
        let next = Array(digest.upcoming.prefix(3))
        guard !next.isEmpty else { return "Nothing else is planned. You can rest easy." }
        let phrases = next.map {
            "\(lowercasedFirst($0.title)) \(dayPhrase(for: $0.when, at: date, calendar: calendar))"
        }
        return "Coming up, you have " + list(phrases) + "."
    }

    private static func whoIsHere(facts: GroundingFacts, people: [Person]) -> String {
        let visiting = people.filter(\.isVisitingToday)
        var pieces = ["\(facts.currentCaregiverName) is \(lowercasedFirst(facts.currentCaregiverRelationship))."]
        if !visiting.isEmpty {
            let names = visiting.map { "\($0.name), \(lowercasedFirst($0.relationship))" }
            pieces.append("\(sentenceCased(list(names))) \(visiting.count == 1 ? "is" : "are") visiting today.")
        }
        pieces.append("If you need anyone else, \(facts.primaryContactName) is just a phone call away.")
        return pieces.joined(separator: " ")
    }

    /// "at 3:00 pm" today, "on Friday at 2:00 pm" beyond it.
    static func dayPhrase(for target: Date, at date: Date = .now, calendar: Calendar = .current) -> String {
        let time = "at \(timeOfDay(target, calendar: calendar))"
        guard !calendar.isDate(target, inSameDayAs: date) else { return time }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEE"
        return "on \(formatter.string(from: target)) \(time)"
    }

    // MARK: Shared formatting

    static func timeOfDay(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "h:mm a"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter.string(from: date).lowercased()
    }

    static func partOfDay(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "morning"
        case 12..<17: "afternoon"
        case 17..<21: "evening"
        default: "nighttime"
        }
    }

    /// Join phrases with commas and a trailing "and", e.g. "a, b and c".
    static func list(_ phrases: [String]) -> String {
        guard let last = phrases.last else { return "" }
        guard phrases.count > 1 else { return last }
        return phrases.dropLast().joined(separator: ", ") + " and " + last
    }

    // MARK: - Private helpers

    private static func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// For dropping a stored phrase mid-sentence: "Your son" → "your son".
    private static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func relativePast(from earlier: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(earlier) / 60))
        switch minutes {
        case 0..<45: return "about \(max(5, minutes)) minutes ago"
        case 45..<90: return "about an hour ago"
        default: return "about \(Int((Double(minutes) / 60).rounded())) hours ago"
        }
    }

    private static func relativeFuture(from now: Date, to later: Date) -> String {
        let minutes = max(0, Int(later.timeIntervalSince(now) / 60))
        switch minutes {
        case 0..<10: return "very soon"
        case 10..<75: return "just under an hour away"
        default: return "in a few hours"
        }
    }
}

// MARK: - Timeline

/// One line in a day's timeline: a logged event, or a conversation that is
/// still running. Finished conversations arrive here as their recap `Event`.
enum TimelineEntry: Identifiable {
    case event(Event)
    case conversation(Conversation)

    var id: UUID {
        switch self {
        case .event(let event): event.id
        case .conversation(let conversation): conversation.id
        }
    }

    var when: Date {
        switch self {
        case .event(let event): event.when
        case .conversation(let conversation): conversation.startedAt
        }
    }

    /// An ongoing conversation is always "now", never pending.
    func hasHappened(by date: Date = .now) -> Bool {
        switch self {
        case .event(let event): event.hasHappened(by: date)
        case .conversation: true
        }
    }
}

// MARK: - What the model is allowed to know

/// The grounded context handed to the phrasing layer.
///
/// Home only ever *shows* today, but the app keeps a wider window than it
/// displays so the model can answer "when did I last see David" or "is anyone
/// coming this week". Everything in here came from the store — the model may
/// draw on it, and may not go beyond it.
struct GroundingDigest {
    let facts: GroundingFacts
    /// Before today, most recent first.
    let recentPast: [Event]
    /// Everything dated today, whether or not it has happened yet.
    let today: [Event]
    /// After now, soonest first — including later today.
    let upcoming: [Event]
    let comfortTopics: [ComfortTopic]

    init(
        facts: GroundingFacts,
        events: [Event],
        comfortTopics: [ComfortTopic] = [],
        at date: Date = .now,
        pastLimit: Int = 20,
        upcomingLimit: Int = 10,
        calendar: Calendar = .current
    ) {
        let startOfToday = calendar.startOfDay(for: date)
        self.facts = facts
        self.recentPast = GroundingService.past(events, before: startOfToday, limit: pastLimit)
        self.today = GroundingService.events(events, on: date, calendar: calendar)
        self.upcoming = GroundingService.upcoming(events, after: date, limit: upcomingLimit)
        self.comfortTopics = comfortTopics
    }

    /// A compact, plain-text rendering for the model's context window. Facts
    /// only — no instructions, no inference, nothing the store did not supply.
    func promptContext(at date: Date = .now, calendar: Calendar = .current) -> String {
        var lines = [
            "Person: \(facts.userName)",
            "Place: \(facts.homeLabel), \(facts.roomLabel)",
            "On duty now: \(facts.currentCaregiverName) (\(facts.currentCaregiverRelationship))",
            "Who to call: \(facts.primaryContactName) (\(facts.primaryContactRelationship))",
            "Now: \(GroundingService.weekdayAndPartOfDay(at: date, calendar: calendar)), "
                + GroundingService.timeOfDay(date, calendar: calendar),
        ]

        lines.append(contentsOf: section("Today", today.map { describe($0, calendar: calendar) }))
        lines.append(contentsOf: section("Coming up", upcoming.map { describe($0, calendar: calendar) }))
        lines.append(contentsOf: section("Earlier", recentPast.map { describe($0, calendar: calendar) }))
        lines.append(contentsOf: section("Likes talking about", comfortTopics.map(\.title)))

        return lines.joined(separator: "\n")
    }

    private func section(_ title: String, _ items: [String]) -> [String] {
        items.isEmpty ? [] : ["\(title):"] + items.map { "- \($0)" }
    }

    private func describe(_ event: Event, calendar: Calendar) -> String {
        let time = GroundingService.timeOfDay(event.when, calendar: calendar)
        let who = event.participants.map(\.name)
        let suffix = who.isEmpty ? "" : " (with \(GroundingService.list(who)))"
        return "\(time) — \(event.title)\(suffix)"
    }
}
