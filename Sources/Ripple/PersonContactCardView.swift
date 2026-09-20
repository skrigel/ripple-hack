import SwiftUI
import SwiftData

/// Add or edit a person — laid out like an iPhone contact card. Used for
/// three cases: creating a caregiver (from the persona picker's "+"),
/// creating an ordinary person (from People, caregiver mode), and editing
/// any existing person. The caller decides which case via `mode`.
struct PersonContactCardView: View {
    enum Mode {
        /// A brand-new person. `presetCaregiver` is `true` only when this
        /// card was opened to elevate/add a caregiver from the persona picker.
        case create(presetCaregiver: Bool)
        case edit(Person)
    }

    let mode: Mode
    /// Called after a new person is inserted, so the caller (e.g. the persona
    /// picker) can select them as the active persona. Not called on edit.
    var onCreate: ((Person) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(RippleServices.self) private var services
    @Query private var allPeople: [Person]

    @State private var name: String
    @State private var relationship: String
    @State private var phone: String
    @State private var recentContext: String
    @State private var memories: [String]
    @State private var voiceClipData: Data?
    @State private var newMemory = ""

    /// Identifies this sheet's clip while it is being previewed, before there
    /// is a saved `Person.id` to key playback on.
    @State private var draftID = UUID()

    init(mode: Mode, onCreate: ((Person) -> Void)? = nil) {
        self.mode = mode
        self.onCreate = onCreate
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _relationship = State(initialValue: "")
            _phone = State(initialValue: "")
            _recentContext = State(initialValue: "")
            _memories = State(initialValue: [])
            _voiceClipData = State(initialValue: nil)
        case .edit(let person):
            _name = State(initialValue: person.name)
            _relationship = State(initialValue: person.relationship)
            _phone = State(initialValue: person.phone)
            _recentContext = State(initialValue: person.recentContext)
            _memories = State(initialValue: person.memories)
            _voiceClipData = State(initialValue: person.voiceClipData)
        }
    }

    private var isEditing: Bool { if case .edit = mode { true } else { false } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 24) {
                    avatar
                    fields
                    voiceSection
                    memoriesSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.background)
        .onChange(of: services.voiceClips.recordedClip) { _, clip in
            guard clip != nil else { return }
            voiceClipData = services.voiceClips.takeRecordedClip()
        }
        .onDisappear {
            services.voiceClips.stopRecording()
            services.voiceClips.stopPlayback()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(Theme.font(15, .medium))
                .foregroundStyle(Theme.mutedText)
            Spacer()
            Text(isEditing ? "Edit person" : "New person")
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

    // MARK: - Avatar

    private var avatar: some View {
        Text(trimmedName.isEmpty ? "?" : String(trimmedName.prefix(1)).uppercased())
            .font(Theme.font(32, .semibold))
            .foregroundStyle(avatarTint)
            .frame(width: 88, height: 88)
            .background(avatarBackground, in: Circle())
    }

    private var avatarTint: Color {
        if case .edit(let person) = mode { person.avatarTint } else { Theme.sage }
    }

    private var avatarBackground: Color {
        if case .edit(let person) = mode { person.avatarBackground } else { Theme.sageSoft }
    }

    // MARK: - Fields

    private var fields: some View {
        RippleCard {
            VStack(spacing: 14) {
                labeledField("Name", text: $name)
                Divider().overlay(Theme.border)
                labeledField("Relationship", text: $relationship, placeholder: "Your daughter")
                Divider().overlay(Theme.border)
                labeledField("Phone", text: $phone, placeholder: "+1 555 010 0100")
                    .keyboardType(.phonePad)
                Divider().overlay(Theme.border)
                labeledField("Recent context", text: $recentContext, placeholder: "Visited last Sunday")
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

    // MARK: - Voice clip

    /// A few seconds of the real voice, recorded by whoever is holding the
    /// phone. Played back untouched — the point is that it is *not* the
    /// synthesizer, so nothing here rewrites, trims, or interprets it.
    private var voiceSection: some View {
        RippleCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Voice clip")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.secondaryText)

                Text("A few seconds of \(possessiveName) own voice — a hello to play back alongside the name.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.mutedText)

                if services.voiceClips.isRecording {
                    recordingControls
                } else if let voiceClipData {
                    clipControls(voiceClipData)
                } else {
                    recordButton
                }
            }
        }
    }

    private var possessiveName: String {
        trimmedName.isEmpty ? "their" : "\(trimmedName)'s"
    }

    private var isPreviewing: Bool { services.voiceClips.playingID == draftID }

    private var recordButton: some View {
        Button { beginRecording() } label: {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill").font(.system(size: 13, weight: .semibold))
                Text("Record a clip")
            }
        }
        .buttonStyle(SoftButtonStyle())
    }

    private var recordingControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.coral)
                    .frame(width: 10, height: 10)
                if let startedAt = services.voiceClips.recordingStartedAt {
                    // The counter ticks in the view rather than the service, so
                    // nothing has to own a timer just to redraw a label.
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(elapsed(from: startedAt, to: context.date))
                            .font(Theme.font(15, .medium).monospacedDigit())
                            .foregroundStyle(Theme.foreground)
                    }
                }
                Spacer()
                Text("Stops at \(Int(VoiceClipService.maximumDuration))s")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.mutedText)
            }

            Button("Stop recording") { services.voiceClips.stopRecording() }
                .buttonStyle(ProminentButtonStyle(fill: Theme.coral))
        }
    }

    private func clipControls(_ data: Data) -> some View {
        VStack(spacing: 10) {
            Button {
                services.voiceClips.play(data, id: draftID)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isPreviewing ? "Stop" : "Play clip")
                }
            }
            .buttonStyle(SoftButtonStyle(fill: Theme.sageSoft, foreground: Theme.sage))

            HStack {
                Button("Record again") { beginRecording() }
                    .font(Theme.font(13, .medium))
                    .foregroundStyle(Theme.sage)
                Spacer()
                Button("Remove clip") {
                    services.voiceClips.stopPlayback()
                    voiceClipData = nil
                }
                .font(Theme.font(13, .medium))
                .foregroundStyle(Theme.coral)
            }
        }
    }

    private func beginRecording() {
        Task { await services.voiceClips.startRecording() }
    }

    private func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Memories

    private var memoriesSection: some View {
        RippleCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Shared memories")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.secondaryText)

                ForEach(memories, id: \.self) { memory in
                    HStack(alignment: .top, spacing: 8) {
                        Text(memory)
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            memories.removeAll { $0 == memory }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.mutedText)
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("Add a memory", text: $newMemory)
                        .font(Theme.font(14))
                    Button {
                        let trimmed = newMemory.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        memories.append(trimmed)
                        newMemory = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Theme.sage)
                    }
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }
        switch mode {
        case .create(let presetCaregiver):
            let palette = AvatarPalette.next(excludingCountOf: allPeople.count)
            let person = Person(
                name: trimmedName,
                relationship: relationship,
                recentContext: recentContext,
                phone: phone,
                memories: memories,
                voiceClipData: voiceClipData,
                avatarBackgroundHex: palette.background,
                avatarTintHex: palette.tint,
                isCaregiver: presetCaregiver,
                sortOrder: (allPeople.map(\.sortOrder).max() ?? -1) + 1
            )
            modelContext.insert(person)
            onCreate?(person)
        case .edit(let person):
            person.name = trimmedName
            person.relationship = relationship
            person.phone = phone
            person.recentContext = recentContext
            person.memories = memories
            person.voiceClipData = voiceClipData
            person.lastModified = .now
        }
        dismiss()
    }
}

/// A small rotation of the design's avatar tints, so new people don't all
/// land on the same color.
enum AvatarPalette {
    private static let pairs: [(background: UInt, tint: UInt)] = [
        (0xEAF3F0, 0x7BA79B),
        (0xF5F0E8, 0xC5B89A),
        (0xF0EEF5, 0xA49BB7),
        (0xF5EFEE, 0xB79B9B),
    ]

    static func next(excludingCountOf count: Int) -> (background: UInt, tint: UInt) {
        pairs[count % pairs.count]
    }
}

extension PersonContactCardView.Mode: Identifiable {
    var id: String {
        switch self {
        case .create(let presetCaregiver): "create-\(presetCaregiver)"
        case .edit(let person): person.id.uuidString
        }
    }
}

#Preview {
    PersonContactCardView(mode: .create(presetCaregiver: false))
        .modelContainer(previewContainer)
        .environment(RippleServices())
}
