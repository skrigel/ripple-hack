import SwiftUI
import SwiftData

/// The "Ask me anything" sheet. Quick-action chips ask a fixed set of
/// questions; answers are built deterministically from the store, warmed for
/// tone by the phrasing engine, then spoken and streamed on screen.
struct AssistantSheet: View {
    @Environment(RippleServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var speech: SpeechManager { services.speech }
    private var phrasing: PhrasingEngine { services.phrasing }
    private var session: CompanionSession { services.session }

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
                    talkControl
                    chips
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.background)
        .task {
            // Opening the sheet *is* the ask, so start listening straight away
            // rather than making the person press a second button. If nobody
            // speaks, the session closes itself and leaves no trace.
            guard !session.isOpen else { return }
            await session.open(store: conversationStore)
        }
        .onDisappear {
            streamTask?.cancel()
            // Leaving the sheet ends the conversation, and writes its recap.
            if session.isOpen {
                Task { await session.close(store: conversationStore) }
            }
        }
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
            AssistantOrb(isSpeaking: isStreaming || speech.isSpeaking)

            if let spoken = currentResponse {
                RippleCard {
                    Text(spoken)
                        .font(Theme.font(16))
                        .foregroundStyle(Theme.foreground)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Talk to me, or tap a button below to ask me something.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.mutedText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 4)
    }

    /// In a conversation the screen mirrors what was just said aloud; outside
    /// one it mirrors the chip answer as it streams.
    private var currentResponse: String? {
        if session.isOpen, !session.transcriptLine.isEmpty { return session.transcriptLine }
        return displayed.isEmpty ? nil : displayed
    }

    // MARK: - Talking out loud
    //
    // A conversation never starts on its own. This button is the whole ask of
    // the person: if they never press it, the app simply knows less.

    private var talkControl: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    if session.isOpen {
                        await session.close(store: conversationStore)
                    } else {
                        await session.open(store: conversationStore)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: session.isOpen ? "stop.fill" : "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(session.isOpen ? "Finish talking" : "Let's talk out loud")
                        .font(Theme.font(15, .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ProminentButtonStyle())

            if let problem = session.listeningProblem {
                // Listening is the only thing missing; the buttons still work.
                Text(problem)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.mutedText)
                    .multilineTextAlignment(.center)
            } else if session.isOpen {
                Text(listeningHint)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.mutedText)
            }
        }
    }

    private var listeningHint: String {
        switch session.phase {
        case .opening: "Just a moment…"
        case .listening: session.listening.isHearingSpeech ? "I can hear you." : "I'm listening."
        case .thinking: "Let me think."
        case .speaking: "…"
        case .wrappingUp: "Saving what we talked about."
        case .closed: ""
        }
    }

    /// The slice of the store a conversation reads from and writes back to.
    private var conversationStore: ConversationStore {
        ConversationStore(
            context: modelContext,
            facts: facts.first,
            events: events,
            people: people,
            comfortTopics: comfortTopics
        )
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

        // Tapping a chip and asking out loud are the same question, so they
        // resolve to the same intent and the same deterministic answer.
        let intent = prompt.intent
        let grounded = GroundingService.answer(
            for: intent,
            digest: conversationStore.groundingDigest(),
            people: people,
            lastSpoken: speech.lastSpoken
        )

        streamTask = Task {
            // Sensitive lines are spoken exactly as built; everything else may
            // have its tone warmed if a model is available.
            let text = intent.isVerbatim ? grounded : await phrasing.warmlyRephrase(grounded)
            guard !Task.isCancelled else { return }
            speech.speak(text, priority: intent == .distress ? .grounding : .reply)
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
}

/// The fixed set of things the person can ask by tapping.
///
/// A chip is just a question asked without speaking, so each one maps to the
/// same `QueryIntent` the spoken path produces. The answer comes from one
/// place, and the rule about which lines skip the model applies to both.
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

    var intent: QueryIntent {
        switch self {
        case .time: .whatTime
        case .happened: .whatHappenedToday
        case .upcoming: .whatsComingUp
        case .who: .whoIsHere
        case .safe: .amISafe
        case .chat: .comfortChat(nil)
        }
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
