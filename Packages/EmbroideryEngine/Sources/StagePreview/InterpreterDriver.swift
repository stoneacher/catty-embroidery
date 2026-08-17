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

        // Assigned after the task is created, which is safe — but **not** for the reason an
        // earlier version of this comment gave ("if the stream has already terminated the
        // handler runs immediately"). Measured: a handler assigned after `finish()` is stored
        // and invoked with `.cancelled` when the stream *storage* deallocates, not at
        // assignment (`swift-code-reviewer`). It is safe because the handler's only action is
        // `task.cancel()`, and a stream that has already terminated implies the producer has
        // already returned, so there is nothing left to cancel.
        //
        // It cancels the **producer** — a consumer that walks away (a view model reset, a
        // window teardown) must stop the interpreter rather than leave it running to the
        // stitch cap.
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
            // Checked before any `step()`, so a stop that lands while the producer is parked
            // in pacing costs no further work. There is a **second** check after the frame —
            // see `completionReason` — because this one alone lost a stop to the stitch cap.
            // Both are `Task.isCancelled` rather than a thrown error, which is what keeps
            // cancellation to a single mechanism (see `RunPacing`).
            if Task.isCancelled {
                continuation.yield(terminal(.stoppedByUser, of: run, batch: .empty))
                return
            }

            let frame = runFrame(&run, carrying: carriedNeedle, budget: budget)
            carriedNeedle = frame.batch.needle
            stitchesThisRun += frame.batch.stitches.count

            // **Cancellation is re-checked here, after the frame, not only at the top of
            // the loop.** A `stop()` landing *during* a long frame was otherwise lost to the
            // cap: the frame would finish, cross `maxStitchesPerRun`, and report
            // `.stitchLimitReached` to a user who had pressed Stop (Codex round 1). See
            // `completionReason` for why cancellation wins over the cap but not over a
            // genuine completion.
            //
            // `run.isFinished` rather than spending another `step()` to discover
            // `.finished`: that extra tick is what would make a `wait(1)` occupy 61
            // frames instead of 60.
            let reason = completionReason(
                programFinished: frame.programFinished,
                interpreterIsFinished: run.isFinished,
                cancelled: Task.isCancelled,
                stitchesThisRun: stitchesThisRun,
                budget: budget
            )

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

    /// Which completion reason wins when more than one is true on the same frame.
    ///
    /// **A pure function so the precedence is a table a test can enumerate**, rather than an
    /// `if`-chain inside the producer loop that only an interleaving could exercise. Codex
    /// round 1 found the ordering wrong for a `stop()` that lands *during* a long frame: the
    /// loop checked cancellation only at the top, so a frame that also crossed the stitch cap
    /// reported `.stitchLimitReached` and the user who pressed Stop was told the preview had
    /// hit a limit.
    ///
    /// The precedence is **completion → cancellation → cap**, and the middle term is the fix.
    /// Cancellation deliberately does *not* win over natural completion, which is a narrowing
    /// of what that finding implied: if the program genuinely finished on the frame the user
    /// pressed Stop, then the design is *whole*, and `.programFinished` is both true and
    /// strictly more informative — reporting `.stoppedByUser` would suggest a partial design
    /// the user does not have. The cap is different: it is an app-imposed limit, so when the
    /// user has also asked to stop, their intent is the honest account of why the run ended,
    /// and it suppresses a limit notice for a run they ended themselves.
    static func completionReason(
        programFinished: Bool,
        interpreterIsFinished: Bool,
        cancelled: Bool,
        stitchesThisRun: Int,
        budget: RunBudget
    ) -> RunCompletion? {
        if programFinished || interpreterIsFinished {
            .programFinished
        } else if cancelled {
            .stoppedByUser
        } else if stitchesThisRun >= budget.maxStitchesPerRun {
            .stitchLimitReached
        } else {
            nil
        }
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
/// **`stop()` cancels the producer only, never the consumer — and getting this backwards
/// silently breaks the story's central criterion.** Only the producer can *decide* to stop:
/// it is the thing that observes `Task.isCancelled` and emits the terminal update carrying
/// `assembledStream()`. Cancelling the consumer instead — the natural reading of "the run
/// `Task` is cancellable", and what cancelling a `for await` task or a `.task {}` does —
/// leaves the interpreter running to its natural end or the stitch cap, so no
/// `.stoppedByUser` terminal is ever produced; and once the buffer drains, the cancelled
/// consumer's suspended `next()` returns `nil`, so anything the producer yields afterwards
/// is lost. Export-after-stop would fail the way Catty's does while every unit test that
/// inspects the producer in isolation still passed.
///
/// **Correction (2026-08-17, in-loop review):** an earlier version of this comment argued
/// that from "`AsyncStream.Iterator.next()` returns `nil` when the consuming task is
/// cancelled". That is **false while elements are buffered**, and it was checked rather than
/// assumed only after the reviewer contradicted it: a consumer cancelled before it ever ran
/// still received all five buffered elements, and `next()` in a cancelled task with one
/// element buffered returned the element, not `nil`. Cancellation marks the stream terminal;
/// it does not discard `pending`. The conclusion is unchanged, the reason is not — and the
/// false premise had a second cost, because it is what made a discarded run's buffered
/// frames look impossible. See `RunViewModel`.
///
/// The consumer therefore keeps draining until the stream finishes on its own. That is **one
/// or two elements** after `stop()`, not one: cancellation is observed at the top of the
/// loop, so a `stop()` landing inside `runFrame` yields that frame's ordinary update first
/// and the terminal on the next pass.
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

    /// Asks the run to stop. The terminal update — carrying `RunCompletion.stoppedByUser` and
    /// the export model — is produced, and **delivered to a consumer that is still
    /// consuming**.
    ///
    /// That qualification is load-bearing rather than pedantic (Codex round 2): a consumer
    /// which has itself been cancelled or dropped terminates the stream, `onTermination`
    /// cancels the producer, and the terminal `yield` then returns `.terminated` and goes
    /// nowhere. That is the right outcome for a discarded run — no terminal is wanted — but it
    /// means the guarantee is about production plus a retained consumer, not about delivery
    /// unconditionally. `RunViewModel.stop()` keeps its consumer alive for exactly this
    /// reason.
    public func stop() {
        task.cancel()
    }
}
