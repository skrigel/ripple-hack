import Foundation
import SwiftData
import SwiftUI

// MARK: - Enumerated domain vocabulary
//
// Small, closed vocabularies are modelled as enums with behaviour attached,
// rather than raw strings scattered through the UI.

/// How an event got into the log. There are exactly two trusted ingestion
/// paths (a caregiver note, a conversation recap) plus an optional third for
/// task-adjacent confirmations.
///
/// A `.confirmation` is a *memory record*, never proof a physical action
/// happened — nothing in the UI may present it as a safety guarantee.
enum EventSource: String, Codable, CaseIterable {
    case caregiverNote
    case conversation
    case confirmation

    /// How the source reads to a caregiver. Never shown to the person.
    var label: String {
        switch self {
        case .caregiverNote: "Caregiver note"
        case .conversation: "From a conversation"
        case .confirmation: "Marked done"
        }
    }
}

// MARK: - SwiftData models
//
// Every record carries a UUID + `lastModified` so the store is sync-ready, per
// the build plan.

/// A person in the user's life — family, care staff, the on-call contact.
///
/// Relational, not a contact list: `relationship` is phrased from the person's
/// point of view ("Your son"), because that is the line the app speaks back.
@Model
final class Person {
    var id: UUID
    var name: String
    var relationship: String
    /// One line of caregiver-maintained context: "Visited last Sunday".
    var recentContext: String
    var phone: String
    /// Shared moments the app can bring up: "the summer you spent in Cornwall".
    /// Defaulted so lightweight migration can backfill existing rows.
    var memories: [String] = []
    @Attribute(.externalStorage) var photoData: Data?
    @Attribute(.externalStorage) var voiceClipData: Data?
    /// Avatar background/accent stored as hex so the store stays self-describing.
    var avatarBackgroundHex: UInt
    var avatarTintHex: UInt
    var isVisitingToday: Bool
    var sortOrder: Int
    var lastModified: Date

    /// Events this person was involved in — the tagging side of the log.
    var events: [Event]
    /// Conversations this person took part in.
    var conversations: [Conversation]

    init(
        id: UUID = UUID(),
        name: String,
        relationship: String,
        recentContext: String,
        phone: String,
        memories: [String] = [],
        photoData: Data? = nil,
        voiceClipData: Data? = nil,
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
        self.memories = memories
        self.photoData = photoData
        self.voiceClipData = voiceClipData
        self.avatarBackgroundHex = avatarBackgroundHex
        self.avatarTintHex = avatarTintHex
        self.isVisitingToday = isVisitingToday
        self.sortOrder = sortOrder
        self.lastModified = lastModified
        self.events = []
        self.conversations = []
    }

    var initial: String { String(name.prefix(1)).uppercased() }
    var avatarBackground: Color { Color(hex: avatarBackgroundHex) }
    var avatarTint: Color { Color(hex: avatarTintHex) }
    var hasVoiceClip: Bool { voiceClipData != nil }
}

/// Something that happened, or is going to happen — the single event log.
///
/// One timeline in both directions: `when` in the past is a recall aid, `when`
/// in the future is an upcoming moment (a visit, a meal together). This is
/// deliberately *not* a scheduler — nothing here reminds, repeats, or nags.
@Model
final class Event {
    var id: UUID
    var title: String
    var detail: String
    var when: Date
    private var sourceRaw: String
    /// Set when this event is the recap of a finished conversation, so the two
    /// stay linked without duplicating the summary text.
    var conversationID: UUID?
    /// Who was involved. Shares the people store with the People screen.
    @Relationship(inverse: \Person.events)
    var participants: [Person]
    var lastModified: Date

    init(
        id: UUID = UUID(),
        title: String,
        detail: String = "",
        when: Date,
        source: EventSource = .caregiverNote,
        conversationID: UUID? = nil,
        participants: [Person] = [],
        lastModified: Date = .now
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.when = when
        self.sourceRaw = source.rawValue
        self.conversationID = conversationID
        self.participants = participants
        self.lastModified = lastModified
    }

    var source: EventSource {
        get { EventSource(rawValue: sourceRaw) ?? .caregiverNote }
        set { sourceRaw = newValue.rawValue }
    }

    func hasHappened(by date: Date = .now) -> Bool { when <= date }
}

/// A conversation session — with the app, or with a family member through it.
///
/// Only ever past or ongoing: `endedAt == nil` means it is still running. The
/// session auto-terminates after a fixed window for privacy; on close the model
/// summarises it into `summary`, which is then written to the event log.
@Model
final class Conversation {
    var id: UUID
    var startedAt: Date
    /// `nil` while the conversation is ongoing.
    var endedAt: Date?
    /// The plain recap, written once on close. Empty while ongoing.
    var summary: String
    /// Who the person was talking to. Empty means they were talking to the app.
    @Relationship(inverse: \Person.conversations)
    var participants: [Person]
    var lastModified: Date

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        endedAt: Date? = nil,
        summary: String = "",
        participants: [Person] = [],
        lastModified: Date = .now
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.summary = summary
        self.participants = participants
        self.lastModified = lastModified
    }

    var isOngoing: Bool { endedAt == nil }

    /// How long the session ran, or has been running.
    func duration(at date: Date = .now) -> TimeInterval {
        (endedAt ?? date).timeIntervalSince(startedAt)
    }

    /// The session auto-terminates after this window, for privacy.
    static let sessionWindow: TimeInterval = 20 * 60
}

/// Something the person likes talking about — a hobby, a place, a memory.
///
/// Caregiver-noted, and the one place the model is allowed to *steer* rather
/// than only report: it may open or gently redirect a conversation with these.
@Model
final class ComfortTopic {
    var id: UUID
    var title: String
    /// A sentence of context the model can lean on, in the caregiver's words.
    var detail: String
    var sortOrder: Int
    var lastModified: Date

    init(
        id: UUID = UUID(),
        title: String,
        detail: String = "",
        sortOrder: Int,
        lastModified: Date = .now
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.sortOrder = sortOrder
        self.lastModified = lastModified
    }
}

/// The highest-stakes record: the facts the app may draw on at any moment,
/// including moments of high distress.
///
/// Critical fields (place, current caregiver, who-to-call) must never be empty
/// or stale — `isComplete` is the guardrail the caregiver view validates on save.
@Model
final class GroundingFacts {
    var userName: String
    var homeLabel: String
    var roomLabel: String
    /// Who is on duty right now — the most perishable field in the store.
    ///
    /// Defaulted to empty only so lightweight migration can backfill rows
    /// written before this field existed. Empty is *not* an acceptable resting
    /// state: `isComplete` is false until a caregiver fills it in.
    var currentCaregiverName: String = ""
    var currentCaregiverRelationship: String = ""
    var primaryContactName: String
    var primaryContactRelationship: String
    var primaryContactPhone: String
    var lastModified: Date

    init(
        userName: String,
        homeLabel: String,
        roomLabel: String,
        currentCaregiverName: String,
        currentCaregiverRelationship: String,
        primaryContactName: String,
        primaryContactRelationship: String,
        primaryContactPhone: String,
        lastModified: Date = .now
    ) {
        self.userName = userName
        self.homeLabel = homeLabel
        self.roomLabel = roomLabel
        self.currentCaregiverName = currentCaregiverName
        self.currentCaregiverRelationship = currentCaregiverRelationship
        self.primaryContactName = primaryContactName
        self.primaryContactRelationship = primaryContactRelationship
        self.primaryContactPhone = primaryContactPhone
        self.lastModified = lastModified
    }

    /// Every field the app may need mid-distress is present. A caregiver edit
    /// that would make this false must be rejected, not silently saved.
    var isComplete: Bool {
        ![userName, homeLabel, currentCaregiverName, primaryContactName, primaryContactPhone]
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// Every entity the store persists — used to build the `ModelContainer`.
enum RippleSchema {
    static let all: [any PersistentModel.Type] = [
        Person.self,
        Event.self,
        Conversation.self,
        ComfortTopic.self,
        GroundingFacts.self,
    ]
}
