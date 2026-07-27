import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// US-208 item 4: the M2 exit criterion's *consumption* half on the star —
/// stepping one tick at a time yields the identical event sequence and assembled
/// stream as `run()`, and re-running the same `Program` value is bit-identical.
///
/// What this adds over US-207's square: the events now carry a **mid-program
/// colour change**, so the event-only reconstruction has to reproduce colour
/// state and not merely positions, and the tick accounting has to hold across
/// **two** compiled loops rather than one.
@Suite("Golden program: star consumption")
struct GoldenProgramStarConsumptionTests {
    private let clock = InterpreterClock(tickDelta: 0.05)

    private func makeInterpreter() -> Interpreter {
        Interpreter(program: GoldenStar.program, clock: clock)
    }

    /// Drives `interpreter` one tick at a time to completion, returning each
    /// tick's batch separately so the per-tick profile stays assertable.
    private func stepToCompletion(_ interpreter: inout Interpreter) -> [[InterpreterEvent]] {
        var batches: [[InterpreterEvent]] = []
        while case let .ticked(batch) = interpreter.step() {
            batches.append(batch)
        }
        return batches
    }

    // MARK: - Incremental consumption equals batch execution

    @Test("stepping one tick at a time yields the identical events and stream as run()")
    func steppingEqualsBatchRun() {
        var stepped = makeInterpreter()
        let batches = stepToCompletion(&stepped)

        var batched = makeInterpreter()
        let batchedEvents = batched.run(maxTicks: 100)

        #expect(Array(batches.joined()) == batchedEvents)
        #expect(stepped.assembledStream() == batched.assembledStream())
        // And the stream is the golden one either way, not merely equal to itself.
        #expect(recordPositions(stepped.assembledStream()) == goldenStarRecords)
    }

    @Test("a consumer rebuilding the stream from the events alone reproduces both colours")
    func eventsAloneReconstructTheStream() {
        // The square could only show that positions survive an event-only
        // rebuild; with two colours the rebuild also has to place the change
        // record, which is the harder half of the claim M3's live preview rests on.
        var stepped = makeInterpreter()
        let batches = stepToCompletion(&stepped)

        let rebuilt = streamRebuiltFromEvents(Array(batches.joined()))
        #expect(rebuilt == stepped.assembledStream())
        #expect(recordPositions(rebuilt) == goldenStarRecords)
        #expect(rebuilt.colorChangeCount == 1)
        #expect(Set(rebuilt.stitches.map(\.color)) == [GoldenStar.startColor, GoldenStar.midThreadColor])
    }

    @Test("the star occupies exactly fifteen ticks with the derived per-tick event profile")
    func perTickProfileMatchesAdr018Accounting() {
        var stepped = makeInterpreter()
        let batches = stepToCompletion(&stepped)

        // Fifteen ticks = fifteen *action* bricks (two colour sets, the pattern
        // activation, 5 × [move, turn], sewUp, write). Eight loop-bookkeeping
        // steps across *two* loops cost nothing — the observable consequence of
        // `repeatLoop`/`loopEnd` being zero-tick (ADR-018).
        #expect(batches.count == 15)
        #expect(batches.count == actionBrickCount(GoldenStar.spec))
        #expect(batches.map(\.count) == goldenStarTickProfile)
        // Tick 2 activates the pattern: action-consuming, but event-free.
        #expect(batches[1].isEmpty)
        // Tick 7 is the mid-program colour set, alone between the two loops —
        // it does not share the second loop's first move.
        #expect(eventTags(batches[6]) == ["color"])
        #expect(eventTags(batches[7]).first == "move")
    }

    @Test("the interpreter finishes on its fifteenth tick and stays finished")
    func finishesOnTheFifteenthTickAndStaysFinished() {
        var interpreter = makeInterpreter()
        #expect(!interpreter.isFinished)

        for _ in 0 ..< 15 {
            _ = interpreter.step()
        }
        // Same-tick close: the last brick's tick also finishes the thread.
        #expect(interpreter.isFinished)
        #expect(interpreter.step() == .finished)
        #expect(interpreter.step() == .finished)
    }

    @Test("assembledStream() mid-run is the golden's prefix, in the first colour only")
    func assembledStreamMidRunIsAPrefix() {
        var interpreter = makeInterpreter()
        for _ in 0 ..< 3 { // colour, activation, first side
            _ = interpreter.step()
        }

        let midRun = interpreter.assembledStream()
        #expect(recordPositions(midRun) == Array(goldenStarRecords.prefix(5)))
        // Stopped before the second colour set, so no change has been armed yet.
        #expect(midRun.colorChangeCount == 0)
        #expect(Set(midRun.stitches.map(\.color)) == [GoldenStar.startColor])
        // Pure: asking twice changes nothing.
        #expect(interpreter.assembledStream() == midRun)
    }

    // MARK: - Determinism

    @Test("two runs of the same program produce identical events and identical streams")
    func twoRunsAreIdentical() {
        var first = makeInterpreter()
        var second = makeInterpreter()

        let firstEvents = first.run(maxTicks: 100)
        let secondEvents = second.run(maxTicks: 100)

        #expect(firstEvents == secondEvents)
        #expect(first.assembledStream() == second.assembledStream())
    }

    @Test("a copy taken before the colour change replays the identical tail")
    func aMidRunCopyReplaysTheIdenticalTail() {
        // Copied inside the first loop, so the copy still has to arm the colour
        // change itself — the zigzag's alternation sign and the manager's
        // per-actor colour state both have to live in the copied value.
        var original = makeInterpreter()
        for _ in 0 ..< 3 {
            _ = original.step()
        }
        var copy = original

        let originalTail = original.run(maxTicks: 100)
        let copyTail = copy.run(maxTicks: 100)

        #expect(originalTail == copyTail)
        #expect(original.assembledStream() == copy.assembledStream())
        #expect(recordPositions(copy.assembledStream()) == goldenStarRecords)
        #expect(copy.assembledStream().colorChangeCount == 1)
    }
}
