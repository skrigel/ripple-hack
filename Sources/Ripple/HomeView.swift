import SwiftUI
import SwiftData

/// "Where you are now" — the grounding answer, then today.
///
/// The screen shows only today: what is true right now, and the day's timeline
/// of events and conversations. Later-today events sit in that same list; they
/// are ordinary events whose time has not arrived. The app keeps a wider window
/// than this in the store (see `GroundingDigest`) so the assistant can still
/// answer about last week or next Tuesday — it just isn't on screen.
struct HomeView: View {
    @Environment(RippleServices.self) private var services
    @Environment(\.currentCaregiver) private var currentCaregiver

    @Query private var facts: [GroundingFacts]
    // Unsorted: `when` is optional now, so SwiftData can't sort by it directly.
    // Every consumer below re-sorts after filtering to known dates anyway.
    @Query private var events: [Event]
    @Query(sort: \Conversation.startedAt, order: .forward) private var conversations: [Conversation]

    @State private var eventFormMode: EventFormView.Mode?

    private var groundingFacts: GroundingFacts? { facts.first }

    var body: some View {
        VStack(spacing: 24) {
            nowSection
            todaySection
        }
        .padding(.horizontal, 20)
        .sheet(item: $eventFormMode) { mode in
            EventFormView(mode: mode)
                .environment(\.currentCaregiver, currentCaregiver)
                .presentationCornerRadius(Theme.sheetRadius)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Right now

    private var nowSection: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            VStack(spacing: 16) {
                RippleCard {
                    VStack(spacing: 4) {
                        Text(GroundingService.clock(at: now))
                            .font(Theme.font(52, .light))
                            .foregroundStyle(Theme.foreground)
                        Text(GroundingService.weekdayAndPartOfDay(at: now))
                            .font(Theme.font(16))
                            .foregroundStyle(Theme.mutedText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                if let facts = groundingFacts {
                    RippleCard {
                        HStack(spacing: 12) {
                            IconChip(systemName: "house.fill", background: Theme.tanSoft, tint: Theme.tan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("You are home, \(facts.userName).")
                                    .font(Theme.font(14, .medium))
                                    .foregroundStyle(Theme.foreground)
                                Text("\(facts.homeLabel) · \(facts.roomLabel)")
                                    .font(Theme.font(12))
                                    .foregroundStyle(Theme.mutedText)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Today

    private var todaySection: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let entries = GroundingService.timeline(
                events: events,
                conversations: conversations,
                on: now
            )

            VStack(alignment: .leading, spacing: 12) {
                Text(GroundingService.todayIntro)
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.mutedText)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)

                ForEach(entries) { entry in
                    TimelineRow(
                        entry: entry,
                        hasHappened: entry.hasHappened(by: now),
                        onEdit: currentCaregiver != nil ? editableEvent(for: entry) : nil
                    )
                }
            }
        }
    }

    // MARK: - Speech

    /// Opening the app is not a question, so it is not answered like one.
    /// A greeting says someone is here without reciting where they are —
    /// the full orientation line is there when it is asked for, and is spoken
    /// on the "Where am I?" and "Am I safe?" paths.
    ///
    /// Deliberately not wired up. `onAppear` fires every time Home is
    /// reselected, not once per launch, so this greeted the person on every
    /// tab switch. Kept for when there is a real "first view of the day"
    /// signal to hang it on.
    private func speakGreeting() {
        guard let facts = groundingFacts else { return }
        services.speech.speak(
            GroundingService.greeting(for: facts.userName, at: .now),
            priority: .grounding
        )
    }

    /// Caregiver notes and confirmations are editable; a conversation's recap
    /// is not — editing that summary is out of scope, so those rows stay
    /// read-only regardless of persona.
    private func editableEvent(for entry: TimelineEntry) -> (() -> Void)? {
        guard case .event(let event) = entry, event.source != .conversation else { return nil }
        return { eventFormMode = .edit(event) }
    }
}

// MARK: - Supporting views

/// One line of the day. Past entries read as settled and lead with a check;
/// entries still to come lead with their time, without implying anything is owed.
private struct TimelineRow: View {
    let entry: TimelineEntry
    let hasHappened: Bool
    /// Present only when a caregiver is signed in and this entry is an
    /// editable event; `nil` renders no pencil at all.
    var onEdit: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(hasHappened ? Theme.sage : Theme.coral)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
                .accessibilityHidden(true)

            Text(GroundingService.timeOfDay(entry.when))
                .font(Theme.font(12, .semibold))
                .foregroundStyle(Theme.mutedText)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.mutedText)
                }
            }

            Spacer(minLength: 8)

            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.mutedText)
                }
                .accessibilityLabel("Edit event")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    private var title: String {
        switch entry {
        case .event(let event): event.title
        case .conversation(let conversation): GroundingService.conversationLine(conversation)
        }
    }

    private var detail: String? {
        switch entry {
        case .event(let event): event.detail
        case .conversation: "Still talking"
        }
    }
}

#Preview {
    ScrollView { HomeView() }
        .background(Theme.background)
        .environment(RippleServices())
        .modelContainer(previewContainer)
}
