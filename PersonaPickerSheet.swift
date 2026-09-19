import SwiftUI
import SwiftData

/// "Who's using Ripple right now?" — lets a caregiver identify themselves
/// (or hand the phone back to patient view), and lets a new caregiver be
/// added without leaving the flow. No passwords: picking a name *is* the
/// identification.
struct PersonaPickerSheet: View {
    @Environment(RippleServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.sortOrder) private var people: [Person]

    @State private var showingAddChoice = false
    @State private var subSheet: SubSheet?

    private enum SubSheet: Identifiable {
        case elevateExisting
        case newPerson
        var id: Int { hashValue }
    }

    private var caregivers: [Person] { people.filter(\.isCaregiver) }
    private var nonCaregivers: [Person] { people.filter { !$0.isCaregiver } }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 20) {
                    patientRow

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Caregivers")
                            .font(Theme.font(13, .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 4)

                        ForEach(caregivers) { caregiver in
                            caregiverRow(caregiver)
                        }

                        addRow
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.background)
        .confirmationDialog("Add a caregiver", isPresented: $showingAddChoice) {
            Button("Make an existing person a caregiver") { subSheet = .elevateExisting }
            Button("Add a new person") { subSheet = .newPerson }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $subSheet) { sheet in
            switch sheet {
            case .elevateExisting:
                ElevatePersonListView(people: nonCaregivers) { chosen in
                    chosen.isCaregiver = true
                    chosen.lastModified = .now
                    select(chosen)
                }
                .environment(services)
            case .newPerson:
                PersonContactCardView(mode: .create(presetCaregiver: true)) { created in
                    select(created)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Who's using Ripple?")
                .font(Theme.font(16, .semibold))
                .foregroundStyle(Theme.foreground)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.mutedText)
                    .frame(width: 28, height: 28)
                    .background(Theme.muted, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Rows

    private var patientRow: some View {
        Button { select(nil) } label: {
            RippleCard {
                HStack(spacing: 14) {
                    IconChip(systemName: "person.crop.circle", background: Theme.muted, tint: Theme.mutedText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Patient view")
                            .font(Theme.font(15, .semibold))
                            .foregroundStyle(Theme.foreground)
                        Text("No caregiver signed in")
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.mutedText)
                    }
                    Spacer(minLength: 0)
                    if services.persona.selectedCaregiverID == nil {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.sage)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func caregiverRow(_ caregiver: Person) -> some View {
        Button { select(caregiver) } label: {
            RippleCard {
                HStack(spacing: 14) {
                    Text(caregiver.initial)
                        .font(Theme.font(18, .semibold))
                        .foregroundStyle(caregiver.avatarTint)
                        .frame(width: 44, height: 44)
                        .background(caregiver.avatarBackground, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(caregiver.name)
                            .font(Theme.font(15, .semibold))
                            .foregroundStyle(Theme.foreground)
                        Text(caregiver.relationship)
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.mutedText)
                    }
                    Spacer(minLength: 0)
                    if services.persona.selectedCaregiverID == caregiver.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.sage)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var addRow: some View {
        Button { showingAddChoice = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").font(.system(size: 15, weight: .semibold))
                Text("Add a caregiver")
            }
            .font(Theme.font(14, .medium))
            .foregroundStyle(Theme.sage)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    // MARK: - Selection

    private func select(_ person: Person?) {
        services.persona.selectedCaregiverID = person?.id
        subSheet = nil
        dismiss()
    }
}

/// The "+" flow's first branch: pick a non-caregiver person to elevate.
private struct ElevatePersonListView: View {
    let people: [Person]
    let onChoose: (Person) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Make a caregiver")
                    .font(Theme.font(16, .semibold))
                    .foregroundStyle(Theme.foreground)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.mutedText)
                        .frame(width: 28, height: 28)
                        .background(Theme.muted, in: Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 12) {
                    if people.isEmpty {
                        RippleCard {
                            Text("Everyone in People is already a caregiver.")
                                .font(Theme.font(14))
                                .foregroundStyle(Theme.mutedText)
                        }
                    }
                    ForEach(people) { person in
                        Button {
                            onChoose(person)
                            dismiss()
                        } label: {
                            RippleCard {
                                HStack(spacing: 14) {
                                    Text(person.initial)
                                        .font(Theme.font(18, .semibold))
                                        .foregroundStyle(person.avatarTint)
                                        .frame(width: 44, height: 44)
                                        .background(person.avatarBackground, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(person.name)
                                            .font(Theme.font(15, .semibold))
                                            .foregroundStyle(Theme.foreground)
                                        Text(person.relationship)
                                            .font(Theme.font(12))
                                            .foregroundStyle(Theme.mutedText)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .background(Theme.background)
    }
}

#Preview {
    PersonaPickerSheet()
        .environment(RippleServices())
        .modelContainer(previewContainer)
}
