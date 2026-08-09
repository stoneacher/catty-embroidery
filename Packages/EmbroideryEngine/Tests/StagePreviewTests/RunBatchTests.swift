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
            .stitch(actor: ActorID(0), position: StagePoint(x: 1, y: 2), layer: 0, color: red),
            .stitch(actor: ActorID(0), position: StagePoint(x: 3, y: 4), layer: 0, color: green)
        ]
        #expect(RunBatch.reducing(events).stitches == [previewStitch(1, 2, red), previewStitch(3, 4, green)])
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

        var accumulated: [PreviewStitch] = []
        var carried: PreviewNeedle?
        var lastRequestedName: String?
        for events in batches {
            let batch = RunBatch.reducing(events, from: carried)
            accumulated += batch.stitches
            carried = batch.needle
            lastRequestedName = batch.requestedDesignName ?? lastRequestedName
        }

        var whole = interpreter(SampleLibrary[id].program)
        let allEvents = whole.run(maxTicks: 100_000)
        let wholeBatch = RunBatch.reducing(allEvents)

        #expect(accumulated == wholeBatch.stitches)
        #expect(carried == wholeBatch.needle)
        #expect(lastRequestedName == wholeBatch.requestedDesignName)
        #expect(!accumulated.isEmpty, "a sample that produced nothing would pass vacuously")
    }
}
