import SwiftUI
import SwiftData

/// Caregiver-only editor for the two things that ground the person: the
/// highest-stakes record (`GroundingFacts`) and the comfort topics the model
/// is allowed to steer conversation toward.
///
/// `GroundingFacts` is drafted locally and only committed on Save, gated by
/// the model's own invariant — see `GroundingFacts.isComplete`. Comfort
/// topics carry no such invariant, so they're edited live against the store.
struct PatientInfoEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var facts: [GroundingFacts]
    @Query(sort: \ComfortTopic.sortOrder) private var comfortTopics: [ComfortTopic]

    @State private var userName = ""
    @State private var homeLabel = ""
    @State private var roomLabel = ""
    @State private var currentCaregiverName = ""
    @State private var currentCaregiverRelationship = ""
    @State private var primaryContactName = ""
    @State private var primaryContactRelationship = ""
    @State private var primaryContactPhone = ""
    @State private var sessionTimeoutMinutes: Double = 20
    @State private var hasLoadedDraft = false

    private var draftIsComplete: Bool {
        ![userName, homeLabel, currentCaregiverName, primaryContactName, primaryContactPhone]
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 24) {
                    identitySection
                    caregiverSection
                    contactSection
                    if !draftIsComplete {
                        Text("Name, home, caregiver, and primary contact name + phone can't be empty.")
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.tan)
                    }
                    conversationSection
                    comfortTopicsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.background)
        .task { loadDraftIfNeeded() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(Theme.font(15, .medium))
                .foregroundStyle(Theme.mutedText)
            Spacer()
            Text("Edit patient info")
                .font(Theme.font(16, .semibold))
                .foregroundStyle(Theme.foreground)
            Spacer()
            Button("Save") { save() }
                .font(Theme.font(15, .semibold))
                .foregroundStyle(draftIsComplete ? Theme.sage : Theme.mutedText)
                .disabled(!draftIsComplete)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Sections

    private var identitySection: some View {
        RippleCard {
            VStack(spacing: 14) {
                labeledField("Name", text: $userName)
                Divider().overlay(Theme.border)
                labeledField("Home", text: $homeLabel, placeholder: "Elm Grove Care Home")
                Divider().overlay(Theme.border)
                labeledField("Room", text: $roomLabel, placeholder: "Room 14")
            }
        }
    }

    private var caregiverSection: some View {
        RippleCard {
            VStack(spacing: 14) {
                Text("Caregiver on duty")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                labeledField("Name", text: $currentCaregiverName)
                Divider().overlay(Theme.border)
                labeledField("Relationship", text: $currentCaregiverRelationship, placeholder: "Your nurse, on duty today")
            }
        }
    }

    private var contactSection: some View {
        RippleCard {
            VStack(spacing: 14) {
                Text("Primary contact")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                labeledField("Name", text: $primaryContactName)
                Divider().overlay(Theme.border)
                labeledField("Relationship", text: $primaryContactRelationship, placeholder: "Your son")
                Divider().overlay(Theme.border)
                labeledField("Phone", text: $primaryContactPhone, placeholder: "+1 555 010 0100")
                    .keyboardType(.phonePad)
            }
        }
    }

    /// The only app-behavior setting exposed here, alongside the facts
    /// themselves — how long a talking-out-loud session may run before it
    /// closes itself, for privacy. Not a "fact" like the sections above, but
    /// this is the one caregiver-only editing surface the app has.
    private var conversationSection: some View {
        RippleCard {
            VStack(spacing: 14) {
                Text("Conversation settings")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Stepper(value: $sessionTimeoutMinutes, in: 5...60, step: 5) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Conversation length limit")
                            .font(Theme.font(15))
                            .foregroundStyle(Theme.foreground)
                        Text("\(Int(sessionTimeoutMinutes)) minutes")
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.mutedText)
                    }
                }
            }
        }
    }

    private var comfortTopicsSection: some View {
        RippleCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Comfort topics")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.secondaryText)

                ForEach(comfortTopics) { topic in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            TextField("Topic", text: titleBinding(topic))
                                .font(Theme.font(14, .medium))
                                .foregroundStyle(Theme.foreground)
                            Button { modelContext.delete(topic) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.mutedText)
                            }
                        }
                        TextField("A sentence of context", text: detailBinding(topic))
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if topic.id != comfortTopics.last?.id {
                        Divider().overlay(Theme.border)
                    }
                }

                Button { addTopic() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add a topic")
                    }
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.sage)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.font(11, .medium))
                .foregroundStyle(Theme.mutedText)
            TextField(placeholder, text: text)
                .font(Theme.font(15))
                .foregroundStyle(Theme.foreground)
        }
    }

    // MARK: - Comfort topic bindings

    private func titleBinding(_ topic: ComfortTopic) -> Binding<String> {
        Binding(get: { topic.title }, set: { topic.title = $0; topic.lastModified = .now })
    }

    private func detailBinding(_ topic: ComfortTopic) -> Binding<String> {
        Binding(get: { topic.detail }, set: { topic.detail = $0; topic.lastModified = .now })
    }

    private func addTopic() {
        let topic = ComfortTopic(title: "", detail: "", sortOrder: (comfortTopics.map(\.sortOrder).max() ?? -1) + 1)
        modelContext.insert(topic)
    }

    // MARK: - Draft lifecycle

    private func loadDraftIfNeeded() {
        guard !hasLoadedDraft, let facts = facts.first else { return }
        userName = facts.userName
        homeLabel = facts.homeLabel
        roomLabel = facts.roomLabel
        currentCaregiverName = facts.currentCaregiverName
        currentCaregiverRelationship = facts.currentCaregiverRelationship
        primaryContactName = facts.primaryContactName
        primaryContactRelationship = facts.primaryContactRelationship
        primaryContactPhone = facts.primaryContactPhone
        sessionTimeoutMinutes = facts.sessionTimeoutMinutes
        hasLoadedDraft = true
    }

    private func save() {
        guard draftIsComplete, let facts = facts.first else { return }
        facts.userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        facts.homeLabel = homeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        facts.roomLabel = roomLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        facts.currentCaregiverName = currentCaregiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        facts.currentCaregiverRelationship = currentCaregiverRelationship.trimmingCharacters(in: .whitespacesAndNewlines)
        facts.primaryContactName = primaryContactName.trimmingCharacters(in: .whitespacesAndNewlines)
        facts.primaryContactRelationship = primaryContactRelationship.trimmingCharacters(in: .whitespacesAndNewlines)
        facts.primaryContactPhone = primaryContactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        facts.sessionTimeoutMinutes = sessionTimeoutMinutes
        facts.lastModified = .now
        dismiss()
    }
}

#Preview {
    PatientInfoEditView()
        .modelContainer(previewContainer)
}
