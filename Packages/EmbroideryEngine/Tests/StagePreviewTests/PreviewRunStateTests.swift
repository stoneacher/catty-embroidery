import EmbroideryEngine
import Samples
import StagePreview
import Testing

@Suite("Preview run state")
struct PreviewRunStateTests {
    // MARK: - One mutation per batch

    /// Story item 2, the substance of it: the fold is **per batch, not per stitch**.
    ///
    /// `revision` counts mutations of the value, so the assertion is arithmetic rather
    /// than a claim about code shape. The two numbers it compares differ by an order of
    /// magnitude on a real sample — 139 updates against 3 194 stitches — so an
    /// implementation that appended stitch by stitch fails loudly rather than
    /// marginally.
    ///
    /// The app-side half of this criterion (that the *observable* mutation count
    /// matches) is `RunViewModelTests`; this is the half that runs on the fast gate.
    @Test("one apply folds a whole batch, so the revision counts batches not stitches")
    func oneApplyFoldsAWholeBatch() async {
        let drained = await driveToCompletion(SampleLibrary[.octagonRosette].program)

        var run = PreviewRunState()
        run.begin()
        for update in drained.updates {
            run.apply(update)
        }

        #expect(run.revision == drained.updates.count)
        #expect(run.display.count == 3194)
        // The claim only means something if the two numbers are different.
        #expect(run.revision != run.display.count)
    }

    /// A batch of many stitches is one mutation, stated at the smallest scale where it
    /// is visible — so the property is pinned independently of any sample's shape.
    @Test("a batch of many stitches is a single revision")
    func aBatchOfManyStitchesIsASingleRevision() {
        var run = PreviewRunState()
        run.begin()
        let batch = RunBatch(stitches: (0 ..< 500).map { previewStitch(Double($0), 0) })

        run.apply(RunUpdate(batch: batch))

        #expect(run.revision == 1)
        #expect(run.display.count == 500)
    }

    // MARK: - Transitions

    @Test("a fresh state is idle with nothing in it")
    func aFreshStateIsIdle() {
        let run = PreviewRunState()

        #expect(run.state == .idle)
        #expect(run.display.isEmpty)
        #expect(run.needle == nil)
        #expect(run.exportModel == nil)
    }

    @Test("beginning a run moves it to running")
    func beginningARunMovesItToRunning() {
        var run = PreviewRunState()

        run.begin()

        #expect(run.state == .running)
    }

    /// The terminal update is what moves the state to `.finished` **and** what supplies
    /// the export model — one update, one mutation, both facts.
    @Test("the terminal update carries the state and the export model together",
          arguments: [RunCompletion.programFinished, .stoppedByUser, .stitchLimitReached])
    func theTerminalUpdateCarriesTheStateAndTheExportModel(_ reason: RunCompletion) {
        var run = PreviewRunState()
        run.begin()
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 1, y: 1))

        run.apply(RunUpdate(
            batch: RunBatch(stitches: [previewStitch(1, 1)]),
            termination: RunTermination(reason: reason, exportModel: stream)
        ))

        #expect(run.state == .finished(reason))
        // Non-nil after **every** way a run can end, which is the criterion
        // `RunTermination`'s non-optional field makes structural.
        #expect(run.exportModel == stream)
        #expect(run.display.count == 1)
    }

    // MARK: - Reset and determinism

    /// Story item 6, first half.
    @Test("reset returns to idle and clears everything a run produced")
    func resetReturnsToIdleAndClearsEverything() {
        var run = PreviewRunState()
        run.begin()
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 1, y: 1))
        run.apply(RunUpdate(
            batch: RunBatch(
                stitches: [previewStitch(1, 1)],
                needle: PreviewNeedle(
                    actor: ActorID(0),
                    update: NeedleUpdate(position: StagePoint(x: 1, y: 1), heading: 0)
                )
            ),
            termination: RunTermination(reason: .programFinished, exportModel: stream)
        ))

        run.reset()

        #expect(run.state == .idle)
        #expect(run.display.isEmpty)
        #expect(run.needle == nil)
        #expect(run.exportModel == nil)
    }

    /// Story item 6, second half: a second play reproduces the identical display list.
    ///
    /// **Asserted on `.stitches`, never on the whole `StitchDisplayList`.** Its `==` is
    /// synthesized and therefore includes `settledCount` and `resetCount` — the latter
    /// differs 1 against 2 across two runs by design, so comparing the values would
    /// fail for a reason that has nothing to do with determinism and would send the
    /// next reader hunting for a nondeterminism that was never there.
    @Test("a second run of the same program reproduces the identical display list")
    func aSecondRunReproducesTheIdenticalDisplayList() async {
        let program = SampleLibrary[.squareCoil].program

        var run = PreviewRunState()
        run.begin()
        for update in await driveToCompletion(program).updates {
            run.apply(update)
        }
        let first = run.display.stitches
        // Captured before the second run, so the comparison below is against a *value* rather
        // than against itself. An earlier version asserted
        // `run.display.colorRuns == run.display.colorRuns`, which is tautological and could
        // not detect a colour-run regression at all (Codex round 1).
        let firstColorRuns = run.display.colorRuns

        run.reset()
        run.begin()
        for update in await driveToCompletion(program).updates {
            run.apply(update)
        }

        #expect(run.display.stitches == first)
        #expect(run.display.colorRuns == firstColorRuns)
        #expect(!first.isEmpty)
        #expect(!firstColorRuns.isEmpty)
    }

    /// `begin()` after a finished run must clear it, or pressing play again would draw
    /// the new run on top of the old one.
    @Test("beginning a second run clears the first")
    func beginningASecondRunClearsTheFirst() {
        var run = PreviewRunState()
        run.begin()
        run.apply(RunUpdate(batch: RunBatch(stitches: [previewStitch(1, 1)])))

        run.begin()

        #expect(run.state == .running)
        #expect(run.display.isEmpty)
        #expect(run.exportModel == nil)
    }

    // MARK: - Only a running run accepts updates

    /// **One half of the fix for a discarded run's updates landing in the next one**
    /// (`swift-code-reviewer`). A cancelled consumer keeps receiving elements already buffered
    /// in the `AsyncStream` — cancellation marks the stream terminal but does not discard
    /// `pending`, measured directly.
    ///
    /// This guard covers updates arriving while the run is `.idle` or `.finished`. It
    /// deliberately does **not** claim to distinguish *sessions*: `begin()` A, `reset()`,
    /// `begin()` B leaves B `.running`, so A's late frames would be accepted here (Codex round
    /// 1 refuted the stronger claim an earlier version of this comment made). Telling one run
    /// from another needs an identity the update does not carry — `RunViewModel.generation`.
    @Test("an update applied before the run begins is ignored")
    func anUpdateBeforeBeginIsIgnored() {
        var run = PreviewRunState()

        run.apply(RunUpdate(batch: RunBatch(stitches: [previewStitch(1, 1)])))

        #expect(run.state == .idle)
        #expect(run.display.isEmpty)
        #expect(run.revision == 0)
    }

    /// The reachable case, and the one with teeth: the user picks a new design mid-run, so
    /// `AppModel.select(_:)` resets, and the previous run's buffered frames arrive
    /// afterwards. Without this they append into the new design's display list — and a
    /// buffered *terminal* would additionally publish the discarded design's export model,
    /// which is US-308's input.
    @Test("updates arriving after a run ends or is reset are ignored")
    func updatesAfterTheRunEndsAreIgnored() {
        var run = PreviewRunState()
        run.begin()
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 1, y: 1))
        run.apply(RunUpdate(
            batch: RunBatch(stitches: [previewStitch(1, 1)]),
            termination: RunTermination(reason: .programFinished, exportModel: stream)
        ))
        let settled = run

        // A late frame from the finished run, then a late frame after a reset.
        run.apply(RunUpdate(batch: RunBatch(stitches: [previewStitch(9, 9)])))
        #expect(run.display.stitches == settled.display.stitches)
        #expect(run.revision == settled.revision)

        run.reset()
        var late = EmbroideryStream()
        late.addStitch(at: StagePoint(x: 5, y: 5))
        run.apply(RunUpdate(
            batch: RunBatch(stitches: [previewStitch(5, 5)]),
            termination: RunTermination(reason: .stitchLimitReached, exportModel: late)
        ))

        #expect(run.state == .idle)
        #expect(run.display.isEmpty)
        #expect(run.exportModel == nil, "a discarded run must not publish an export model")
    }

    // MARK: - What the stage draws the needle from

    /// The needle is only shown while the run is running, and the rule is **a value here**
    /// rather than an expression at the call site.
    ///
    /// It was an expression in `RootView`, and the test that claimed to pin it recomputed
    /// the same expression in its own body — so it stayed green if the call site dropped the
    /// condition entirely (`swift-code-reviewer`). A needle parked on a finished design says
    /// the machine is still working on it.
    @Test("the needle is visible only while the run is running")
    func theNeedleIsVisibleOnlyWhileRunning() {
        let pose = PreviewNeedle(
            actor: ActorID(0),
            update: NeedleUpdate(position: StagePoint(x: 1, y: 1), heading: 0)
        )
        var run = PreviewRunState()
        run.begin()
        run.apply(RunUpdate(batch: RunBatch(stitches: [previewStitch(1, 1)], needle: pose)))

        #expect(run.visibleNeedle == pose)

        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 1, y: 1))
        run.apply(RunUpdate(
            batch: RunBatch(),
            termination: RunTermination(reason: .stoppedByUser, exportModel: stream)
        ))

        #expect(run.needle == pose, "the pose is retained — only its visibility changes")
        #expect(run.visibleNeedle == nil)
    }

    // MARK: - The settling watermark

    /// US-305 shipped the cached-raster path wired but unreachable, because nothing
    /// advanced the watermark; ADR-024 records the gap and addresses it to this story
    /// by name. This is where it is advanced.
    ///
    /// **Quantised, and the test pins the quantisation rather than the mere fact of
    /// advancing.** The renderer re-bakes whenever `settledCount` changes, so settling
    /// every frame would bake every frame — strictly worse than never baking. The
    /// watermark therefore lands on multiples of `settleChunk` and never exceeds the
    /// stitch count.
    @Test("the watermark advances in chunks and never passes the stitch count",
          arguments: [SampleID.octagonRosette, .squareCoil])
    func theWatermarkAdvancesInChunks(_ id: SampleID) async {
        var run = PreviewRunState()
        run.begin()
        var watermarks: [Int] = []
        for update in await driveToCompletion(SampleLibrary[id].program).updates {
            run.apply(update)
            if watermarks.last != run.display.settledCount {
                watermarks.append(run.display.settledCount)
            }
        }

        let chunk = PreviewRunState.settleChunk
        #expect(run.display.settledCount == run.display.count - run.display.count % chunk)
        #expect(run.display.settledCount <= run.display.count)
        #expect(watermarks.allSatisfy { $0 % chunk == 0 })
        // Advances a handful of times per run, not once per frame — the property the
        // chunking exists for. Both samples cross US-305's bakingThreshold of 2000.
        #expect(watermarks.count <= run.display.count / chunk + 1)
        #expect(run.display.settledCount >= 2000)
    }

    @Test("a run shorter than one chunk settles nothing")
    func aRunShorterThanOneChunkSettlesNothing() {
        var run = PreviewRunState()
        run.begin()

        run.apply(RunUpdate(batch: RunBatch(stitches: [previewStitch(1, 1)])))

        #expect(run.display.settledCount == 0)
    }
}
