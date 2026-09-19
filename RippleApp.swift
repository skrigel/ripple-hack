import SwiftUI
import SwiftData

@main
struct RippleApp: App {
    /// One voice, one ear, and the two engines that may hold a model —
    /// comprehension facing in, phrasing out. See `RippleServices`.
    @State private var services = RippleServices()

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
                .environment(services)
        }
        .modelContainer(container)
    }
}
