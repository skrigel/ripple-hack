import SwiftUI
import SwiftData

/// "Past events" — everything that has already happened, grouped by day,
/// most recent day first.
///
/// Unlike Home (which shows only today, past and future), this is the
/// complete history: every event with `when` before now, regardless of how
/// long ago. A caregiver adds new entries here, and can correct any of them —
/// the patient's own view has neither affordance.
struct PastEventsView: View {
    @Environment(\.currentCaregiver) private var currentCaregiver
    @Query(sort: \Event.when, order: .reverse) private var events: [Event]

    @State private var eventFormMode: EventFormView.Mode?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(GroundingService.pastEventsIntro)
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.mutedText)
                Spacer()
                if currentCaregiver != nil {
                    Button { eventFormMode = .create } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.sage)
                    }
                    .accessibilityLabel("Add an event")
                }
            }
            .padding(.horizontal, 4)

            if days.isEmpty {
                RippleCard {
                    Text("Nothing has happened yet. That's perfectly fine.")
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ForEach(days, id: \.day) { group in
                VStack(alignment: .leading, spacing: 12) {
                    Text(GroundingService.headerDate(at: group.day))
                        .font(Theme.font(13, .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 4)

                    ForEach(group.events) { event in
                        eventRow(event)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .sheet(item: $eventFormMode) { mode in
            EventFormView(mode: mode)
                .environment(\.currentCaregiver, currentCaregiver)
                .presentationCornerRadius(Theme.sheetRadius)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Rows

    private func eventRow(_ event: Event) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconChip(systemName: icon(for: event.source), diameter: 28,
                     background: Theme.sageSoft, tint: Theme.sage)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.mutedText)
                }
            }
            Spacer(minLength: 8)
            // Conversation recaps stay read-only, matching Home's timeline.
            if currentCaregiver != nil, event.source != .conversation {
                Button { eventFormMode = .edit(event) } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.mutedText)
                }
                .accessibilityLabel("Edit event")
            }
            Text(GroundingService.timeOfDay(event.when))
                .font(Theme.font(12))
                .foregroundStyle(Theme.mutedText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    // MARK: - Derived data

    /// Every event before now, grouped by day, most recent day first, each
    /// day's events listed most recent first.
    private var days: [(day: Date, events: [Event])] {
        let calendar = Calendar.current
        let earlier = GroundingService.past(events, before: .now)

        return Dictionary(grouping: earlier) { calendar.startOfDay(for: $0.when) }
            .map { (day: $0.key, events: $0.value.sorted { $0.when > $1.when }) }
            .sorted { $0.day > $1.day }
    }

    private func icon(for source: EventSource) -> String {
        switch source {
        case .caregiverNote: "note.text"
        case .conversation: "bubble.left.and.bubble.right.fill"
        case .confirmation: "checkmark"
        }
    }
}

#Preview {
    ScrollView { PastEventsView() }
        .background(Theme.background)
        .modelContainer(previewContainer)
}
