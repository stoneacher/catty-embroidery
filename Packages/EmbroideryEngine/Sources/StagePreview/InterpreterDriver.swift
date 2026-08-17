import Interpreter

/// Runs an `Interpreter` off the main actor and yields one `RunUpdate` per frame.
///
/// It takes an `Interpreter`, **not** a `Program`. Two reasons, both structural:
/// it keeps `StagePreview` off `ProgramModel` (ADR-022's dependency line stays
/// where it is, and `Package.swift` needs no change), and it puts the
/// "`reset()` is one assignment because the interpreter is a value type"
/// criterion where it belongs — the caller builds a fresh `Interpreter` per play,
/// which is the whole of the reset. Contrast Catroid's three separate resets
/// (`embroideryPatternManager.clear()` twice, `resetDrawingState()`,
/// `resetEmbroideryThreadColor()`) and Catty's reload-from-disk.
public struct InterpreterDriver: Sendable {
    public let budget: RunBudget
    private let pacing: any RunPacing

    public init(pacing: some RunPacing, budget: RunBudget = .display) {
        self.pacing = pacing
        self.budget = budget
    }

    /// Starts the run and returns the session that feeds and stops it.
    public func start(_ interpreter: Interpreter) -> RunSession {
        // Red-phase stub: the surface exists so the tests compile and fail on
        // their assertions. Green phase implements the producer loop.
        let (stream, continuation) = AsyncStream<RunUpdate>.makeStream(
            bufferingPolicy: .unbounded
        )
        _ = interpreter
        _ = pacing
        continuation.finish()
        return RunSession(updates: stream, task: Task {})
    }
}

/// A running run: the updates to consume, and the way to stop it.
///
/// **`stop()` cancels the producer only, never the consumer — and getting this
/// backwards silently breaks the story's central criterion.**
/// `AsyncStream.Iterator.next()` returns `nil` when the *consuming* task is
/// cancelled. So a `stop()` that cancelled the consumer (the natural reading of
/// "the run `Task` is cancellable", and what cancelling a `for await` task or a
/// `.task {}` does) would let the producer build the terminal update carrying
/// `assembledStream()` and then have it **never delivered** — export-after-stop
/// would fail exactly the way Catty's does, while every unit test that inspects
/// the producer in isolation still passed.
///
/// The consumer therefore keeps draining until the stream finishes on its own,
/// which it does one element after `stop()`.
public struct RunSession: Sendable {
    /// Single-consumer, unbounded buffering.
    ///
    /// **Never `.bufferingNewest`.** Dropping an update would lose stitches
    /// permanently from an append-only display list — there is no later frame
    /// that re-sends them, because a `RunBatch` is a delta and not an
    /// accumulator.
    ///
    /// The usual justification for unbounded — "the producer self-paces" — is
    /// true under `DisplayRunPacing` and **false under `ImmediateRunPacing`**,
    /// which every test uses: there the producer races ahead and the only bound
    /// is `RunBudget.maxStitchesPerRun`. That is affordable (200 000
    /// `PreviewStitch` ≈ 5 MB) but it is a different argument, and the criterion
    /// is worth stating in the form that is actually true.
    public let updates: AsyncStream<RunUpdate>

    private let task: Task<Void, Never>

    init(updates: AsyncStream<RunUpdate>, task: Task<Void, Never>) {
        self.updates = updates
        self.task = task
    }

    /// Asks the run to stop. The terminal update — carrying
    /// `RunCompletion.stoppedByUser` and the export model — is still produced and
    /// still delivered.
    public func stop() {
        task.cancel()
    }
}
