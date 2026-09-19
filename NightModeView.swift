import SwiftUI
import SwiftData

/// The sundowning screen. Different rules from daytime: calm, minimal, never
/// argues. Reassure first, ground second, and escalate to a person — not more
/// words — via a prominent one-tap call.
struct NightModeView: View {
    @Environment(\.openURL) private var openURL
    @Environment(SpeechManager.self) private var speech

    @Query private var facts: [GroundingFacts]
    @Query private var reassurances: [Reassurance]

    let onExit: () -> Void

    private var groundingFacts: GroundingFacts? { facts.first }
    private var reassuranceLine: String { reassurances.first?.text ?? "You are safe. Everything is okay." }

    var body: some View {
        ZStack {
            Theme.nightBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Button(action: onExit) {
                    Text("Day view")
                        .font(Theme.font(12))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 48)

                reassurance.padding(.bottom, 44)

                if let facts = groundingFacts {
                    groundingFactsSection(facts)
                }

                Spacer(minLength: 24)

                if let facts = groundingFacts {
                    callSection(facts)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .onAppear(perform: speakNightGrounding)
    }

    // MARK: - Sections

    private var reassurance: some View {
        // Reassure first, before any fact.
        VStack(alignment: .leading, spacing: 2) {
            Text("You are safe.")
            Text("Everything is okay.")
        }
        .font(Theme.font(26, .light))
        .foregroundStyle(Theme.nightForeground.opacity(0.7))
    }

    private func groundingFactsSection(_ facts: GroundingFacts) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                NightLabel(text: "Where you are")
                Text("You are at home,\n\(facts.userName).")
                    .font(Theme.font(30, .semibold))
                    .foregroundStyle(Theme.nightForeground)
                Text(facts.homeLabel)
                    .font(Theme.font(16))
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                NightLabel(text: "The time")
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 0) {
                        Text("It is nighttime —")
                            .font(Theme.font(30, .semibold))
                            .foregroundStyle(Theme.nightForeground)
                        Text(GroundingService.nightTimeLine(at: context.date) + ".")
                            .font(Theme.font(30, .light))
                            .foregroundStyle(Theme.nightForeground.opacity(0.7))
                    }
                }
            }
        }
    }

    private func callSection(_ facts: GroundingFacts) -> some View {
        VStack(spacing: 8) {
            Text("If you need someone")
                .font(Theme.font(14))
                .foregroundStyle(Color.white.opacity(0.3))

            Button { call(facts) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill").font(.system(size: 18, weight: .semibold))
                    Text("Call \(facts.primaryContactName)").font(Theme.font(18, .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Theme.sage, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            }
            .accessibilityLabel("Call \(facts.primaryContactName)")

            Text(facts.primaryContactRelationship)
                .font(Theme.font(12))
                .foregroundStyle(Color.white.opacity(0.25))
        }
    }

    // MARK: - Behaviour

    private func speakNightGrounding() {
        guard let facts = groundingFacts else { return }
        // Reassure first, ground second — never lead with the correction.
        let line = "\(reassuranceLine) You are at \(facts.homeLabel), \(facts.userName). "
            + "It is nighttime, \(GroundingService.nightTimeLine(at: .now))."
        speech.speak(line)
    }

    private func call(_ facts: GroundingFacts) {
        let digits = facts.primaryContactPhone.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel://\(digits)") else { return }
        openURL(url)
    }
}

private struct NightLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.font(12, .medium))
            .tracking(2)
            .foregroundStyle(Color.white.opacity(0.3))
    }
}
