import SwiftUI
import SwiftData

/// The three primary destinations in the bottom navigation.
enum AppTab: String, CaseIterable, Identifiable {
    case home, tasks, people

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "Today"
        case .tasks: "Tasks"
        case .people: "People"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "clock"
        case .tasks: "checklist"
        case .people: "person.2"
        }
    }
}

struct ContentView: View {
    @Query private var facts: [GroundingFacts]

    @State private var tab: AppTab = .home
    @State private var showingNightMode = false
    @State private var showingAssistant = false

    private var userName: String { facts.first?.userName ?? "there" }

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
        .fullScreenCover(isPresented: $showingNightMode) {
            NightModeView { showingNightMode = false }
        }
        .sheet(isPresented: $showingAssistant) {
            AssistantSheet()
                .presentationDetents([.fraction(0.8)])
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
            Button { showingNightMode = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "moon.fill").font(.system(size: 10))
                    Text("Night").font(Theme.font(12, .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.foreground, in: Capsule())
                .foregroundStyle(Theme.background)
            }
            .accessibilityLabel("Switch to night mode")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Screens

    @ViewBuilder
    private var selectedScreen: some View {
        switch tab {
        case .home: HomeView()
        case .tasks: TaskListView()
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
        .environment(SpeechManager())
        .environment(PhrasingEngine())
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
