import Foundation
import SwiftData

/// Seeds the store on first launch with the content shown in the design.
/// Idempotent: only runs when the store is empty.
enum SampleData {

    static func seedIfNeeded(_ context: ModelContext) {
        let alreadySeeded = (try? context.fetchCount(FetchDescriptor<GroundingFacts>())) ?? 0
        guard alreadySeeded == 0 else { return }

        seedGroundingFacts(context)
        seedPeople(context)
        seedTasks(context)
        seedTodayLog(context)
        seedAgenda(context)
        seedReassurances(context)

        try? context.save()
    }

    // MARK: - Sections

    private static func seedGroundingFacts(_ context: ModelContext) {
        context.insert(GroundingFacts(
            userName: "Margaret",
            homeLabel: "Elm Grove Care Home",
            roomLabel: "Room 14",
            primaryContactName: "David",
            primaryContactRelationship: "Your son",
            primaryContactPhone: "+15550102"
        ))
    }

    private static func seedPeople(_ context: ModelContext) {
        [
            Person(name: "Maya", relationship: "Your daughter",
                   recentContext: "Visiting today at 3 o'clock", phone: "+15550101",
                   avatarBackgroundHex: 0xEAF3F0, avatarTintHex: 0x7BA79B,
                   isVisitingToday: true, sortOrder: 0),
            Person(name: "David", relationship: "Your son",
                   recentContext: "Visited last Sunday", phone: "+15550102",
                   avatarBackgroundHex: 0xF5F0E8, avatarTintHex: 0xC5B89A,
                   sortOrder: 1),
            Person(name: "Sarah", relationship: "Your nurse, on duty today",
                   recentContext: "Here until 6 o'clock this evening", phone: "+15550103",
                   avatarBackgroundHex: 0xF0EEF5, avatarTintHex: 0xA49BB7,
                   sortOrder: 2),
            Person(name: "Robert", relationship: "Your brother",
                   recentContext: "Called three days ago", phone: "+15550104",
                   avatarBackgroundHex: 0xF5EFEE, avatarTintHex: 0xB79B9B,
                   sortOrder: 3),
        ].forEach(context.insert)
    }

    private static func seedTasks(_ context: ModelContext) {
        let tea = CareTask(title: "Make your afternoon tea", scheduleHint: "afternoon", sortOrder: 0)
        tea.steps = stepList([
            "Fill the kettle with water and switch it on.",
            "Place a tea bag in your favourite mug.",
            "When the kettle clicks off, pour the water over the tea bag.",
            "Wait about three minutes, then remove the tea bag.",
            "Add milk and sugar if you like, then stir gently.",
            "Find a comfortable place to sit and enjoy your tea.",
        ])

        let evening = CareTask(title: "Get ready for the evening", scheduleHint: "evening", sortOrder: 1)
        evening.steps = stepList([
            "Change into your comfortable evening clothes.",
            "Take your evening medication with a glass of water.",
            "Draw the curtains in your room.",
        ])

        [tea, evening].forEach(context.insert)
    }

    private static func seedTodayLog(_ context: ModelContext) {
        [
            ("Had breakfast", 8, 15),
            ("Took your morning walk", 9, 30),
            ("Took your medication", 10, 45),
            ("Had lunch", 12, 30),
        ].forEach { label, hour, minute in
            context.insert(LogEntry(label: label, timestamp: today(hour, minute)))
        }
    }

    private static func seedAgenda(_ context: ModelContext) {
        [
            ("Maya visits", "Your daughter", 15, 0),
            ("Dinner", "With David", 17, 30),
            ("Evening tea", "", 20, 0),
        ].forEach { title, detail, hour, minute in
            context.insert(AgendaEvent(time: today(hour, minute), title: title, detail: detail))
        }
    }

    private static func seedReassurances(_ context: ModelContext) {
        [
            "You are safe. Everything is okay.",
            "You're safe, and I'm right here with you.",
            "There's nothing to worry about. You are home.",
        ].forEach { context.insert(Reassurance(text: $0)) }
    }

    // MARK: - Helpers

    private static func stepList(_ texts: [String]) -> [TaskStep] {
        texts.enumerated().map { TaskStep(order: $0.offset, text: $0.element) }
    }

    /// Today at the given hour/minute, so seeded times are always "today".
    private static func today(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }
}
