/// What the app's haptic map can play (Release readiness D3, ADR-052): a selection tick on
/// brick add and reorder drop, success on a completed run whose export can be shared, and an
/// error on each failed export attempt. Nothing else plays a haptic.
///
/// Plain values, no SwiftUI: `AppModel` holds the pulse, and its file stays free of view
/// types. The mapping to `SensoryFeedback` lives in `HapticKind+SensoryFeedback.swift`.
enum HapticKind: Equatable, Sendable {
    case selection
    case success
    case error
}

/// One haptic to play. The serial makes every pulse a new value, so two pulses of the same
/// kind in a row are two changes of the `.sensoryFeedback` trigger, not one.
struct HapticPulse: Equatable, Sendable {
    let kind: HapticKind
    let serial: Int
}
