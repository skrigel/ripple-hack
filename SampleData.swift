import Foundation
import SwiftData

/// Seeds the store on first launch with the content shown in the design.
/// Idempotent: only runs when the store is empty.
enum SampleData {

    static func seedIfNeeded(_ context: ModelContext) {
        let alreadySeeded = (try? context.fetchCount(FetchDescriptor<GroundingFacts>())) ?? 0
        guard alreadySeeded == 0 else { return }

        seedGroundingFacts(context)
        let people = seedPeople(context)
        let conversation = seedConversations(context, people: people)
        seedEvents(context, people: people, conversation: conversation)
        seedComfortTopics(context)

        try? context.save()
    }

    // MARK: - Sections

    private static func seedGroundingFacts(_ context: ModelContext) {
        context.insert(GroundingFacts(
            userName: "Margaret",
            homeLabel: "Elm Grove Care Home",
            roomLabel: "Room 14",
            currentCaregiverName: "Sarah",
            currentCaregiverRelationship: "Your nurse, on duty today",
            primaryContactName: "David",
            primaryContactRelationship: "Your son",
            primaryContactPhone: "+15550102"
        ))
    }

    /// Returns the inserted people keyed by name so events can tag them.
    private static func seedPeople(_ context: ModelContext) -> [String: Person] {
        let people = [
            Person(name: "Maya", relationship: "Your daughter",
                   recentContext: "Visiting today at 3 o'clock", phone: "+15550101",
                   memories: ["The garden you planted together the spring she moved house"],
                   avatarBackgroundHex: 0xEAF3F0, avatarTintHex: 0x7BA79B,
                   isVisitingToday: true, sortOrder: 0),
            Person(name: "David", relationship: "Your son",
                   recentContext: "Visited last Sunday", phone: "+15550102",
                   memories: ["Teaching him to drive on the lanes near Ashford"],
                   avatarBackgroundHex: 0xF5F0E8, avatarTintHex: 0xC5B89A,
                   sortOrder: 1),
            Person(name: "Sarah", relationship: "Your nurse, on duty today",
                   recentContext: "Here until 6 o'clock this evening", phone: "+15550103",
                   avatarBackgroundHex: 0xF0EEF5, avatarTintHex: 0xA49BB7,
                   sortOrder: 2),
            Person(name: "Robert", relationship: "Your brother",
                   recentContext: "Called three days ago", phone: "+15550104",
                   memories: ["Summers at the coast when you were both small"],
                   avatarBackgroundHex: 0xF5EFEE, avatarTintHex: 0xB79B9B,
                   sortOrder: 3),
        ]
        people.forEach(context.insert)
        return Dictionary(uniqueKeysWithValues: people.map { ($0.name, $0) })
    }

    /// One finished session, so the log has a conversation recap in it.
    private static func seedConversations(
        _ context: ModelContext,
        people: [String: Person]
    ) -> Conversation {
        let conversation = Conversation(
            startedAt: today(10, 5),
            endedAt: today(10, 22),
            summary: "You had a chat with Maya about the garden and her trip.",
            participants: [people["Maya"]].compactMap { $0 }
        )
        context.insert(conversation)
        return conversation
    }

    /// The single event log, running in both directions from now.
    private static func seedEvents(
        _ context: ModelContext,
        people: [String: Person],
        conversation: Conversation
    ) {
        // Past — caregiver notes.
        context.insert(Event(title: "Had breakfast in the day room",
                             when: today(8, 15), source: .caregiverNote))
        context.insert(Event(title: "Saw the doctor", detail: "A routine check, all well.",
                             when: today(9, 30), source: .caregiverNote))

        // Past — the recap of the conversation above, written on close.
        context.insert(Event(title: conversation.summary,
                             when: conversation.endedAt ?? today(10, 22),
                             source: .conversation,
                             conversationID: conversation.id,
                             participants: conversation.participants))

        // Past — a confirmation. A memory record, not proof anything happened.
        context.insert(Event(title: "Had lunch", when: today(12, 30), source: .confirmation))

        // Later today — ordinary events whose time has not arrived yet.
        context.insert(Event(title: "Maya visits", detail: "Your daughter",
                             when: today(15, 0), source: .caregiverNote,
                             participants: [people["Maya"]].compactMap { $0 }))
        context.insert(Event(title: "Dinner with David", detail: "Your son",
                             when: today(17, 30), source: .caregiverNote,
                             participants: [people["David"]].compactMap { $0 }))

        // Earlier days. Off-screen on Home, but the assistant can still reach
        // them for "when did I last see David".
        context.insert(Event(title: "David came for lunch", detail: "He brought photographs.",
                             when: daysAway(-3, hour: 12, minute: 30), source: .caregiverNote,
                             participants: [people["David"]].compactMap { $0 }))
        context.insert(Event(title: "Robert called", when: daysAway(-3, hour: 16, minute: 0),
                             source: .caregiverNote,
                             participants: [people["Robert"]].compactMap { $0 }))
        context.insert(Event(title: "Walked in the garden with Sarah",
                             when: daysAway(-1, hour: 10, minute: 15), source: .caregiverNote,
                             participants: [people["Sarah"]].compactMap { $0 }))

        // Beyond today — likewise off-screen, kept so the app knows it's coming.
        context.insert(Event(title: "Maya visits again", detail: "Your daughter",
                             when: daysAway(2, hour: 14, minute: 0), source: .caregiverNote,
                             participants: [people["Maya"]].compactMap { $0 }))
    }

    private static func seedComfortTopics(_ context: ModelContext) {
        [
            ("The garden", "She kept roses for forty years and still names the varieties."),
            ("Cornwall", "Family holidays at the coast — she lights up describing the cliff path."),
            ("Teaching", "She taught primary school in Ashford and loves talking about her class."),
        ].enumerated().forEach { index, topic in
            context.insert(ComfortTopic(title: topic.0, detail: topic.1, sortOrder: index))
        }
    }

    // MARK: - Helpers

    /// Today at the given hour/minute, so seeded times are always "today".
    private static func today(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    /// `offset` days from today at the given hour/minute. Negative is the past.
    private static func daysAway(_ offset: Int, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: offset, to: .now) ?? .now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
