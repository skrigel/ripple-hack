import SwiftUI
import SwiftData

struct PeopleView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.currentCaregiver) private var currentCaregiver
    @Query(sort: \Person.sortOrder) private var people: [Person]

    @State private var personCardMode: PersonContactCardView.Mode?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("The people in your life.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.mutedText)
                Spacer()
                if currentCaregiver != nil {
                    Button { personCardMode = .create(presetCaregiver: false) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add person")
                        }
                        .font(Theme.font(13, .medium))
                        .foregroundStyle(Theme.sage)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            ForEach(people) { person in
                PersonCard(
                    person: person,
                    onCall: { call(person) },
                    onEdit: currentCaregiver != nil ? { personCardMode = .edit(person) } : nil
                )
            }
        }
        .padding(.horizontal, 20)
        .sheet(item: $personCardMode) { mode in
            PersonContactCardView(mode: mode)
        }
    }

    private func call(_ person: Person) {
        let digits = person.phone.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel://\(digits)") else { return }
        openURL(url)
    }
}

private struct PersonCard: View {
    let person: Person
    let onCall: () -> Void
    var onEdit: (() -> Void)? = nil

    var body: some View {
        RippleCard {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    Text(person.initial)
                        .font(Theme.font(20, .semibold))
                        .foregroundStyle(person.avatarTint)
                        .frame(width: 56, height: 56)
                        .background(person.avatarBackground, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(person.name)
                                .font(Theme.font(16, .semibold))
                                .foregroundStyle(Theme.foreground)
                            if person.isVisitingToday {
                                Text("Visiting today")
                                    .font(Theme.font(11, .medium))
                                    .foregroundStyle(Theme.sage)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Theme.sageSoft, in: Capsule())
                            }
                        }
                        Text(person.relationship)
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.mutedText)
                        Text(person.recentContext)
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 0)

                    if let onEdit {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.mutedText)
                                .frame(width: 28, height: 28)
                                .background(Theme.muted, in: Circle())
                        }
                        .accessibilityLabel("Edit \(person.name)")
                    }
                }

                Button(action: onCall) {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.fill").font(.system(size: 13, weight: .semibold))
                        Text("Call \(person.name)")
                    }
                }
                .buttonStyle(SoftButtonStyle())
                .accessibilityLabel("Call \(person.name)")
            }
        }
    }
}
