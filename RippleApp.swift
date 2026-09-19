import SwiftUI
import SwiftData

@main
struct RippleApp: App {
    /// Shared services live for the whole app: one voice, one phrasing engine.
    @State private var speech = SpeechManager()
    @State private var phrasing = PhrasingEngine()

    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Schema(RippleSchema.all))
        } catch {
            fatalError("Could not create the on-device store: \(error)")
        }
        SampleData.seedIfNeeded(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(speech)
                .environment(phrasing)
        }
        .modelContainer(container)
    }
}
