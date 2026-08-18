import SwiftUI

/// What Reduce Motion means on the stage.
///
/// **This is the "single gate" `StageTransportRow` asks US-307 to reuse — but the thing that
/// can actually be shared is the policy, not the environment read.** Taken literally, reusing
/// one read means passing a `Bool` down as a parameter, which decouples the value from the
/// environment SwiftUI resolves for the child: a preview, an `.environment(...)` override or
/// a future host injecting the setting would move one view and not the other. Two views
/// reading `\.accessibilityReduceMotion` is per-view resolution working as designed.
///
/// What *would* have been duplication is the decision about what the setting suppresses, and
/// there is exactly one of it, here. Being a pure function it is also assertable — `Animation`
/// is `Equatable` — where the same decision spelled inline in two view bodies could only be
/// checked on a device.
///
/// **Direct manipulation is deliberately not gated.** Reduce Motion is about motion the *app*
/// starts; suppressing a pinch or a pan would break the gesture rather than calm it. So only
/// the double-tap reset passes through here.
enum StageMotion {
    /// The double-tap-to-fit transition. `nil` is a legal `Animation?` meaning "instantly",
    /// so one `withAnimation` call site serves both branches without a branch of its own.
    static func fitAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.15)
    }

    /// The transport button's play/stop symbol morph — US-306's, moved here unchanged so the
    /// two decisions live together. The symbol still *changes* under Reduce Motion; it just
    /// does not animate.
    static func symbolTransition(reduceMotion: Bool) -> ContentTransition {
        reduceMotion ? .identity : .symbolEffect(.replace)
    }
}
