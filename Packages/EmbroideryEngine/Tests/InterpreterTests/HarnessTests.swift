import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// Slice 5 of the language-test runner (brief D2, D3, D5, D6): the language tests'
/// harness bricks run in the interpreter as actions, and a run ends in one result.
struct HarnessTests {
    private static let clock = InterpreterClock(tickDelta: 1.0 / 60)
    private static let move = ScriptStep.brick(.moveNSteps(.number(10)))

    private static func assertEquals(_ actual: Formula, _ expected: Formula) -> ScriptStep {
        .assertEquals(actual: actual, expected: expected)
    }

    private static func object(_ scripts: [[ScriptStep]], variables: [Variable] = []) -> HarnessObject {
        HarnessObject(Object(name: "A", startHeading: 90, variables: variables), scripts: scripts)
    }

    private func run(
        _ objects: [HarnessObject],
        variables: [Variable] = [],
        budget: Int = Interpreter.harnessBudget
    ) -> HarnessRun {
        var interpreter = Interpreter(harness: objects, clock: Self.clock, variables: variables)
        return interpreter.runHarness(budget: budget)
    }

    private func moves(_ run: HarnessRun) -> Int {
        run.events.filter {
            if case .needleMoved = $0 {
                true
            } else {
                false
            }
        }.count
    }

    // MARK: - Results (D5)

    @Test func finishStageAloneIsAPassInOneTick() {
        let result = run([Self.object([[.finishStage]])])
        #expect(result.outcome == .passed)
        #expect(result.ticks == 1)
    }

    @Test func eachHarnessStepIsOneAction() {
        let result = run([Self.object([[Self.assertEquals(.number(1), .number(1)), .finishStage]])])
        #expect(result.outcome == .passed)
        #expect(result.ticks == 2)
    }

    /// Brief D2: `isSameValue` over the normalised values. NaN equals NaN (Catroid's
    /// `"NaN" == "NaN"`), −0 equals +0, and ±∞ is ±MAX after normalisation, as every
    /// Catroid node result is (`normalizeDegeneratedDoubleValues`).
    @Test(arguments: [
        (Formula.number(1), Formula.number(1), true),
        (.number(.nan), .number(.nan), true),
        (.binary(.divide, .number(0), .number(0)), .number(.nan), true),
        (.number(-0.0), .number(0), true),
        (.binary(.mult, .number(1e308), .number(10)), .number(.greatestFiniteMagnitude), true),
        (.number(1), .number(1.000_000_000_000_1), false),
        (.number(.nan), .number(1), false),
        (.number(2), .number(1), false)
    ])
    func assertEqualsComparesBySameValue(actual: Formula, expected: Formula, passes: Bool) {
        let result = run([Self.object([[Self.assertEquals(actual, expected), .finishStage]])])
        #expect((result.outcome == .passed) == passes)
    }

    @Test func aFailureNamesItsPositionAndValues() {
        let failing = Self.assertEquals(.number(2), .number(3))
        let result = run([
            Self.object([[Self.move]]),
            Self.object([[Self.move], [Self.move, failing]])
        ])
        #expect(result.outcome == .assertionFailed(AssertionFailure(
            objectIndex: 1, scriptIndex: 1, stepIndex: 1, expected: 3, actual: 2
        )))
    }

    @Test func aFailureCarriesNaNAsNaN() {
        let result = run([Self.object([[Self.assertEquals(.number(.nan), .number(1))]])])
        guard case let .assertionFailed(failure) = result.outcome else {
            Issue.record("expected a failure, got \(result.outcome)")
            return
        }
        #expect(failure.actual.isNaN)
        #expect(failure == AssertionFailure(objectIndex: 0, scriptIndex: 0, stepIndex: 0, expected: 1, actual: .nan))
    }

    /// The first result is latched and the tick it lands in finishes: every other
    /// thread still takes its action there, and no further tick runs
    /// (`StageActivity.java:490-498`, `StageListener.java:584-593`; Codex brief
    /// review, finding 3).
    @Test(arguments: [true, false])
    func theTickOfTheFirstResultFinishesAndNothingRunsAfter(failingFirst: Bool) {
        let failing = [Self.assertEquals(.number(1), .number(2))]
        let mover = [Self.move, Self.move, Self.move]
        let scripts = failingFirst ? [failing, mover] : [mover, failing]
        let result = run([Self.object(scripts)])
        #expect(result.outcome == .assertionFailed(AssertionFailure(
            objectIndex: 0, scriptIndex: failingFirst ? 0 : 1, stepIndex: 0, expected: 2, actual: 1
        )))
        #expect(result.ticks == 1)
        #expect(moves(result) == 1)
    }

    @Test func theFirstResultWinsWithinOneTick() {
        let failing = [Self.assertEquals(.number(1), .number(2))]
        #expect(run([Self.object([[.finishStage], failing])]).outcome == .passed)
        if case .assertionFailed = run([Self.object([failing, [.finishStage]])]).outcome {} else {
            Issue.record("a failure reported first must win over a later finish in the same tick")
        }
    }

    // MARK: - Ticks (D6)

    /// Seen from a second script that moves once per tick: three harness steps take
    /// three ticks.
    @Test func aHarnessStepCostsOneTickSeenFromASecondScript() {
        let checks = [
            Self.assertEquals(.number(1), .number(1)),
            Self.assertEquals(.number(1), .number(1)),
            .finishStage
        ]
        let result = run([Self.object([checks, Array(repeating: Self.move, count: 10)])])
        #expect(result.outcome == .passed)
        #expect(result.ticks == 3)
        #expect(moves(result) == 3)
    }

    @Test func aHarnessStepAfterAnActionWaitsForTheNextTick() {
        let result = run([Self.object([[Self.move, Self.assertEquals(.number(1), .number(1)), .finishStage]])])
        #expect(result.ticks == 3)
    }

    @Test func aFinishInsideALoopEndsTheRun() {
        let loop: [ScriptStep] = [.brick(.repeatLoop(times: .number(5))), Self.move, .finishStage, .brick(.loopEnd)]
        let result = run([Self.object([loop])])
        #expect(result.outcome == .passed)
        #expect(result.ticks == 2)
        #expect(moves(result) == 1)
    }

    /// `ExitStage` ends the stage without a result (`ExitStageBrick.java:43`), so
    /// the run fails as ended-without-result; one after a finish is never reached.
    @Test func exitStageEndsTheRunWithoutAResult() {
        #expect(run([Self.object([[.exitStage, .finishStage]])]).outcome == .endedWithoutResult)
        #expect(run([Self.object([[.exitStage, .finishStage]])]).ticks == 1)
        #expect(run([Self.object([[.finishStage, .exitStage]])]).outcome == .passed)
    }

    @Test func aRunWhoseThreadsAllEndWithoutAResultFails() {
        let result = run([Self.object([[Self.move]])])
        #expect(result.outcome == .endedWithoutResult)
        #expect(result.ticks == 1)
        #expect(run([]).outcome == .endedWithoutResult)
        #expect(run([]).ticks == 0)
    }

    /// Brief D6: a result reported in tick 600 counts; reaching tick 601 is
    /// `budgetExhausted`, and the ticks used are reported either way.
    @Test func theBudgetIs600TicksAndItsBoundaryIsPinned() {
        func loop(_ count: Double) -> [ScriptStep] {
            [.brick(.repeatLoop(times: .number(count))), Self.move, .brick(.loopEnd), .finishStage]
        }
        #expect(Interpreter.harnessBudget == 600)
        let inTime = run([Self.object([loop(599)])])
        #expect(inTime.outcome == .passed)
        #expect(inTime.ticks == 600)
        let late = run([Self.object([loop(600)])])
        #expect(late.outcome == .budgetExhausted)
        #expect(late.ticks == 600)
        let forever = run([Self.object([[.brick(.forever), Self.move, .brick(.loopEnd)]])], budget: 7)
        #expect(forever.outcome == .budgetExhausted)
        #expect(forever.ticks == 7)
    }

    // MARK: - The interpreter around it

    @Test func afterAResultTheInterpreterIsFinished() {
        var interpreter = Interpreter(harness: [Self.object([[.finishStage, Self.move]])], clock: Self.clock)
        #expect(interpreter.step() == .ticked([]))
        #expect(interpreter.isFinished)
        #expect(interpreter.step() == .finished)
    }

    /// The harness reads the objects' and the project's variables like any brick.
    @Test func harnessFormulasReadVariables() {
        let objectX = [Self.assertEquals(.variable("x"), .number(5)), .finishStage]
        #expect(run([Self.object([objectX], variables: [Variable(name: "x", value: 5)])]).outcome == .passed)
        let projectY = [Self.assertEquals(.variable("y"), .number(7)), .finishStage]
        #expect(run([Self.object([projectY])], variables: [Variable(name: "y", value: 7)]).outcome == .passed)
    }

    /// The object's pose is the one it is given (the importer gives heading 90).
    @Test func theObjectStartsWhereItIsPlaced() {
        let check = [Self.move, Self.assertEquals(.sensor(.objectX), .number(10)), .finishStage]
        #expect(run([Self.object([check])]).outcome == .passed)
    }

    /// An unbalanced script compiles to nothing, as `init(program:)` does (ADR-018).
    @Test func anUnbalancedHarnessScriptIsInert() {
        let result = run([Self.object([[.brick(.loopEnd), .finishStage]])])
        #expect(result.outcome == .endedWithoutResult)
        // An unclosed opener is caught only by validation: the compiler's own stack
        // check sees nothing wrong, and the finish would run (caught by mutation).
        let unclosed = run([Self.object([[.brick(.repeatLoop(times: .number(2))), .finishStage]])])
        #expect(unclosed.outcome == .endedWithoutResult)
    }
}
