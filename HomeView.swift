import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(SpeechManager.self) private var speech

    @Query private var facts: [GroundingFacts]
    @Query(sort: \LogEntry.timestamp, order: .forward) private var log: [LogEntry]
    @Query(sort: \AgendaEvent.time, order: .forward) private var agenda: [AgendaEvent]

    @State private var orientation: Orientation = .now

    private var groundingFacts: GroundingFacts? { facts.first }

    var body: some View {
        VStack(spacing: 24) {
            OrientationPicker(selection: $orientation)

            switch orientation {
            case .now: nowView
            case .next: nextView
            }
        }
        .padding(.horizontal, 20)
        .onAppear(perform: speakGrounding)
    }

    // MARK: - Right now

    private var nowView: some View {
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

                RippleCard {
                    HStack(alignment: .top, spacing: 14) {
                        IconChip(systemName: "heart.fill", background: Theme.sageSoft, tint: Theme.sage)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nothing needed right now")
                                .font(Theme.font(16, .medium))
                                .foregroundStyle(Theme.foreground)
                            Text(GroundingService.presentSummary(
                                recentDone: mostRecentDone(before: now),
                                nextUp: nextEvent(after: now),
                                at: now
                            ))
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
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

    // MARK: - Done today

    private var pastView: some View {
        VStack(alignment: .leading, spacing: 12) {
            IntroLine(text: GroundingService.doneIntro)
            ForEach(todaysLog) { entry in
                HStack(spacing: 14) {
                    IconChip(systemName: "checkmark", diameter: 28,
                             background: Theme.sageSoft, tint: Theme.sage)
                    Text(entry.label)
                        .font(Theme.font(14, .medium))
                        .foregroundStyle(Theme.foreground)
                    Spacer()
                    Text(GroundingService.timeOfDay(entry.timestamp))
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.mutedText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
            }
        }
    }

    // MARK: - What's next

    private var nextView: some View {
        VStack(alignment: .leading, spacing: 12) {
            IntroLine(text: GroundingService.nextIntro)
            ForEach(agenda) { event in
                HStack(spacing: 14) {
                    Text(GroundingService.timeOfDay(event.time))
                        .font(Theme.font(12, .semibold))
                        .foregroundStyle(Theme.sage)
                        .frame(width: 64, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(Theme.font(14, .medium))
                            .foregroundStyle(Theme.foreground)
                        if !event.detail.isEmpty {
                            Text(event.detail)
                                .font(Theme.font(12))
                                .foregroundStyle(Theme.mutedText)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
            }
        }
    }

    // MARK: - Derived data

    private var todaysLog: [LogEntry] {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return log.filter { $0.timestamp >= startOfDay }
    }

    private func mostRecentDone(before now: Date) -> LogEntry? {
        todaysLog.last { $0.timestamp <= now }
    }

    private func nextEvent(after now: Date) -> AgendaEvent? {
        agenda.first { $0.time > now }
    }

    private func speakGrounding() {
        guard let facts = groundingFacts else { return }
        speech.speak(GroundingService.spokenGrounding(facts: facts, at: .now))
    }
}

// MARK: - Supporting views

/// The segmented "Done today / Right now / What's next" control.
private struct OrientationPicker: View {
    @Binding var selection: Orientation

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Orientation.allCases) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection = option }
                } label: {
                    Text(option.label)
                        .font(Theme.font(14, .medium))
                        .foregroundStyle(isSelected ? Theme.foreground : Theme.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.card)
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            }
                        }
                }
            }
        }
        .padding(4)
        .background(Theme.muted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct IntroLine: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.font(14, .medium))
            .foregroundStyle(Theme.mutedText)
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
    }
}
