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
    static func presentSummary(
        recentDone: LogEntry?,
        nextUp: AgendaEvent?,
        at date: Date,
        calendar: Calendar = .current
    ) -> String {
        let pieces = [
            recentDone.map { "You \(lowercasedLabel($0.label)) \(relativePast(from: $0.timestamp, to: date))." },
            nextUp.map { "\($0.title) at \(timeOfDay($0.time, calendar: calendar)) — \(relativeFuture(from: date, to: $0.time))." },
        ].compactMap { $0 }

        return pieces.isEmpty ? "Nothing is needed right now. You are safe and settled." : pieces.joined(separator: " ")
    }

    // MARK: List intros

    static let doneIntro = "Here is everything you have done today."
    static let nextIntro = "Here is what is coming up."

    // MARK: The spoken grounding line (Home, on open)

    /// The instant, precomputed present-orientation line spoken on open.
    /// Verbatim — no model call, no spinner.
    static func spokenGrounding(facts: GroundingFacts, at date: Date, calendar: Calendar = .current) -> String {
        "It's \(partOfDay(at: date, calendar: calendar)), about \(timeOfDay(date, calendar: calendar)). "
        + "You are at \(facts.homeLabel), \(facts.userName), and everything is okay."
    }

    // MARK: Night mode

    /// Night runs on the caregiver window / late clock. Simple and honest.
    static func isNight(at date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 20 || hour < 6
    }

    static func nightTimeLine(at date: Date, calendar: Calendar = .current) -> String {
        "about \(timeOfDay(date, calendar: calendar))"
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

    // MARK: - Private helpers

    private static func lowercasedLabel(_ label: String) -> String {
        guard let first = label.first else { return label }
        return first.lowercased() + label.dropFirst()
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
