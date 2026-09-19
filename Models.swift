import Foundation
import SwiftData
import SwiftUI

// MARK: - Enumerated domain vocabulary
//
// Small, closed vocabularies are modelled as enums with behaviour attached,
// rather than raw strings scattered through the UI.

/// Who recorded a completion. Kept internal to the store; never surfaced to the
/// person (see the interaction-design "dignity note").
enum CompletionSource: String, Codable {
    case person
    case caregiver
}

/// The three time-orientation directions of the Home screen.
enum Orientation: String, CaseIterable, Identifiable {
    case past, now

    var id: String { rawValue }

    var label: String {
        switch self {
        case .past: "Done today"
        case .now: "Right now"
        }
    }
}

// MARK: - SwiftData models
//
// Every record carries a UUID + `lastModified` so the store is sync-ready, per
// the build plan. Naming avoids `Task` (Swift Concurrency) by using `CareTask`.

/// A person in the user's life — family, care staff, the on-call contact.
@Model
final class Person {
    var id: UUID
    var name: String
    var relationship: String
    var recentContext: String
    var phone: String
    /// Avatar background/accent stored as hex so the store stays self-describing.
    var avatarBackgroundHex: UInt
    var avatarTintHex: UInt
    var isVisitingToday: Bool
    var sortOrder: Int
    var lastModified: Date

    init(
        id: UUID = UUID(),
        name: String,
        relationship: String,
        recentContext: String,
        phone: String,
        avatarBackgroundHex: UInt,
        avatarTintHex: UInt,
        isVisitingToday: Bool = false,
        sortOrder: Int,
        lastModified: Date = .now
    ) {
        self.id = id
        self.name = name
        self.relationship = relationship
        self.recentContext = recentContext
        self.phone = phone
        self.avatarBackgroundHex = avatarBackgroundHex
        self.avatarTintHex = avatarTintHex
        self.isVisitingToday = isVisitingToday
        self.sortOrder = sortOrder
        self.lastModified = lastModified
    }

    var initial: String { String(name.prefix(1)).uppercased() }
    var avatarBackground: Color { Color(hex: avatarBackgroundHex) }
    var avatarTint: Color { Color(hex: avatarTintHex) }
}

/// A caregiver-authored routine, surfaced one ordered step at a time.
@Model
final class CareTask {
    var id: UUID
    var title: String
    @Relationship(deleteRule: .cascade, inverse: \TaskStep.task)
    var steps: [TaskStep]
    var scheduleHint: String?
    var sortOrder: Int
    var lastModified: Date

    init(
        id: UUID = UUID(),
        title: String,
        steps: [TaskStep] = [],
        scheduleHint: String? = nil,
        sortOrder: Int,
        lastModified: Date = .now
    ) {
        self.id = id
        self.title = title
        self.steps = steps
        self.scheduleHint = scheduleHint
        self.sortOrder = sortOrder
        self.lastModified = lastModified
    }

    var orderedSteps: [TaskStep] { steps.sorted { $0.order < $1.order } }
}

/// One verbatim instruction within a `CareTask`.
@Model
final class TaskStep {
    var id: UUID
    var order: Int
    var text: String
    var task: CareTask?

    init(id: UUID = UUID(), order: Int, text: String) {
        self.id = id
        self.order = order
        self.text = text
    }
}

/// A record that something happened today. Drives the reassuring "Done today"
/// view. This records *that a tap occurred*, never a physical safety guarantee.
@Model
final class LogEntry {
    var id: UUID
    var label: String
    var timestamp: Date
    var taskID: UUID?
    private var sourceRaw: String
    var lastModified: Date

    init(
        id: UUID = UUID(),
        label: String,
        timestamp: Date = .now,
        taskID: UUID? = nil,
        source: CompletionSource = .person,
        lastModified: Date = .now
    ) {
        self.id = id
        self.label = label
        self.timestamp = timestamp
        self.taskID = taskID
        self.sourceRaw = source.rawValue
        self.lastModified = lastModified
    }

    var source: CompletionSource {
        get { CompletionSource(rawValue: sourceRaw) ?? .person }
        set { sourceRaw = newValue.rawValue }
    }
}

/// Something coming up later today — powers the "What's next" view.
@Model
final class AgendaEvent {
    var id: UUID
    var time: Date
    var title: String
    var detail: String
    var lastModified: Date

    init(
        id: UUID = UUID(),
        time: Date,
        title: String,
        detail: String = "",
        lastModified: Date = .now
    ) {
        self.id = id
        self.time = time
        self.title = title
        self.detail = detail
        self.lastModified = lastModified
    }
}

/// The highest-stakes record: the facts night mode reads directly. Critical
/// fields (home, contact) must never be empty — validated on save (caregiver v1).
@Model
final class GroundingFacts {
    var userName: String
    var homeLabel: String
    var roomLabel: String
    var primaryContactName: String
    var primaryContactRelationship: String
    var primaryContactPhone: String
    var lastModified: Date

    init(
        userName: String,
        homeLabel: String,
        roomLabel: String,
        primaryContactName: String,
        primaryContactRelationship: String,
        primaryContactPhone: String,
        lastModified: Date = .now
    ) {
        self.userName = userName
        self.homeLabel = homeLabel
        self.roomLabel = roomLabel
        self.primaryContactName = primaryContactName
        self.primaryContactRelationship = primaryContactRelationship
        self.primaryContactPhone = primaryContactPhone
        self.lastModified = lastModified
    }
}

/// A caregiver-approved calming line. At night the model may only draw from
/// these — never free generation.
@Model
final class Reassurance {
    var id: UUID
    var text: String
    var lastModified: Date

    init(id: UUID = UUID(), text: String, lastModified: Date = .now) {
        self.id = id
        self.text = text
        self.lastModified = lastModified
    }
}

/// Every entity the store persists — used to build the `ModelContainer`.
enum RippleSchema {
    static let all: [any PersistentModel.Type] = [
        Person.self,
        CareTask.self,
        TaskStep.self,
        LogEntry.self,
        AgendaEvent.self,
        GroundingFacts.self,
        Reassurance.self,
    ]
}
