import SwiftUI

/// The caregiver acting as the current persona, threaded through the
/// environment so every screen and sheet can gate edit affordances on it
/// without re-resolving `PersonaSession.selectedCaregiverID` against the
/// people query themselves. `nil` means the patient's own view.
private struct CurrentCaregiverKey: EnvironmentKey {
    static let defaultValue: Person? = nil
}

extension EnvironmentValues {
    var currentCaregiver: Person? {
        get { self[CurrentCaregiverKey.self] }
        set { self[CurrentCaregiverKey.self] = newValue }
    }
}
