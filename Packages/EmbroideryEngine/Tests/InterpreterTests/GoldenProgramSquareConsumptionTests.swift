import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// US-207 items 3–4: the M2 exit criterion's *consumption* half, now on a
/// non-trivial program — driving the square one `step()` at a time yields the
/// identical event sequence and assembled stream as `run()`, and re-running the
/// same `Program` value is bit-identical.
@Suite("Golden program: square consumption")
struct GoldenProgramSquareConsumptionTests {
    private let clock = InterpreterClock(tickDelta: 0.05)

    private func interpreter() -> Interpreter {
        Interpreter(program: GoldenSquare.program, clock: clock)
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

    // MARK: - Item 3 — incremental consumption equals batch execution

    @Test("stepping one tick at a time yields the identical events and stream as run()")
    func steppingEqualsBatchRun() {
        var stepped = interpreter()
        let batches = stepToCompletion(&stepped)

        var batched = interpreter()
        let batchedEvents = batched.run(maxTicks: 100)

        #expect(batches.flatMap(\.self) == batchedEvents)
        #expect(stepped.assembledStream() == batched.assembledStream())
        // And the stream is the golden one either way, not merely equal to itself.
        #expect(recordPositions(stepped.assembledStream()) == goldenSquareRecords)
    }

    @Test("the square occupies exactly twelve ticks with the derived per-tick event profile")
    func perTickProfileMatchesAdr018Accounting() {
        var stepped = interpreter()
        let batches = stepToCompletion(&stepped)

        #expect(batches.count == 12)
        #expect(batches.map(\.count) == goldenSquareTickProfile)
        // Tick 2 activates the pattern: action-consuming, but event-free — an
        // empty `.ticked` batch rather than a skipped tick.
        #expect(batches[1].isEmpty)
        // The loop's exhaustion folds into tick 10 (the fourth turn), so the tack
        // waits for tick 11 instead of sharing that tick (ADR-018).
        #expect(eventTags(batches[9]) == ["move"])
        #expect(eventTags(batches[10]) == Array(repeating: "stitch", count: 5))
    }

    @Test("the interpreter finishes on its twelfth tick and stays finished")
    func finishesOnTheTwelfthTickAndStaysFinished() {
        var interpreter = interpreter()
        #expect(!interpreter.isFinished)

        for _ in 0 ..< 12 {
            _ = interpreter.step()
        }
        // Same-tick close: the last brick's tick also finishes the thread.
        #expect(interpreter.isFinished)
        #expect(interpreter.step() == .finished)
        #expect(interpreter.step() == .finished)
    }

    @Test("assembledStream() mid-run is the golden's prefix and is repeatable")
    func assembledStreamMidRunIsAPrefix() {
        var interpreter = interpreter()
        for _ in 0 ..< 3 { // colour, activation, first side
            _ = interpreter.step()
        }

        let midRun = interpreter.assembledStream()
        #expect(recordPositions(midRun) == Array(goldenSquareRecords.prefix(5)))
        // Pure: asking twice changes nothing.
        #expect(interpreter.assembledStream() == midRun)
    }

    // MARK: - Item 4 — determinism

    @Test("two runs of the same program produce identical events and identical streams")
    func twoRunsAreIdentical() {
        var first = interpreter()
        var second = interpreter()

        let firstEvents = first.run(maxTicks: 100)
        let secondEvents = second.run(maxTicks: 100)

        #expect(firstEvents == secondEvents)
        #expect(first.assembledStream() == second.assembledStream())
    }

    @Test("a copy taken mid-run replays the identical tail — execution state is in the value")
    func aMidRunCopyReplaysTheIdenticalTail() {
        // `Interpreter` documents that a caller can snapshot or replay a run by
        // copying the value; nothing tested it. Copy after the first side, then
        // advance original and copy independently.
        var original = interpreter()
        for _ in 0 ..< 3 {
            _ = original.step()
        }
        var copy = original

        let originalTail = original.run(maxTicks: 100)
        let copyTail = copy.run(maxTicks: 100)

        #expect(originalTail == copyTail)
        #expect(original.assembledStream() == copy.assembledStream())
        #expect(recordPositions(copy.assembledStream()) == goldenSquareRecords)
    }
}
