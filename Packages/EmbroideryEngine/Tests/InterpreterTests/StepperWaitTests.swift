import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// US-205 test-plan item 3: `wait(seconds:)` measured against the injected
/// logical clock (ADR-018). The thread accumulates `tickDelta` per tick and
/// resumes once elapsed ≥ duration — occupying `ceil(seconds / tickDelta)` ticks
/// for `seconds > 0`, and 1 tick for a zero / throwing formula (Catroid
/// `WaitAction` duration-0 fallback). No wall-clock anywhere.
@Suite("Stepper wait")
struct StepperWaitTests {
    /// 0/0 → NaN root → `FormulaError.notANumber`.
    private let throwing = Formula.binary(.divide, .number(0), .number(0))

    @Test("wait(0.1) under tickDelta 0.05 blocks for exactly two ticks, then resumes")
    func waitBlocksForCeilTicks() {
        let script = Script(bricks: [
            .wait(seconds: .number(0.1)),
            .moveNSteps(.number(10))
        ])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: InterpreterClock(tickDelta: 0.05))
        let actor = ActorID(0)

        // Tick 1: still waiting (elapsed 0.05 < 0.1) — no event.
        #expect(interpreter.step() == .ticked([]))
        // Tick 2: wait completes (elapsed 0.10 ≥ 0.10) — one waited event.
        #expect(interpreter.step() == .ticked([.waited(actor: actor)]))
        // Tick 3: the move resumes.
        #expect(interpreter.step() == .ticked([
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 10)))
        ]))
        #expect(interpreter.step() == .finished)
    }

    @Test("a zero-second wait occupies exactly one tick")
    func zeroWaitOccupiesOneTick() {
        let script = Script(bricks: [
            .wait(seconds: .number(0)),
            .moveNSteps(.number(10))
        ])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: InterpreterClock(tickDelta: 0.05))
        let actor = ActorID(0)

        #expect(interpreter.step() == .ticked([.waited(actor: actor)]))
        #expect(interpreter.step() == .ticked([
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 10)))
        ]))
    }

    @Test("a throwing wait formula degrades to a one-tick wait (duration 0)")
    func throwingWaitOccupiesOneTick() {
        let script = Script(bricks: [
            .wait(seconds: throwing),
            .moveNSteps(.number(10))
        ])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: InterpreterClock(tickDelta: 0.05))
        let actor = ActorID(0)

        #expect(interpreter.step() == .ticked([.waited(actor: actor)]))
        #expect(interpreter.step() == .ticked([
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 10)))
        ]))
    }

    @Test("a longer wait scales with tickDelta (0.11 / 0.05 ⇒ three ticks)")
    func waitScalesWithTickDelta() {
        // Deliberately off-boundary: elapsed reaches 0.05, 0.10 (< 0.11), then
        // 0.15 (≥ 0.11) on tick 3 — robust against float accumulation drift.
        let script = Script(bricks: [.wait(seconds: .number(0.11))])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: InterpreterClock(tickDelta: 0.05))

        #expect(interpreter.step() == .ticked([]))
        #expect(interpreter.step() == .ticked([]))
        #expect(interpreter.step() == .ticked([.waited(actor: ActorID(0))]))
        #expect(interpreter.step() == .finished)
    }

    @Test("an exact-ratio wait can drift one tick from ceil (accepted FP accumulation)")
    func exactRatioWaitDriftsFromCeil() {
        // ADR-018 (Codex): the logical clock ACCUMULATES tickDelta (Catroid
        // TemporalAction parity), and accumulation is authoritative over the
        // nominal ceil(seconds/tickDelta). For 0.1 / 0.01, ten binary additions
        // sum to 0.09999999999999999 < 0.1, so the wait completes on tick 11, not
        // the nominal 10. Deterministic and pinned, not a bug.
        let script = Script(bricks: [.wait(seconds: .number(0.1))])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: InterpreterClock(tickDelta: 0.01))

        for _ in 1 ... 10 {
            #expect(interpreter.step() == .ticked([])) // still short of 0.1
        }
        #expect(interpreter.step() == .ticked([.waited(actor: ActorID(0))])) // tick 11
    }
}
