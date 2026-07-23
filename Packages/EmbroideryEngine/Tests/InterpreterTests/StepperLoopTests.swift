import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// US-205 test-plan item 5: loop compilation and tick accounting (ADR-018). A
/// `repeatLoop` runs its body exactly N times; nested loops multiply; `forever`
/// is bounded only by `run(maxTicks:)`. Loop bookkeeping is zero-tick, folded
/// into the completing tick (Catroid `RepeatAction` parity). The empty-body
/// guard verifies an action-free loop consumes one tick per iteration and never
/// hangs — the highest-value edge case.
@Suite("Stepper loops")
struct StepperLoopTests {
    private let clock = InterpreterClock(tickDelta: 0.05)
    /// 0/0 → NaN root → `FormulaError.notANumber`.
    private let throwing = Formula.binary(.divide, .number(0), .number(0))

    private func moveCount(_ events: [InterpreterEvent]) -> Int {
        events.filter {
            if case .needleMoved = $0 {
                true
            } else {
                false
            }
        }.count
    }

    @Test("repeatLoop(3) runs its body exactly three times, one body brick per tick")
    func repeatRunsBodyThreeTimes() {
        let script = Script(bricks: [
            .repeatLoop(times: .number(3)),
            .moveNSteps(.number(10)),
            .loopEnd
        ])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: clock)

        // Three ticks, one needleMoved each, then finished — no empty exit tick.
        let actor = ActorID(0)
        #expect(interpreter.step() == .ticked([
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 10)))
        ]))
        #expect(interpreter.step() == .ticked([
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 20)))
        ]))
        #expect(interpreter.step() == .ticked([
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 30)))
        ]))
        #expect(interpreter.step() == .finished)
    }

    @Test("nested loops multiply: repeatLoop(2){ repeatLoop(2){ move } } runs 4 times")
    func nestedLoopsMultiply() {
        let script = Script(bricks: [
            .repeatLoop(times: .number(2)), // outer
            .repeatLoop(times: .number(2)), // inner
            .moveNSteps(.number(10)),
            .loopEnd, // inner
            .loopEnd // outer
        ])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: clock)

        let events = interpreter.run(maxTicks: 100)
        #expect(moveCount(events) == 4)
        if case let .needleMoved(_, update) = events.last {
            #expect(update.position == StagePoint(x: 0, y: 40))
        } else {
            Issue.record("expected a final needleMoved event")
        }
    }

    @Test("repeatLoop with a zero, negative, or throwing count runs its body zero times")
    func repeatZeroOrThrowingRunsBodyZeroTimes() {
        for count in [Formula.number(0), .number(-3), throwing] {
            let script = Script(bricks: [
                .repeatLoop(times: count),
                .moveNSteps(.number(10)),
                .loopEnd
            ])
            let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
            var interpreter = Interpreter(program: program, clock: clock)
            #expect(moveCount(interpreter.run(maxTicks: 100)) == 0)
        }
    }

    @Test("forever runs one body brick per tick and is bounded only by maxTicks")
    func foreverBoundedByMaxTicks() {
        let script = Script(bricks: [
            .forever,
            .moveNSteps(.number(10)),
            .loopEnd
        ])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: clock)

        #expect(moveCount(interpreter.run(maxTicks: 5)) == 5)
        #expect(!interpreter.isFinished) // never terminates on its own
    }

    // MARK: Empty-body guard (story omits it; highest-value edge)

    @Test("an empty forever body consumes one tick per iteration and never hangs")
    func emptyForeverDoesNotHang() {
        let script = Script(bricks: [.forever, .loopEnd])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: clock)

        // Must return (not hang) with no events, and never finish.
        #expect(interpreter.run(maxTicks: 5) == [])
        #expect(!interpreter.isFinished)
    }

    @Test("an empty repeatLoop body consumes one tick per iteration and then finishes")
    func emptyRepeatDoesNotHang() {
        let script = Script(bricks: [.repeatLoop(times: .number(2)), .loopEnd])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: clock)

        #expect(interpreter.run(maxTicks: 100) == [])
        #expect(interpreter.isFinished) // terminates after its empty iterations
    }

    // MARK: Prior action, THEN an empty loop (swift-code-reviewer regression)

    @Test("an action followed by an empty forever does not hang and never finishes")
    func actionThenEmptyForeverDoesNotHang() {
        // The critical case the isolation tests missed: the move sets the
        // per-tick action flag, so the empty forever must defer at its body entry
        // rather than spin the back-jump inside a single step().
        let script = Script(bricks: [.moveNSteps(.number(10)), .forever, .loopEnd])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: clock)
        let actor = ActorID(0)

        // Tick 1: the move only (forever entry deferred).
        #expect(interpreter.step() == .ticked([
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 10)))
        ]))
        // Subsequent ticks: empty iterations, never finishing.
        #expect(interpreter.step() == .ticked([]))
        #expect(!interpreter.isFinished)
        #expect(interpreter.run(maxTicks: 10) == [])
        #expect(!interpreter.isFinished)
    }

    @Test("an action followed by an empty repeatLoop runs one tick per iteration, not all at once")
    func actionThenEmptyRepeatIsPaced() {
        let script = Script(bricks: [.moveNSteps(.number(10)), .repeatLoop(times: .number(4)), .loopEnd])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: clock)

        // Tick 1 runs the move and must NOT drain the loop — the thread is still
        // running (the empty iterations are paced one per tick, not collapsed).
        _ = interpreter.step()
        #expect(!interpreter.isFinished)
        // It does terminate, having emitted only the one move.
        #expect(interpreter.run(maxTicks: 100) == [])
        #expect(interpreter.isFinished)
    }

    @Test("an empty repeatLoop(2) detects termination one tick after its last iteration (accepted degenerate)")
    func emptyRepeatFinishesOneTickLate() {
        // ADR-018 accepted degenerate (Codex): an action-free repeat consumes one
        // tick per empty iteration (ticks 1 and 2 here), then the exhausted
        // counter-check finishes on tick 3 — one tick later than a non-empty loop,
        // because the empty loopEnd yields before the begin can fold exhaustion in.
        // The alternative fix reintroduces spurious empty ticks on nested-loop
        // entry (the common case), a worse trade.
        let script = Script(bricks: [.repeatLoop(times: .number(2)), .loopEnd])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: clock)

        _ = interpreter.run(maxTicks: 2) // two empty iterations
        #expect(!interpreter.isFinished) // not yet — exhaustion detected next tick
        _ = interpreter.step() // tick 3: exhausted counter marks the thread finished
        #expect(interpreter.isFinished)
    }

    @Test("nested empty loops compound the delay, shifting concurrent geometry (ADR-018 pathological)")
    func nestedEmptyLoopsCompoundDelay() {
        // ADR-018 Codex round-2 pathological divergence: nested count-1 EMPTY loops
        // add a late tick at each enclosing loopEnd, so A's turn only lands on tick 3.
        // Because B shares A's needle, B's first two moves precede the turn (heading 0
        // → (0,10),(0,20)) but its third move is on tick 3, after A's turn that tick,
        // so it runs on heading 90 → (10,20); A then moves on heading 90 → (20,20).
        // This documents our accounting, not Catroid's (which would land elsewhere).
        let scriptA = Script(bricks: [
            .repeatLoop(times: .number(1)),
            .repeatLoop(times: .number(1)),
            .loopEnd,
            .loopEnd,
            .turnRight(.number(90)),
            .moveNSteps(.number(10))
        ])
        let scriptB = Script(bricks: [.moveNSteps(.number(10)), .moveNSteps(.number(10)), .moveNSteps(.number(10))])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [scriptA, scriptB])])])
        var interpreter = Interpreter(program: program, clock: clock)

        guard case let .needleMoved(_, update)? = interpreter.run(maxTicks: 100).last else {
            Issue.record("expected a final needleMoved event")
            return
        }
        #expect(update.position == StagePoint(x: 20, y: 20))
    }
}
