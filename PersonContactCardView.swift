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
    @Query private var allPeople: [Person]

    @State private var name: String
    @State private var relationship: String
    @State private var phone: String
    @State private var recentContext: String
    @State private var memories: [String]
    @State private var newMemory = ""

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
        case .edit(let person):
            _name = State(initialValue: person.name)
            _relationship = State(initialValue: person.relationship)
            _phone = State(initialValue: person.phone)
            _recentContext = State(initialValue: person.recentContext)
            _memories = State(initialValue: person.memories)
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
                    memoriesSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.background)
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
}
