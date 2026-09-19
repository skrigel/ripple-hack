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
