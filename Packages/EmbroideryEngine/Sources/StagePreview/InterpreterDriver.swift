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
    ///
    /// `makeStream` rather than the closure-based initializer, because the closure
    /// form cannot hand the `Task` back out for `RunSession.stop()` to cancel.
    ///
    /// `Task.detached`, **not** `Task {}`: this is called from `@MainActor`, and a
    /// plain `Task {}` inherits the enclosing actor's isolation — which would run a
    /// 24 008-stitch tick on the main actor and drop frames doing it. `detached`
    /// removes the ambiguity rather than relying on a reader noticing it.
    public func start(_ interpreter: Interpreter) -> RunSession {
        let (stream, continuation) = AsyncStream<RunUpdate>.makeStream(
            bufferingPolicy: .unbounded
        )
        let budget = budget
        let pacing = pacing

        let task = Task.detached(priority: .userInitiated) {
            // Every exit path finishes the stream, including the cancellation path, so
            // a consumer's `for await` always terminates.
            defer { continuation.finish() }
            await Self.produce(interpreter, into: continuation, budget: budget, pacing: pacing)
        }

        // Assigned after the fact, which is safe: if the stream has already
        // terminated the handler runs immediately. It cancels the **producer** — a
        // consumer that walks away (a view model reset, a window teardown) must stop
        // the interpreter rather than leave it running to the stitch cap.
        continuation.onTermination = { _ in task.cancel() }

        return RunSession(updates: stream, task: task)
    }

    /// The producer loop: one `RunUpdate` per frame until the run ends.
    ///
    /// `static` so the detached task captures no `self`, and free of any reference to
    /// the enclosing value's storage — everything it needs arrives as a parameter.
    private static func produce(
        _ interpreter: Interpreter,
        into continuation: AsyncStream<RunUpdate>.Continuation,
        budget: RunBudget,
        pacing: any RunPacing
    ) async {
        var run = interpreter
        var carriedNeedle: PreviewNeedle?
        var stitchesThisRun = 0

        while true {
            // Checked once per frame, before any `step()`. A single check is what
            // keeps the terminal update unconditional — see `RunPacing`.
            if Task.isCancelled {
                continuation.yield(terminal(.stoppedByUser, of: run, batch: .empty))
                return
            }

            let frame = runFrame(&run, carrying: carriedNeedle, budget: budget)
            carriedNeedle = frame.batch.needle
            stitchesThisRun += frame.batch.stitches.count

            // Precedence is explicit: on the frame where a program both finishes and
            // crosses the cap, finishing wins. A design that completed is not one that
            // was cut short, and telling the user otherwise would be wrong in the one
            // direction that matters.
            //
            // `run.isFinished` rather than spending another `step()` to discover
            // `.finished`: that extra tick is what would make a `wait(1)` occupy 61
            // frames instead of 60.
            let reason: RunCompletion? = if frame.programFinished || run.isFinished {
                .programFinished
            } else if stitchesThisRun >= budget.maxStitchesPerRun {
                .stitchLimitReached
            } else {
                nil
            }

            guard let reason else {
                continuation.yield(RunUpdate(batch: frame.batch))
                await pacing.waitForNextFrame()
                continue
            }
            continuation.yield(terminal(reason, of: run, batch: frame.batch))
            return
        }
    }

    /// One frame's ticks, and whether the program finished during them.
    private static func runFrame(
        _ run: inout Interpreter, carrying needle: PreviewNeedle?, budget: RunBudget
    ) -> FrameOutcome {
        var batch = RunBatch(needle: needle)
        var ticks = 0

        while ticks < budget.ticksPerFrame {
            // The stitch budget is checked **between** ticks, never before the first
            // one: `step()` returns one atomic `[InterpreterEvent]`, so the opening
            // tick of a frame always runs whole however large it is. This is also what
            // stops a `maxStitchesPerFrame` of 0 from spinning out empty frames.
            if ticks > 0, batch.stitches.count >= budget.maxStitchesPerFrame {
                break
            }
            switch run.step() {
            case .finished:
                return FrameOutcome(batch: batch, programFinished: true)
            case let .ticked(events):
                batch.absorb(RunBatch.reducing(events, from: batch.needle))
                ticks += 1
            }
        }
        return FrameOutcome(batch: batch, programFinished: false)
    }

    /// The terminal update. Funnelled through one function so that no completion path
    /// can be added later that forgets to carry `assembledStream()`.
    private static func terminal(
        _ reason: RunCompletion, of run: Interpreter, batch: RunBatch
    ) -> RunUpdate {
        RunUpdate(
            batch: batch,
            termination: RunTermination(reason: reason, exportModel: run.assembledStream())
        )
    }

    private struct FrameOutcome {
        var batch: RunBatch
        var programFinished: Bool
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
