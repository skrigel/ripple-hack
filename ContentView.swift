import SwiftUI
import SwiftData

/// The three primary destinations in the bottom navigation.
enum AppTab: String, CaseIterable, Identifiable {
    case home, past, people

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "Today"
        case .past: "Past events"
        case .people: "People"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "clock"
        case .past: "bubble.left.and.text.bubble.right"
        case .people: "person.2"
        }
    }
}

struct ContentView: View {
    @Environment(RippleServices.self) private var services
    @Query private var facts: [GroundingFacts]
    @Query(sort: \Person.sortOrder) private var people: [Person]

    @State private var tab: AppTab = .home
    @State private var showingAssistant = false
    @State private var showingPersonaPicker = false
    @State private var showingPatientInfoEdit = false

    private var userName: String { facts.first?.userName ?? "there" }

    /// The caregiver currently acting as the persona, resolved from
    /// `PersonaSession`'s stored id against the live people query. `nil`
    /// means the patient's own, unchanged view.
    private var currentCaregiver: Person? {
        people.first { $0.id == services.persona.selectedCaregiverID }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    selectedScreen
                        .padding(.top, 8)
                        .padding(.bottom, 150) // clear the nav + floating button
                }
                .scrollIndicators(.hidden)
            }

            navigationBar
            assistantButton.padding(.bottom, 92)
        }
        // Published once here so every screen and sheet can gate edit
        // affordances on it without re-resolving the persona themselves.
        .environment(\.currentCaregiver, currentCaregiver)
        .sheet(isPresented: $showingAssistant) {
            AssistantSheet()
                // A sheet is built outside this view's tree, so the services
                // are handed over explicitly rather than assumed to be
                // inherited. Same instances — this is a re-injection, not a
                // second set.
                .environment(services)
                .presentationDetents([.fraction(0.8)])
                .presentationCornerRadius(Theme.sheetRadius)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPersonaPicker) {
            PersonaPickerSheet()
                .environment(services)
                .presentationDetents([.fraction(0.7)])
                .presentationCornerRadius(Theme.sheetRadius)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPatientInfoEdit) {
            PatientInfoEditView()
                .presentationCornerRadius(Theme.sheetRadius)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(GroundingService.headerDate(at: .now))
                    .font(Theme.font(12, .medium))
                    .foregroundStyle(Theme.mutedText)
                Text(GroundingService.greeting(for: userName, at: .now))
                    .font(Theme.font(18, .semibold))
                    .foregroundStyle(Theme.foreground)
            }
            Spacer()
            if currentCaregiver != nil {
                Button { showingPatientInfoEdit = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.mutedText)
                        .frame(width: 36, height: 36)
                        .background(Theme.muted, in: Circle())
                }
                .accessibilityLabel("Edit patient info")
            }
            personaButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var personaButton: some View {
        Button { showingPersonaPicker = true } label: {
            if let caregiver = currentCaregiver {
                Text(caregiver.initial)
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(caregiver.avatarTint)
                    .frame(width: 36, height: 36)
                    .background(caregiver.avatarBackground, in: Circle())
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.mutedText)
                    .frame(width: 36, height: 36)
            }
        }
        .accessibilityLabel(currentCaregiver.map { "Signed in as \($0.name)" } ?? "Select who's using Ripple")
    }

    // MARK: - Screens

    @ViewBuilder
    private var selectedScreen: some View {
        switch tab {
        case .home: HomeView()
        case .past: PastEventsView()
        case .people: PeopleView()
        }
    }

    // MARK: - Bottom navigation

    private var navigationBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { item in
                let isActive = item == tab
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 21, weight: .regular))
                        Text(item.label).font(Theme.font(11, .medium))
                    }
                    .foregroundStyle(isActive ? Theme.sage : Theme.mutedText)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(item.label)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(alignment: .top) {
            Theme.background.opacity(0.92)
                .background(.ultraThinMaterial)
                .overlay(Theme.border.frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Floating assistant button

    private var assistantButton: some View {
        Button { showingAssistant = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill").font(.system(size: 14, weight: .semibold))
                Text("Ask me anything").font(Theme.font(15, .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(Theme.sage, in: Capsule())
            .shadow(color: Theme.sage.opacity(0.45), radius: 12, y: 4)
        }
        .accessibilityLabel("Open assistant")
    }
}

#Preview {
    ContentView()
        .environment(RippleServices())
        .modelContainer(previewContainer)
}

/// An in-memory, seeded container so previews render with the design's content.
@MainActor
let previewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: Schema(RippleSchema.all),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    SampleData.seedIfNeeded(container.mainContext)
    return container
}()
