import Foundation
import Observation

/// Which `Person` is currently holding the phone, if any.
///
/// This is identity, not authentication — a caregiver picks their own name
/// from a list, nothing is verified. Persisted in `UserDefaults` rather than
/// SwiftData: it's a device-local "who's using this right now" setting, not
/// patient data, and carries no `lastModified`/sync semantics of its own.
@Observable
@MainActor
final class PersonaSession {
    private static let key = "ripple.selectedCaregiverID"

    var selectedCaregiverID: UUID? {
        didSet {
            UserDefaults.standard.set(selectedCaregiverID?.uuidString, forKey: Self.key)
        }
    }

    init() {
        selectedCaregiverID = UserDefaults.standard.string(forKey: Self.key).flatMap(UUID.init)
    }
}
