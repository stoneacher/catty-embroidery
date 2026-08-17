/// The three independent limits a run is governed by.
///
/// They are three rather than two because two of them are frequently confused,
/// and confusing them produces a design that either stutters or never stops:
/// `maxStitchesPerFrame` **never terminates a run**, and `maxStitchesPerRun`
/// **never throttles a frame**.
public struct RunBudget: Hashable, Sendable {
    /// How many `step()` calls one frame may make. Defaults to 1, which is
    /// ADR-018's coupling: one logical tick per displayed frame, so a `wait(1)`
    /// brick at `tickDelta = 1/60` occupies 60 frames and reads as one second.
    public let ticksPerFrame: Int

    /// A stitch budget checked **between** ticks: once a frame has accumulated
    /// this many stitches, it runs no further tick and yields what it has.
    ///
    /// **It cannot bound a batch, and at the default `ticksPerFrame = 1` it is
    /// unreachable by construction.** `step()` returns one atomic
    /// `[InterpreterEvent]` — it loops every runnable thread and accumulates all
    /// of their events into a single array (`Interpreter.swift:79`) — so the
    /// driver cannot split it, and the first tick of a frame always runs whole
    /// however large it is. Measured: 6 001 stitches from one thread
    /// (`tripleStitch` + `moveNSteps(2000)`), and **24 008 from eight concurrent
    /// scripts in the same tick**, since each spends tick 0 activating its
    /// pattern and they all move on tick 1.
    ///
    /// So this exists for when `ticksPerFrame` is *raised*, exactly as US-306's
    /// criterion says. Saying so here matters because a reader who assumes it
    /// throttles today would size it against a frame time it does not control.
    public let maxStitchesPerFrame: Int

    /// The whole-run stitch cap, and the only producer of
    /// `RunCompletion.stitchLimitReached`.
    ///
    /// A `forever` program never terminates on its own, so without this the app
    /// would rely on the user to stop every run. Not a hard *tick* cap: a
    /// long-waiting program is not a runaway one, and ticks are a poor proxy for
    /// the thing that actually grows without bound.
    ///
    /// It counts **stitch events** — display-list entries — not export records.
    /// ADR-021's divergences make those different numbers, and events are what
    /// memory scales with.
    ///
    /// 200 000 is bracketed on both sides rather than picked: it must clear
    /// US-309's 50 000-stitch exit criterion by a wide margin (4×), and sit well
    /// under the DST `ST` header field's 999 999 ceiling, which US-211 turns from
    /// a trap into a thrown error.
    public let maxStitchesPerRun: Int

    /// **Every axis is clamped to at least 1, and that is a correctness fix rather than
    /// tidiness** (`swift-code-reviewer`). `ticksPerFrame: 0` ran zero ticks per frame, so no
    /// budget axis could ever fire — `run.isFinished` stayed false because no `step()` was
    /// made, and `stitchesThisRun` stayed 0 — producing a run that yielded empty frames
    /// forever and delivered **zero** terminals. That was the only path found that breaks the
    /// terminal guarantee ADR-027 makes structural everywhere else. A negative
    /// `maxStitchesPerRun` is the mirror case: `0 >= -1` terminated every run on frame 1.
    ///
    /// Clamped here rather than guarded at the use site because this type is `public` and
    /// ADR-027 hands it to US-309 as a tunable, so the invalid value must not be
    /// constructible in the first place.
    public init(
        ticksPerFrame: Int = 1,
        maxStitchesPerFrame: Int = 2000,
        maxStitchesPerRun: Int = 200_000
    ) {
        self.ticksPerFrame = Swift.max(1, ticksPerFrame)
        self.maxStitchesPerFrame = Swift.max(1, maxStitchesPerFrame)
        self.maxStitchesPerRun = Swift.max(1, maxStitchesPerRun)
    }

    /// What the app runs with: one tick per displayed frame (ADR-018).
    public static let display = RunBudget()
}
