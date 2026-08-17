/// How fast the driver produces frames — injected rather than chosen, so a test
/// drains a whole run deterministically without sleeping (ADR-006 pattern 2).
///
/// `Sendable` is load-bearing, not decorative: the driver captures its pacing
/// into a detached `Task`.
public protocol RunPacing: Sendable {
    /// Suspends until the next frame should be produced, **or until the task is
    /// cancelled, whichever comes first**.
    ///
    /// **The cancellation half is a requirement, not a courtesy, and the run's central
    /// guarantee depends on it.** The producer observes cancellation between frames, so an
    /// implementation that stays suspended through a cancellation parks the producer
    /// permanently: `stop()` then never reaches the next check, never emits
    /// `.stoppedByUser`, and the export model the story promises after a stop is never
    /// produced at all. Codex round 2 found exactly that hole — via this package's own
    /// gated test double, which had been written to ignore cancellation deliberately.
    ///
    /// `Task.sleep` satisfies this for free (it throws on cancellation); a hand-rolled
    /// gate must use `withTaskCancellationHandler` or equivalent. The requirement is stated
    /// here because it cannot be enforced by the type — see
    /// `InterpreterDriverTests.aRunStoppedWhileParkedInPacingStillTerminates`, which is the
    /// contract's test.
    ///
    /// **Non-throwing on purpose.** A `throws` requirement would give cancellation two
    /// paths — a thrown `CancellationError` and the driver's own `Task.isCancelled` check —
    /// and two paths means one of them eventually skips the terminal update. An
    /// implementation swallows its own cancellation error and lets the driver's single check
    /// own the decision.
    func waitForNextFrame() async
}

/// Sleeps a frame. The duration is supplied by the app rather than baked in here,
/// because it must be derived from the same number as `InterpreterClock.tickDelta`
/// — see `AppRunClock`, where both come from `1.0 / 60.0`. A frame duration that
/// disagreed with the tick delta would make `wait(1)` stop reading as one second.
public struct DisplayRunPacing: RunPacing {
    public let frameDuration: Duration

    public init(frameDuration: Duration) {
        self.frameDuration = frameDuration
    }

    public func waitForNextFrame() async {
        // `try?`, not `try`: see the protocol requirement. Cancellation is the
        // driver's to observe, and it does so at the top of the next frame.
        try? await Task.sleep(for: frameDuration)
    }
}

/// Produces frames as fast as the consumer takes them — what every test uses, so
/// a whole run drains with no wall-clock and no flakiness.
public struct ImmediateRunPacing: RunPacing {
    public init() {}

    /// **`Task.yield()` rather than an empty body, and this is not cosmetic.** An
    /// `async` function that never suspends does not give up the cooperative
    /// thread, so a `forever` program under immediate pacing would monopolise it
    /// and starve the consumer until the stitch cap — a hang that looks like a
    /// deadlock and is nothing of the kind.
    public func waitForNextFrame() async {
        await Task.yield()
    }
}
