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
}
