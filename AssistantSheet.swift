import SwiftUI
import SwiftData

/// The "Ask me anything" sheet. Quick-action chips ask a fixed set of
/// questions; answers are built deterministically from the store, warmed for
/// tone by the phrasing engine, then spoken and streamed on screen.
struct AssistantSheet: View {
    @Environment(SpeechManager.self) private var speech
    @Environment(PhrasingEngine.self) private var phrasing
    @Environment(\.dismiss) private var dismiss

    @Query private var facts: [GroundingFacts]
    @Query(sort: \Event.when) private var events: [Event]
    @Query(sort: \Person.sortOrder) private var people: [Person]
    @Query(sort: \ComfortTopic.sortOrder) private var comfortTopics: [ComfortTopic]

    @State private var selected: AssistantPrompt?
    @State private var displayed = ""
    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 28) {
                    orbAndResponse
                    chips
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.background)
        .onDisappear { streamTask?.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Ask me anything")
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

    // MARK: - Orb + streamed response

    private var orbAndResponse: some View {
        VStack(spacing: 20) {
            AssistantOrb(isSpeaking: isStreaming)

            if displayed.isEmpty {
                Text("Tap a button below to ask me something.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.mutedText)
                    .multilineTextAlignment(.center)
            } else {
                RippleCard {
                    Text(displayed)
                        .font(Theme.font(16))
                        .foregroundStyle(Theme.foreground)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Quick-action chips

    private var chips: some View {
        VStack(spacing: 10) {
            ForEach(AssistantPrompt.allCases) { prompt in
                let isSelected = prompt == selected
                Button { ask(prompt) } label: {
                    Text(prompt.label)
                        .font(Theme.font(14, .medium))
                        .foregroundStyle(isSelected ? Theme.sage : Theme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            (isSelected ? Theme.sageSoft : Theme.muted),
                            in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                .stroke(isSelected ? Color(hex: 0xC5DDD8) : .clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Behaviour

    private func ask(_ prompt: AssistantPrompt) {
        streamTask?.cancel()
        selected = prompt
        displayed = ""
        isStreaming = true

        let base = response(for: prompt)
        streamTask = Task {
            // Warm the tone if a model is available; instant fallback otherwise.
            let text = await phrasing.warmlyRephrase(base)
            guard !Task.isCancelled else { return }
            speech.speak(text)
            await stream(text)
            isStreaming = false
        }
    }

    /// Reveal the response one character at a time, echoing the design's stream.
    private func stream(_ text: String) async {
        guard !text.isEmpty else { return }
        for index in 1...text.count {
            if Task.isCancelled { return }
            displayed = String(text.prefix(index))
            try? await Task.sleep(for: .milliseconds(18))
        }
    }

    // MARK: - Deterministic answers from the store

    private func response(for prompt: AssistantPrompt) -> String {
        switch prompt {
        case .time: timeResponse
        case .happened: happenedResponse
        case .upcoming: upcomingResponse
        case .who: whoResponse
        case .safe: safeResponse
        case .chat: chatResponse
        }
    }

    private var userName: String { facts.first?.userName ?? "there" }

    /// The wider window the assistant may draw on — more than Home shows.
    private var digest: GroundingDigest? {
        facts.first.map {
            GroundingDigest(facts: $0, events: events, comfortTopics: comfortTopics)
        }
    }

    private var timeResponse: String {
        let base = "It's \(GroundingService.timeOfDay(.now)), \(userName)."
        guard let next = digest?.upcoming.first else { return base }
        return base + " \(next.title) is coming up at \(GroundingService.timeOfDay(next.when))."
    }

    private var happenedResponse: String {
        let items = (digest?.today ?? []).filter { $0.hasHappened() }
        guard !items.isEmpty else { return "You're just getting started today, \(userName)." }
        let phrases = items.map { "\($0.title.lowercased()) at \(GroundingService.timeOfDay($0.when))" }
        return "You've had a lovely day so far. " + GroundingService.list(phrases).capitalizedFirst + "."
    }

    /// Reaches past today — the next thing coming up may be days away.
    private var upcomingResponse: String {
        let items = digest?.upcoming.prefix(3).map { $0 } ?? []
        guard !items.isEmpty else { return "Nothing else is planned. You can rest easy." }
        let phrases = items.map { "\($0.title.lowercased()) \(dayPhrase(for: $0.when))" }
        return "Coming up, you have " + GroundingService.list(phrases) + "."
    }

    /// "at 3:00 pm" for today, "on Friday at 2:00 pm" beyond it.
    private func dayPhrase(for date: Date, calendar: Calendar = .current) -> String {
        let time = "at \(GroundingService.timeOfDay(date, calendar: calendar))"
        guard !calendar.isDate(date, inSameDayAs: .now) else { return time }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEE"
        return "on \(formatter.string(from: date)) \(time)"
    }

    private var whoResponse: String {
        let visiting = people.first { $0.isVisitingToday }
        let pieces = [
            facts.first.map { "\($0.currentCaregiverName) is \($0.currentCaregiverRelationship.lowercasedFirst)." },
            visiting.map { "\($0.name) is coming to visit." },
            facts.first.map { "If you need anyone else, \($0.primaryContactName) is just a phone call away." },
        ].compactMap { $0 }
        return pieces.isEmpty ? "You're not alone — help is always a phone call away." : pieces.joined(separator: " ")
    }

    private var safeResponse: String {
        guard let facts = facts.first else { return "You are safe. Everything is okay." }
        return "You are safe, \(facts.userName). You're at \(facts.homeLabel), \(facts.roomLabel). Everything is okay."
    }

    /// Opens a conversation from a caregiver-noted comfort topic. This is the
    /// one place the app *steers* rather than reports — and it still only ever
    /// draws on what a caregiver entered.
    private var chatResponse: String {
        guard let topic = comfortTopics.first else {
            return "I'd love to hear about your day, \(userName). What's on your mind?"
        }
        let opener = "Tell me about \(topic.title.lowercasedFirst), \(userName)."
        return topic.detail.isEmpty ? opener : opener + " I'd love to hear about it."
    }
}

/// The fixed set of things the person can ask.
enum AssistantPrompt: String, CaseIterable, Identifiable {
    case time, happened, upcoming, who, safe, chat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .time: "What time is it?"
        case .happened: "What's happened today?"
        case .upcoming: "What's coming up?"
        case .who: "Who's here today?"
        case .safe: "Am I safe?"
        case .chat: "Let's talk about something nice"
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }

    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}

/// The sage orb that emits calming ripple rings while speaking.
private struct AssistantOrb: View {
    let isSpeaking: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            if isSpeaking {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .fill(Theme.sage.opacity(0.18))
                        .frame(width: 80, height: 80)
                        .scaleEffect(animate ? 2.1 : 1)
                        .opacity(animate ? 0 : 0.55)
                        .animation(
                            .easeOut(duration: 1.5).repeatForever(autoreverses: false)
                                .delay(Double(ring) * 0.34),
                            value: animate
                        )
                }
            }

            Circle()
                .fill(orbFill)
                .frame(width: 80, height: 80)
                .shadow(color: isSpeaking ? Theme.sage.opacity(0.4) : .black.opacity(0.06),
                        radius: isSpeaking ? 12 : 6, y: isSpeaking ? 4 : 2)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(isSpeaking ? .white : Theme.sage)
                )
        }
        .frame(height: 80)
        .onChange(of: isSpeaking) { _, speaking in animate = speaking }
        .onAppear { animate = isSpeaking }
    }

    private var orbFill: AnyShapeStyle {
        if isSpeaking {
            AnyShapeStyle(LinearGradient(
                colors: [Theme.sage, Color(hex: 0x9DC4BB)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        } else {
            AnyShapeStyle(Theme.sageSoft)
        }
    }
}
