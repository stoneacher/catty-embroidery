import SwiftUI

extension HapticKind {
    /// The system feedback each kind plays. `.sensoryFeedback` honours the user's system
    /// haptics setting, so nothing here needs to check it.
    var feedback: SensoryFeedback {
        switch self {
        case .selection: .selection
        case .success: .success
        case .error: .error
        }
    }
}
