import SwiftUI
import SwiftData

struct TaskListView: View {
    @Environment(\.modelContext) private var context
    @Environment(SpeechManager.self) private var speech

    @Query(sort: \CareTask.sortOrder) private var tasks: [CareTask]
    @Query private var log: [LogEntry]

    @State private var activeTask: CareTask?

    var body: some View {
        Group {
            if let task = activeTask {
                TaskStepView(task: task) { activeTask = nil }
            } else {
                taskList
            }
        }
        .padding(.horizontal, 20)
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tap a task to get started, one step at a time.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.mutedText)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

            ForEach(tasks) { task in
                Button {
                    activeTask = task
                } label: {
                    taskRow(task, isDone: isCompletedToday(task))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func taskRow(_ task: CareTask, isDone: Bool) -> some View {
        HStack(spacing: 14) {
            IconChip(
                systemName: isDone ? "checkmark" : "play.fill",
                background: isDone ? Theme.sageSoft : Theme.muted,
                tint: isDone ? Theme.sage : Theme.tan
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.foreground)
                Text(isDone ? "Completed" : "\(task.steps.count) steps")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.mutedText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.tan)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 6, y: 1)
        .opacity(isDone ? 0.5 : 1)
    }

    /// A task counts as done today if a matching completion is already logged.
    private func isCompletedToday(_ task: CareTask) -> Bool {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return log.contains { $0.taskID == task.id && $0.timestamp >= startOfDay }
    }
}

/// The one-step-at-a-time pacing flow for a single task.
private struct TaskStepView: View {
    @Environment(\.modelContext) private var context
    @Environment(SpeechManager.self) private var speech

    let task: CareTask
    let onExit: () -> Void

    @State private var stepIndex = 0

    private var steps: [TaskStep] { task.orderedSteps }
    private var currentStep: TaskStep? { steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }
    private var isLastStep: Bool { stepIndex == steps.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onExit) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    Text("All tasks").font(Theme.font(14))
                }
                .foregroundStyle(Theme.mutedText)
            }
            .padding(.bottom, 20)

            Text(task.title)
                .font(Theme.font(16, .semibold))
                .foregroundStyle(Theme.foreground)
            Text("Step \(stepIndex + 1) of \(steps.count)")
                .font(Theme.font(14))
                .foregroundStyle(Theme.mutedText)
                .padding(.bottom, 20)

            progressBar.padding(.bottom, 28)

            RippleCard(cornerRadius: Theme.sheetRadius, padding: 28) {
                Text(currentStep?.text ?? "")
                    .font(Theme.font(20, .medium))
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .lineSpacing(4)
            }
            .padding(.bottom, 24)

            actions
        }
        .onAppear { speakCurrentStep() }
        .onChange(of: stepIndex) { speakCurrentStep() }
    }

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(steps.indices, id: \.self) { index in
                Capsule()
                    .fill(index <= stepIndex ? Theme.sage : Theme.border)
                    .opacity(index < stepIndex ? 0.4 : 1)
                    .frame(height: 6)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: advance) {
                Text(isLastStep ? "All done!" : "Done — next step")
            }
            .buttonStyle(ProminentButtonStyle())

            Button { speakCurrentStep() } label: { Text("Say that again") }
                .buttonStyle(SoftButtonStyle())

            if stepIndex > 0 {
                Button { stepIndex -= 1 } label: { Text("Go back one step") }
                    .buttonStyle(SoftButtonStyle(fill: .clear, foreground: Theme.mutedText))
            }
        }
    }

    private func advance() {
        if isLastStep {
            logCompletion()
            onExit()
        } else {
            stepIndex += 1
        }
    }

    private func speakCurrentStep() {
        guard let step = currentStep else { return }
        speech.speak(step.text)
    }

    /// A finished task writes a self-reported completion — the record the
    /// reassuring "Done today" view reads back. A memory record, not a guarantee.
    private func logCompletion() {
        context.insert(LogEntry(label: task.title, taskID: task.id, source: .person))
        try? context.save()
    }
}
