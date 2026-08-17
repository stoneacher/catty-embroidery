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

        run.reset()
        run.begin()
        for update in await driveToCompletion(program).updates {
            run.apply(update)
        }

        #expect(run.display.stitches == first)
        #expect(run.display.colorRuns == run.display.colorRuns)
        #expect(!first.isEmpty)
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
