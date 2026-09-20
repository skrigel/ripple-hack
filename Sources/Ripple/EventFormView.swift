import SwiftUI
import SwiftData

/// Add or edit an entry in the one event log. `when` can be set to the past
/// (a memory) or the future (a plan) — `Event` is deliberately bidirectional,
/// so there's no separate "past vs. upcoming" toggle here.
struct EventFormView: View {
    enum Mode {
        case create
        case edit(Event)
    }

    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currentCaregiver) private var currentCaregiver
    @Query(sort: \Person.sortOrder) private var people: [Person]

    @State private var title: String
    @State private var detail: String
    @State private var when: Date
    @State private var participantIDs: Set<UUID>

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _title = State(initialValue: "")
            _detail = State(initialValue: "")
            _when = State(initialValue: .now)
            _participantIDs = State(initialValue: [])
        case .edit(let event):
            _title = State(initialValue: event.title)
            _detail = State(initialValue: event.detail)
            _when = State(initialValue: event.when)
            _participantIDs = State(initialValue: Set(event.participants.map(\.id)))
        }
    }

    private var isEditing: Bool { if case .edit = mode { true } else { false } }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedTitle.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 24) {
                    detailsSection
                    whenSection
                    participantsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(Theme.font(15, .medium))
                .foregroundStyle(Theme.mutedText)
            Spacer()
            Text(isEditing ? "Edit event" : "New event")
                .font(Theme.font(16, .semibold))
                .foregroundStyle(Theme.foreground)
            Spacer()
            Button("Save") { save() }
                .font(Theme.font(15, .semibold))
                .foregroundStyle(canSave ? Theme.sage : Theme.mutedText)
                .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Sections

    private var detailsSection: some View {
        RippleCard {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(Theme.font(11, .medium))
                        .foregroundStyle(Theme.mutedText)
                    TextField("Dinner with David", text: $title)
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.foreground)
                }
                Divider().overlay(Theme.border)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detail")
                        .font(Theme.font(11, .medium))
                        .foregroundStyle(Theme.mutedText)
                    TextField("A note about the event", text: $detail)
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.foreground)
                }
            }
        }
    }

    private var whenSection: some View {
        RippleCard {
            DatePicker("When", selection: $when)
                .font(Theme.font(15))
                .foregroundStyle(Theme.foreground)
                .tint(Theme.sage)
        }
    }

    private var participantsSection: some View {
        RippleCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Who's involved")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.secondaryText)

                if people.isEmpty {
                    Text("No one in People yet.")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.mutedText)
                }

                ForEach(people) { person in
                    Button { toggle(person) } label: {
                        HStack(spacing: 12) {
                            Text(person.initial)
                                .font(Theme.font(14, .semibold))
                                .foregroundStyle(person.avatarTint)
                                .frame(width: 32, height: 32)
                                .background(person.avatarBackground, in: Circle())
                            Text(person.name)
                                .font(Theme.font(14, .medium))
                                .foregroundStyle(Theme.foreground)
                            Spacer(minLength: 0)
                            if participantIDs.contains(person.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.sage)
                            } else {
                                Image(systemName: "circle").foregroundStyle(Theme.mutedText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Behaviour

    private func toggle(_ person: Person) {
        if participantIDs.contains(person.id) {
            participantIDs.remove(person.id)
        } else {
            participantIDs.insert(person.id)
        }
    }

    private func save() {
        guard canSave else { return }
        let participants = people.filter { participantIDs.contains($0.id) }

        switch mode {
        case .create:
            let event = Event(
                title: trimmedTitle,
                detail: detail,
                when: when,
                source: .caregiverNote,
                createdByPersonID: currentCaregiver?.id,
                participants: participants
            )
            modelContext.insert(event)
        case .edit(let event):
            event.title = trimmedTitle
            event.detail = detail
            event.when = when
            event.participants = participants
            event.lastModified = .now
        }
        dismiss()
    }
}

extension EventFormView.Mode: Identifiable {
    var id: String {
        switch self {
        case .create: "create"
        case .edit(let event): event.id.uuidString
        }
    }
}

#Preview {
    EventFormView(mode: .create)
        .modelContainer(previewContainer)
}
