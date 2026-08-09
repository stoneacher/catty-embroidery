import EmbroideryEngine
import Interpreter
import ProgramModel
import Samples
import StagePreview
import Testing

@Suite("Run batch")
struct RunBatchTests {
    @Test("an empty batch reduces to empty")
    func emptyEventsReduceToEmpty() {
        #expect(RunBatch.reducing([]) == .empty)
    }

    @Test("reducing nothing carries the incoming needle pose forward")
    func emptyBatchCarriesTheNeedle() {
        let carried = PreviewNeedle(
            actor: ActorID(0),
            update: NeedleUpdate(position: StagePoint(x: 3, y: 4), heading: 90)
        )
        let batch = RunBatch.reducing([], from: carried)
        #expect(batch.stitches.isEmpty)
        #expect(batch.needle == carried)
    }

    @Test("stitch events become preview stitches in order, with their colors")
    func stitchEventsBecomePreviewStitches() {
        let events: [InterpreterEvent] = [
            .stitch(actor: ActorID(0), position: StagePoint(x: 1, y: 2), layer: 0, color: PreviewColor.red),
            .stitch(actor: ActorID(0), position: StagePoint(x: 3, y: 4), layer: 0, color: PreviewColor.green)
        ]
        #expect(RunBatch.reducing(events).stitches == [
            previewStitch(1, 2, PreviewColor.red),
            previewStitch(3, 4, PreviewColor.green)
        ])
    }

    @Test("the needle pose is the last one in the batch")
    func needlePoseIsLastWins() {
        let first = NeedleUpdate(position: StagePoint(x: 1, y: 1), heading: 10)
        let last = NeedleUpdate(position: StagePoint(x: 9, y: 9), heading: 20)
        let events: [InterpreterEvent] = [
            .needleMoved(actor: ActorID(0), update: first),
            .needleMoved(actor: ActorID(0), update: last)
        ]
        #expect(RunBatch.reducing(events).needle == PreviewNeedle(actor: ActorID(0), update: last))
    }

    @Test("a finalize request is carried as the terminal marker, last wins")
    func finalizeRequestIsCarried() {
        let events: [InterpreterEvent] = [
            .finalizeRequested(name: "first"), .finalizeRequested(name: "second")
        ]
        #expect(RunBatch.reducing(events).requestedDesignName == "second")
    }

    /// The AC's "no preview code path consumes `.colorArmed`", made
    /// mechanical: a batch of nothing but armed colours — including a hex the
    /// manager rejected — must reduce to exactly nothing.
    @Test("colorArmed and waited contribute nothing at all")
    func ignoredEventsContributeNothing() {
        let events: [InterpreterEvent] = [
            .colorArmed(actor: ActorID(0), hex: "#ff0000"),
            .colorArmed(actor: ActorID(0), hex: "not-a-color"),
            .waited(actor: ActorID(0))
        ]
        #expect(RunBatch.reducing(events) == .empty)
    }

    /// ADR-018's structural invariant, one layer up: `run(maxTicks:)` is the
    /// concatenation of the `step()` batches, so folding the batches one at a
    /// time and folding the whole event list must agree.
    @Test(
        "per-tick reductions concatenate to the whole-run reduction",
        arguments: SampleLibrary.all.map(\.id)
    )
    func perTickReductionsConcatenate(_ id: SampleID) {
        var stepped = interpreter(SampleLibrary[id].program)
        let batches = tickBatches(&stepped)

        let folded = foldBatches(batches)

        var whole = interpreter(SampleLibrary[id].program)
        let allEvents = whole.run(maxTicks: 100_000)
        let wholeBatch = RunBatch.reducing(allEvents)

        #expect(folded.stitches == wholeBatch.stitches)
        #expect(folded.needle == wholeBatch.needle)
        #expect(folded.requestedName == wholeBatch.requestedDesignName)
        #expect(!folded.stitches.isEmpty, "a sample that produced nothing would pass vacuously")
        #expect(folded.needle != nil, "a sample that moved no needle would pass vacuously")
    }

    /// The partition test above is **tautological for the terminal marker** on
    /// the bundled samples, because neither contains `writeEmbroideryToFile`:
    /// both sides yield `nil`, so a reducer that dropped finalization entirely
    /// would pass (Codex round 1). This partitions explicit batches instead,
    /// with the finalize in an *earlier* tick than the last, so carrying it
    /// across a later non-finalize tick is what is actually tested.
    @Test("the terminal marker survives a later tick that does not finalize")
    func finalizeMarkerSurvivesAcrossTicks() {
        let batches: [[InterpreterEvent]] = [
            [.stitch(actor: ActorID(0), position: StagePoint(x: 0, y: 0), layer: 0, color: PreviewColor.red)],
            [.finalizeRequested(name: "design")],
            [.stitch(actor: ActorID(0), position: StagePoint(x: 1, y: 0), layer: 0, color: PreviewColor.red)]
        ]

        let folded = foldBatches(batches)

        let whole = RunBatch.reducing(batches.flatMap(\.self))
        #expect(folded.requestedName == "design")
        #expect(whole.requestedDesignName == "design")
        #expect(folded.stitches == whole.stitches)

        // And the marker really is per-batch, not sticky: the final batch
        // carries none of its own.
        #expect(RunBatch.reducing(batches[2]).requestedDesignName == nil)
    }
}
