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

    // MARK: Duplicate names resolve first-match (Codex — matches VariableScope)

    @Test("duplicate project-variable declarations resolve to the first (not the last)")
    func duplicateProjectVariablesUseFirstMatch() {
        let script = Script(bricks: [.moveNSteps(.variable("x"))])
        let program = Program(
            scenes: [Scene(objects: [Object(scripts: [script])])],
            variables: [Variable(name: "x", value: 10), Variable(name: "x", value: 20)]
        )
        var interpreter = Interpreter(program: program, clock: clock)
        // First match wins → 10, as ProgramModel.VariableScope defines; NOT 20.
        #expect(finalPosition(interpreter.run(maxTicks: 100)) == StagePoint(x: 0, y: 10))
    }

    @Test("an object variable shadows a same-named project variable, per object")
    func objectVariableShadowsProjectVariablePerObject() {
        // Object A has its own "n" (=3, shadows project); object B reads project "n" (=100).
        let readN = Script(bricks: [.moveNSteps(.variable("n"))])
        let objectA = Object(name: "a", variables: [Variable(name: "n", value: 3)], scripts: [readN])
        let objectB = Object(name: "b", scripts: [readN])
        let program = Program(
            scenes: [Scene(objects: [objectA, objectB])],
            variables: [Variable(name: "n", value: 100)]
        )
        var interpreter = Interpreter(program: program, clock: clock)

        let events = interpreter.run(maxTicks: 100)
        #expect(events == [
            .needleMoved(actor: ActorID(0), update: NeedleUpdate(position: StagePoint(x: 0, y: 3))),
            .needleMoved(actor: ActorID(1), update: NeedleUpdate(position: StagePoint(x: 0, y: 100)))
        ])
    }

    @Test("writing an object-shadowed variable does not leak into the project scope")
    func writingObjectVariableDoesNotTouchProject() {
        // Object A shadows "n" and overwrites its own copy; object B still sees project "n".
        let objectA = Object(
            name: "a",
            variables: [Variable(name: "n", value: 3)],
            scripts: [Script(bricks: [.setVariable(name: "n", to: .number(7)), .moveNSteps(.variable("n"))])]
        )
        let objectB = Object(name: "b", scripts: [Script(bricks: [.moveNSteps(.variable("n"))])])
        let program = Program(
            scenes: [Scene(objects: [objectA, objectB])],
            variables: [Variable(name: "n", value: 100)]
        )
        var interpreter = Interpreter(program: program, clock: clock)

        // Object A spends tick 1 on setVariable (no event), so B's move (actor 1,
        // still project n = 100) emits before A's move (actor 0, its own n = 7) on
        // tick 2 — the write stayed object-local.
        let events = interpreter.run(maxTicks: 100)
        #expect(events == [
            .needleMoved(actor: ActorID(1), update: NeedleUpdate(position: StagePoint(x: 0, y: 100))),
            .needleMoved(actor: ActorID(0), update: NeedleUpdate(position: StagePoint(x: 0, y: 7)))
        ])
    }
}
