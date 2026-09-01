import StagePreview
import Testing

/// US-309 test item 4: an animated run to 50 000 with no dropped batch.
///
/// **Half of this item was already green before the story started, and it is labelled as a
/// regression guard rather than as work.** "Display list count equals the interpreter's
/// stitch-event count" is what `PreviewRunState.apply` does by construction —
/// `display.append(contentsOf: update.batch.stitches)`, with `RunBatch.reducing`'s
/// exhaustive switch already pinned by US-306. Writing it as new work would produce a test
/// that was never red, which is the class US-308's journal gives the cheap check for.
///
/// What *is* new is the second half: **one observable mutation per batch, held at 50 000**.
/// US-307 measured 2 rebuilds against 139 batches on a 3 194-stitch sample; nothing has ever
/// run this path at fifteen times that length, and a per-stitch mutation introduced anywhere
/// in the fold would leave `revision` equal to the stitch count instead of the update count.
/// At M3's real samples the two differ by an order of magnitude; here they differ by three.
@Suite("US-309 run state at fifty thousand")
struct PreviewRunStateAtScaleTests {
    @Test("a fifty-thousand-stitch run loses no batch")
    func aFiftyThousandStitchRunLosesNoBatch() async {
        let program = SyntheticDesign.program()
        let drained = await driveToCompletion(program)

        var run = PreviewRunState()
        run.begin()
        for update in drained.updates {
            run.apply(update)
        }

        #expect(run.display.count == stitchEventCount(of: program))
        #expect(run.display.count == SyntheticDesign.programStitchCount)
    }

    /// The genuinely new assertion: the fold stays one mutation per update at this scale.
    ///
    /// Compared against the **update count**, not against a constant: a run's frame count is
    /// a property of the program and the budget, and pinning it as a literal here would make
    /// this test fail for a reason that has nothing to do with what it guards.
    @Test("a fifty-thousand-stitch run is one mutation per batch")
    func aFiftyThousandStitchRunIsOneMutationPerBatch() async {
        let drained = await driveToCompletion(SyntheticDesign.program())

        var run = PreviewRunState()
        run.begin()
        for update in drained.updates {
            run.apply(update)
        }

        #expect(run.revision == drained.updates.count)
        #expect(run.revision * 10 < run.display.count, """
        \(run.revision) mutations for \(run.display.count) stitches — if these are within an \
        order of magnitude the fold has become per-stitch
        """)
    }

    /// The precondition AC3's capture protocol depends on: after the run, the design is
    /// settled to the policy's watermark, so a "50 000 settled" capture is a state the device
    /// session can actually reach rather than one it has to contrive.
    @Test("a finished fifty-thousand-stitch run settles to the policy's watermark")
    func aFinishedFiftyThousandStitchRunSettlesToThePolicysWatermark() async {
        let drained = await driveToCompletion(SyntheticDesign.program())

        var run = PreviewRunState()
        run.begin()
        for update in drained.updates {
            run.apply(update)
        }

        #expect(run.display.settledCount == PreviewRunState.settleWatermark(for: run.display.count))
        #expect(run.display.settledCount >= 50_000)
    }

    /// The run terminates on the program finishing, not on the stitch cap.
    ///
    /// `RunBudget.maxStitchesPerRun` is 200 000 and its doc comment says it clears US-309's
    /// criterion "by a wide margin (4×)". This is the test that makes that sentence true of
    /// the design rather than of an arithmetic claim about it — a synthetic that tripped the
    /// cap would produce a truncated capture and a `.stitchLimitReached` terminal nobody
    /// looked at.
    @Test("the synthetic run finishes on its own rather than hitting the stitch cap")
    func theSyntheticRunFinishesOnItsOwnRatherThanHittingTheStitchCap() async {
        let drained = await driveToCompletion(SyntheticDesign.program())
        #expect(drained.terminalCount == 1)
        #expect(drained.termination?.reason == .programFinished)
    }
}
