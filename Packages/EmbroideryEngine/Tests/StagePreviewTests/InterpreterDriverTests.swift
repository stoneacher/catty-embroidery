import Samples
// `@testable` for `InterpreterDriver.completionReason` alone, which is deliberately
// **internal**: it is the run's completion-precedence table, not API. Making it public to
// test it would widen the boundary `StagePreviewTargetIsolationTests` exists to pin.
@testable import StagePreview
import Testing

@Suite("Interpreter driver")
struct InterpreterDriverTests {
    // MARK: - A whole run

    /// Story item 1. Two claims in one: the run reaches `.programFinished` on its
    /// own, and it delivers **every** stitch the program emits — nothing dropped at
    /// a frame boundary, which is what unbounded buffering exists to guarantee.
    @Test("a full sample run drains to programFinished with every stitch the sample emits",
          arguments: SampleLibrary.all)
    func aFullSampleRunDeliversEveryStitch(_ sample: SampleProgram) async {
        let expected = stitchEventCount(of: sample.program)
        let drained = await driveToCompletion(sample.program)

        #expect(drained.termination?.reason == .programFinished)
        #expect(drained.stitches.count == expected)
        #expect(drained.terminalCount == 1)
        // The export model is present on a natural finish too, not only after a stop.
        #expect((drained.termination?.exportModel.count ?? 0) > 0)
    }

    /// The literals, pinned separately from the derivation above.
    ///
    /// Deriving the expectation from the same interpreter the driver runs would move
    /// both sides of the equation together, so a change in the engine would keep the
    /// test green while changing what the app draws. `SampleBudgetTests` pins these
    /// same counts one target away; this is the preview's own copy of the claim.
    @Test("the samples' stitch counts are the numbers US-301 pinned",
          arguments: [(SampleID.octagonRosette, 3194), (SampleID.squareCoil, 2976)])
    func theSamplesStitchCountsAreThePinnedNumbers(_ id: SampleID, _ expected: Int) async {
        let drained = await driveToCompletion(SampleLibrary[id].program)

        #expect(drained.stitches.count == expected)
    }

    // MARK: - Stopping

    /// Story item 3, and the story's central criterion: a user stop still yields an
    /// export model.
    ///
    /// This is the direct answer to Catty's `Stage.stopProject()`, which calls
    /// `removeAllChildren()` and `frontend.project?.removeReferences()` — tearing
    /// down the very object graph its own `shareDST` reads — so that stopping a run
    /// there can cost the design you meant to export.
    ///
    /// Gated pacing rather than immediate: see `GatedRunPacing`. A `forever` program
    /// so that a natural finish cannot race the stop and hand back
    /// `.programFinished` instead.
    ///
    /// The iterator is a **local**: a suite-level `static var` holding an
    /// `AsyncIterator` does not compile here.
    @Test("stopping mid-run finishes as stoppedByUser with stitches and an export model",
          .timeLimit(.minutes(1)))
    func stoppingMidRunKeepsTheDesignAndTheExportModel() async {
        let pacing = GatedRunPacing()
        let driver = InterpreterDriver(pacing: pacing)
        let session = driver.start(interpreter(foreverProgram()))

        var drained = DrainedRun()
        var iterator = session.updates.makeAsyncIterator()
        for frame in 0 ..< 3 {
            // The first frame needs no credit: the driver produces one, *then* paces.
            if frame > 0 {
                await pacing.grant()
            }
            guard let update = await iterator.next() else { break }
            drained.updates.append(update)
        }

        session.stop()
        // **No grant here, deliberately.** An earlier version granted one more frame so the
        // parked producer would wake — which is precisely what hid the fact that a
        // cancellation-deaf gate parks the producer forever (Codex round 2). `stop()` alone
        // must be enough.
        while let update = await iterator.next() {
            drained.updates.append(update)
        }

        #expect(drained.termination?.reason == .stoppedByUser)
        #expect(drained.terminalCount == 1)
        // All three of item 3's assertions, and the last two are the ones that matter:
        // a stop that lost the design or the export model would still report the right
        // reason.
        #expect(!drained.stitches.isEmpty)
        #expect((drained.termination?.exportModel.count ?? 0) > 0)
    }

    /// The `RunPacing` contract's test: **a run stopped while the producer is parked in
    /// pacing still terminates**, with no further help from the test.
    ///
    /// Codex round 2 found this hole through this package's own gated double, which had been
    /// written to ignore cancellation "deliberately": a producer suspended in
    /// `waitForNextFrame()` never reached the next `Task.isCancelled` check, so `stop()`
    /// produced no `.stoppedByUser` and no export model — the story's central criterion,
    /// defeated by an injected implementation rather than by the driver. The requirement cannot
    /// be expressed in the protocol's type, so it is documented there and pinned here.
    ///
    /// A `forever` program, so nothing but the stop can end the run.
    @Test("a run stopped while parked in pacing still terminates", .timeLimit(.minutes(1)))
    func aRunStoppedWhileParkedInPacingStillTerminates() async {
        let pacing = GatedRunPacing()
        let driver = InterpreterDriver(pacing: pacing)
        let session = driver.start(interpreter(foreverProgram()))

        var iterator = session.updates.makeAsyncIterator()
        // The first frame needs no credit; after yielding it the producer parks in the gate.
        _ = await iterator.next()

        session.stop()

        var updates: [RunUpdate] = []
        while let update = await iterator.next() {
            updates.append(update)
        }

        #expect(updates.compactMap(\.termination).count == 1)
        #expect(updates.compactMap(\.termination).first?.reason == .stoppedByUser)
    }

    // MARK: - The stitch cap

    /// Story item 4. A `forever` program never terminates on its own, so the app owns
    /// the stop — and it must stop on a *stitch* budget, which is why the driver loops
    /// `step()` rather than calling `run(maxTicks:)`.
    ///
    /// `.timeLimit` so "does not hang" fails the test instead of hanging the suite.
    /// A small injected cap rather than draining the 200 000 default: the default is
    /// pinned separately and cheaply below.
    @Test("a forever program stops at the stitch cap rather than running away",
          .timeLimit(.minutes(1)))
    func aForeverProgramStopsAtTheStitchCap() async {
        let drained = await driveToCompletion(
            foreverProgram(), budget: RunBudget(maxStitchesPerRun: 400)
        )

        #expect(drained.termination?.reason == .stitchLimitReached)
        #expect(drained.terminalCount == 1)
        // At or just past the cap, never short of it: the cap is checked between
        // ticks, and one tick of this program adds two stitches.
        #expect(drained.stitches.count >= 400)
        #expect(drained.stitches.count <= 402)
        #expect((drained.termination?.exportModel.count ?? 0) > 0)
    }

    /// A degenerate budget must not produce a run that can never end.
    ///
    /// `ticksPerFrame: 0` ran **zero** ticks per frame, so `programFinished` stayed false,
    /// `run.isFinished` never became true (no `step()` was ever made) and `stitchesThisRun`
    /// stayed 0 — no budget axis could fire and the producer yielded empty frames forever.
    /// That was the only path found that produces **zero** terminals, breaking the guarantee
    /// ADR-027 makes structural everywhere else (`swift-code-reviewer`). Negative
    /// `maxStitchesPerRun` is the mirror case: `0 >= -1` terminated every run on frame 1.
    ///
    /// `RunBudget` is public and ADR-027 hands it to US-309 as a tunable, so the values are
    /// clamped in `init` rather than guarded at the use site.
    @Test("a degenerate budget is clamped rather than producing an endless run",
          .timeLimit(.minutes(1)))
    func aDegenerateBudgetIsClamped() async {
        #expect(RunBudget(ticksPerFrame: 0).ticksPerFrame >= 1)
        #expect(RunBudget(ticksPerFrame: -5).ticksPerFrame >= 1)
        #expect(RunBudget(maxStitchesPerFrame: 0).maxStitchesPerFrame >= 1)
        #expect(RunBudget(maxStitchesPerRun: -1).maxStitchesPerRun >= 1)

        // And the run it produces still terminates, on a program that never ends by itself.
        let drained = await driveToCompletion(
            foreverProgram(), budget: RunBudget(ticksPerFrame: 0, maxStitchesPerRun: 300)
        )

        #expect(drained.terminalCount == 1)
        #expect(drained.termination?.reason == .stitchLimitReached)
    }

    /// The default budget is the number the story's close-out records, so it is
    /// asserted rather than left as a literal in one file.
    @Test("the display budget is one tick per frame and the recorded stitch cap")
    func theDisplayBudgetIsTheRecordedNumbers() {
        #expect(RunBudget.display.ticksPerFrame == 1)
        #expect(RunBudget.display.maxStitchesPerFrame == 2000)
        #expect(RunBudget.display.maxStitchesPerRun == 200_000)
    }

    // MARK: - Completion precedence

    /// The precedence table, enumerated — because the interesting cases are the ones where two
    /// reasons are true at once, and only an interleaving would reach them through the driver.
    ///
    /// Codex round 1 found the ordering wrong: cancellation was checked only at the top of the
    /// loop, so a `stop()` landing *during* a long frame that also crossed the cap reported
    /// `.stitchLimitReached` to a user who had pressed Stop.
    @Test("completion beats cancellation, and cancellation beats the cap")
    func completionPrecedence() {
        let budget = RunBudget(maxStitchesPerRun: 100)
        let reason = InterpreterDriver.completionReason

        // Nothing true yet.
        #expect(reason(false, false, false, 0, budget) == nil)
        // Each alone.
        #expect(reason(true, false, false, 0, budget) == .programFinished)
        #expect(reason(false, true, false, 0, budget) == .programFinished)
        #expect(reason(false, false, true, 0, budget) == .stoppedByUser)
        #expect(reason(false, false, false, 100, budget) == .stitchLimitReached)
        // **Cancellation beats the cap** — the finding. The user's own stop is the honest
        // account of why the run ended, and it suppresses a limit notice for a run they ended.
        #expect(reason(false, false, true, 100, budget) == .stoppedByUser)
        // **Completion beats cancellation** — deliberately narrowing what the finding implied.
        // If the program genuinely finished on the frame Stop was pressed, the design is whole,
        // and `.stoppedByUser` would suggest a partial design the user does not have.
        #expect(reason(true, false, true, 100, budget) == .programFinished)
        #expect(reason(false, true, true, 100, budget) == .programFinished)
    }

    // MARK: - Oversize ticks

    /// Story item 5(a). One tick emits far more than `maxStitchesPerFrame`, and it is
    /// applied **whole** — `step()` returns one atomic `[InterpreterEvent]`, so the
    /// driver cannot split it and must not try.
    ///
    /// `ticksPerFrame: 4` is required for this test to mean anything: at the default
    /// of 1 the per-frame stitch budget is unreachable by construction, so the test
    /// would assert only that the batch was not truncated. And the program has work
    /// *after* the oversize move, or the run finishes inside the same frame and
    /// "the frame ended at the budget" has nothing to observe.
    @Test("an oversize single tick is applied whole and ends its frame")
    func anOversizeSingleTickIsAppliedWholeAndEndsItsFrame() async {
        let program = oversizeProgram(threads: 1, steps: 2000, tail: 10)

        let budgeted = await driveToCompletion(
            program, budget: RunBudget(ticksPerFrame: 4, maxStitchesPerFrame: 100)
        )
        let unbudgeted = await driveToCompletion(
            program, budget: RunBudget(ticksPerFrame: 4, maxStitchesPerFrame: 500_000)
        )

        // 2000 segments × 3 points + the anchor, then 10 segments × 3.
        #expect(budgeted.stitchCountsPerUpdate == [6001, 30])
        // Same stitches, one frame, when the budget is out of the way — which is what
        // makes the assertion above a claim about the *budget* and not about the fold.
        #expect(unbudgeted.stitchCountsPerUpdate == [6031])
        #expect(budgeted.stitches.count == unbudgeted.stitches.count)
        #expect(budgeted.termination?.reason == .programFinished)
    }

    /// Story item 5(b), and the half that a one-thread test cannot reach.
    ///
    /// `step()` loops *every* runnable thread and accumulates all of their events into
    /// one array (`Interpreter.swift:79`), so there is no global bound on a batch at
    /// all — the worst case scales with the number of concurrent scripts. A
    /// single-thread test would pass against an implementation that assumed a
    /// per-thread ceiling, which is exactly the bug this catches.
    ///
    /// All eight big moves land in the **same** tick because ADR-018 round-robins one
    /// action brick per thread per tick: every thread spends tick 0 activating its
    /// triple stitch.
    ///
    /// The story's stated worst case of 3 000 002 events per thread per tick is an
    /// *argument*, not a fixture: reaching ADR-014's 1 000 000-segment cap also
    /// engages ADR-020's interpolation refusal and would take minutes. This is a
    /// representative oversize.
    @Test("several concurrent scripts in one tick are applied whole")
    func severalConcurrentScriptsInOneTickAreAppliedWhole() async {
        let program = oversizeProgram(threads: 8, steps: 1000, tail: 10)

        let budgeted = await driveToCompletion(
            program, budget: RunBudget(ticksPerFrame: 4, maxStitchesPerFrame: 100)
        )
        let unbudgeted = await driveToCompletion(
            program, budget: RunBudget(ticksPerFrame: 4, maxStitchesPerFrame: 500_000)
        )

        // 8 × (1000 segments × 3 + anchor), then 8 × (10 × 3).
        #expect(budgeted.stitchCountsPerUpdate == [24008, 240])
        #expect(unbudgeted.stitchCountsPerUpdate == [24248])
        #expect(budgeted.termination?.reason == .programFinished)
    }

    // MARK: - The clock coupling

    /// Story item 7, and ADR-019's rule applies: a `wait(1)` at `tickDelta = 1/60`
    /// sits exactly **on** a threshold, so the test says so and guards it.
    ///
    /// Sixty accumulations of `1.0 / 60.0` sum to `1.0000000000000013`, which is
    /// `>= 1.0` — so the wait completes on the sixtieth tick and there is no ADR-018
    /// drift to pin here. It is worth asserting the exact number rather than a range
    /// precisely *because* it is on the boundary: a change in the accumulation that
    /// pushed the sum below 1.0 would cost a frame, and rounding the expectation would
    /// hide it.
    ///
    /// **60 rather than 61 is design-dependent**, and the design is stated here so the
    /// number is not arbitrary: the driver detects completion with
    /// `Interpreter.isFinished` after the tick, so the frame that finishes the wait is
    /// also the terminal frame. A driver that instead spent an extra `step()` to
    /// discover `.finished` would produce 61.
    @Test("a wait of one second occupies exactly sixty frames")
    func aWaitOfOneSecondOccupiesSixtyFrames() async {
        let drained = await driveToCompletion(waitProgram())

        #expect(drained.updates.count == 60)
        #expect(drained.termination?.reason == .programFinished)
        #expect(drained.stitches.isEmpty)
    }

    /// The bracketed case, so an off-by-one cannot hide in the first frame or the
    /// terminal one: one frame for the running stitch, sixty for the wait, one for the
    /// move.
    @Test("a bracketed wait occupies sixty frames between its neighbours")
    func aBracketedWaitOccupiesSixtyFramesBetweenItsNeighbours() async {
        let drained = await driveToCompletion(bracketedWaitProgram())

        #expect(drained.updates.count == 62)
        #expect(!drained.stitches.isEmpty)
    }
}
