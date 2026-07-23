import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// US-205 test-plan item 6: the mutable variable store. `setVariable` /
/// `changeVariableBy` write to the interpreter's store, visible to later formula
/// evaluation (US-202 scoping). A throwing data formula substitutes 0 (Catroid
/// `SetVariableAction` / `ChangeVariableAction` read through `interpretDouble`,
/// which returns 0 on failure) — deliberately distinct from motion catch-and-skip.
@Suite("Stepper variables")
struct StepperVariableTests {
    private let clock = InterpreterClock(tickDelta: 0.05)
    /// 0/0 → NaN root → `FormulaError.notANumber` (the sole formula error).
    private let throwing = Formula.binary(.divide, .number(0), .number(0))

    private func finalPosition(_ events: [InterpreterEvent]) -> StagePoint? {
        guard case let .needleMoved(_, update) = events.last else { return nil }
        return update.position
    }

    @Test("setVariable then moveNSteps(variable) moves by the stored value")
    func setVariableThenMoveUsesStoredValue() {
        let script = Script(bricks: [
            .setVariable(name: "x", to: .number(5)),
            .moveNSteps(.variable("x"))
        ])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: clock)

        // Heading 0 → move by 5 lands at (0, 5).
        #expect(finalPosition(interpreter.run(maxTicks: 100)) == StagePoint(x: 0, y: 5))
    }

    @Test("changeVariableBy accumulates onto the stored value")
    func changeVariableByAccumulates() {
        let script = Script(bricks: [
            .setVariable(name: "x", to: .number(5)),
            .changeVariableBy(name: "x", value: .number(3)),
            .moveNSteps(.variable("x"))
        ])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: clock)

        #expect(finalPosition(interpreter.run(maxTicks: 100)) == StagePoint(x: 0, y: 8))
    }

    @Test("a project variable seeded on the program is readable and writable")
    func projectVariableRoundTrips() {
        let script = Script(bricks: [
            .changeVariableBy(name: "n", value: .number(2)),
            .moveNSteps(.variable("n"))
        ])
        let program = Program(
            scenes: [Scene(objects: [Object(scripts: [script])])],
            variables: [Variable(name: "n", value: 10)]
        )
        var interpreter = Interpreter(program: program, clock: clock)

        // 10 + 2 = 12.
        #expect(finalPosition(interpreter.run(maxTicks: 100)) == StagePoint(x: 0, y: 12))
    }

    @Test("a throwing setVariable substitutes 0")
    func throwingSetVariableSubstitutesZero() {
        let script = Script(bricks: [
            .setVariable(name: "x", to: .number(9)),
            .setVariable(name: "x", to: throwing), // → 0, not left at 9
            .moveNSteps(.variable("x"))
        ])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: clock)

        #expect(finalPosition(interpreter.run(maxTicks: 100)) == StagePoint(x: 0, y: 0))
    }

    @Test("a throwing changeVariableBy adds 0 (no-op), leaving the value intact")
    func throwingChangeVariableByIsNoOp() {
        let script = Script(bricks: [
            .setVariable(name: "x", to: .number(7)),
            .changeVariableBy(name: "x", value: throwing), // += 0
            .moveNSteps(.variable("x"))
        ])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: clock)

        #expect(finalPosition(interpreter.run(maxTicks: 100)) == StagePoint(x: 0, y: 7))
    }
}
