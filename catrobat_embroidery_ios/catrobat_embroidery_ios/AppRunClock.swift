import Interpreter

/// The clock the app runs programs with.
///
/// ADR-018 requires only that `tickDelta > 0` — the interpreter is deliberately
/// wall-clock-free, so *what a tick means* is the app's decision, not the
/// engine's. M3 pins one tick per displayed frame: at 1/60 s a `wait(1)` brick
/// occupies 60 ticks and reads as one second on screen, with no wall-clock
/// anywhere in the package.
///
/// It lives here, in app code, rather than inside US-306's driver because the
/// coupling is a *product* decision that outlives any one view model, and
/// because a constant no test can reach is a comment pretending to be code.
/// `nonisolated` deliberately, and it is not cosmetic. The app target builds
/// with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (ADR-006's shape), so
/// without this keyword `preview` is main-actor isolated and
/// "main actor-isolated static property 'preview' can not be referenced from a
/// nonisolated context" is what US-306 gets the moment it steps the interpreter
/// off the main actor — which it must, since one `step()` can emit millions of
/// events. `InterpreterClock` is a `Sendable` value type, so there is nothing
/// to protect. Verified by compiling the isolated version against the app
/// target rather than reasoned about (in-loop review, 2026-08-11).
nonisolated enum AppRunClock {
    /// One tick per frame at 60 Hz.
    ///
    /// Note what this does **not** promise: the interpreter is not paced by it.
    /// A single `step()` can emit tens of thousands of stitches (one thread's
    /// worst case is 3,000,002 events), so US-306's driver governs how many
    /// ticks a frame gets — the frame budget bounds the tick count, not the
    /// batch size.
    static let preview = InterpreterClock(tickDelta: 1.0 / 60.0)
}
