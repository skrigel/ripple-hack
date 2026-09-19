import SwiftUI
import SwiftData

struct PeopleView: View {
    @Environment(\.openURL) private var openURL
    @Query(sort: \Person.sortOrder) private var people: [Person]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The people in your life.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.mutedText)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

            ForEach(people) { person in
                PersonCard(person: person) { call(person) }
            }
        }
        .padding(.horizontal, 20)
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
