import ProgramModel

/// One step of a language-test script (brief D3): a brick, or one of the
/// harness bricks that never become `Brick` cases, so they cannot reach the
/// palette or the saved format.
package enum ScriptStep: Sendable, Equatable {
    case brick(Brick)
    case harness(HarnessStep)

    package static func assertEquals(actual: Formula, expected: Formula) -> Self {
        .harness(.assertEquals(actual: actual, expected: expected))
    }

    package static let finishStage = Self.harness(.finishStage)
    package static let exitStage = Self.harness(.exitStage)
}

/// A language-test harness brick: an action like a brick (D6), compiled to
/// `Instruction.harness`.
package enum HarnessStep: Sendable, Equatable {
    /// Catroid `AssertEqualsBrick`; compared by `isSameValue` (D2).
    case assertEquals(actual: Formula, expected: Formula)
    /// Catroid `FinishStageBrick`: the test passed.
    case finishStage
    /// Catroid `ExitStageBrick`: the stage ends without a result (D5).
    case exitStage
}

/// An object for `Interpreter.init(harness:)`: its pose and variables, and its
/// scripts as steps. `object.scripts` is ignored; build it with `scripts: []`. The
/// list given to the interpreter is already flat, in ADR-018's object order.
package struct HarnessObject: Sendable {
    package var object: Object
    package var scripts: [[ScriptStep]]

    package init(_ object: Object, scripts: [[ScriptStep]]) {
        self.object = object
        self.scripts = scripts
    }
}

package struct AssertionFailure: Sendable, Equatable {
    package var objectIndex: Int
    package var scriptIndex: Int
    package var stepIndex: Int
    package var expected: Double
    package var actual: Double

    package init(objectIndex: Int, scriptIndex: Int, stepIndex: Int, expected: Double, actual: Double) {
        self.objectIndex = objectIndex
        self.scriptIndex = scriptIndex
        self.stepIndex = stepIndex
        self.expected = expected
        self.actual = actual
    }

    /// NaN-aware, so a failure carrying NaN equals itself (ADR-006 reflexivity).
    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.objectIndex == rhs.objectIndex && lhs.scriptIndex == rhs.scriptIndex && lhs.stepIndex == rhs.stepIndex
            && lhs.expected.isSameValue(as: rhs.expected) && lhs.actual.isSameValue(as: rhs.actual)
    }
}

/// A language test's run: how it ended, after how many ticks, with what events.
package struct HarnessRun: Sendable, Equatable {
    package var outcome: HarnessOutcome
    package var ticks: Int
    package var events: [InterpreterEvent]

    package init(outcome: HarnessOutcome, ticks: Int, events: [InterpreterEvent] = []) {
        self.outcome = outcome
        self.ticks = ticks
        self.events = events
    }
}

/// How a language test's run ended (brief D5, D6).
package enum HarnessOutcome: Sendable, Equatable {
    case passed
    case assertionFailed(AssertionFailure)
    /// Every thread ended, or ExitStage ran, before any result.
    case endedWithoutResult
    /// The budget ran out first.
    case budgetExhausted
}

/// The first ending a run reaches, latched: Catroid's `finishStage` and
/// `finishTestWithResult` both act only while the stage is not yet finishing
/// (`StageActivity.java:482-497`), so the first wins and later ones are ignored.
enum HarnessEnding: Sendable, Equatable {
    case result(HarnessOutcome)
    case exited
}

struct HarnessState: Sendable {
    var ending: HarnessEnding?
    /// Set once the tick an ending landed in has finished; no tick runs after.
    var stopped = false
}

extension Interpreter {
    /// Brief D6: a deterministic policy chosen after Catroid's 10 s timeout, not a
    /// translation of it (Codex brief review, finding 7). A result in tick 600
    /// counts; reaching tick 601 is `budgetExhausted`.
    package static let harnessBudget = 600

    /// An interpreter over language-test scripts: each object's pose and variables,
    /// and its scripts as steps (its own `scripts` are ignored).
    package init(harness objects: [HarnessObject], clock: InterpreterClock, variables: [Variable] = []) {
        self.init(objects: objects, variables: variables, clock: clock)
    }

    /// Runs until the first ending's tick finishes, every thread has ended, or the
    /// budget is spent, and reports which, with the ticks used and every event.
    package mutating func runHarness(budget: Int = Interpreter.harnessBudget) -> HarnessRun {
        var events: [InterpreterEvent] = []
        var ticks = 0
        while ticks < budget, case let .ticked(batch) = step() {
            events += batch
            ticks += 1
        }
        let outcome: HarnessOutcome = switch harness.ending {
        case let .result(outcome): outcome
        case .exited: .endedWithoutResult
        case nil: threads.allSatisfy(\.finished) ? .endedWithoutResult : .budgetExhausted
        }
        return HarnessRun(outcome: outcome, ticks: ticks, events: events)
    }

    /// A harness step is one action (D6): deferred when the thread already acted
    /// this tick, like any brick. A failing assert latches its failure and keeps
    /// its thread where it is (`AssertEqualsAction.kt:38`: `act` returns false).
    mutating func performHarness(_ index: Int, _ step: HarnessStep, acted: inout Bool) -> Bool {
        if acted {
            return false
        }
        acted = true
        let thread = threads[index]
        switch step {
        case let .assertEquals(actual, expected):
            let scope = scope(forObjectAt: thread.objectIndex)
            let actualValue = actual.interpretValue(scope: scope)
            let expectedValue = expected.interpretValue(scope: scope)
            guard actualValue.isSameValue(as: expectedValue) else {
                latch(.result(.assertionFailed(AssertionFailure(
                    objectIndex: thread.objectIndex, scriptIndex: thread.scriptIndex,
                    stepIndex: thread.instructionPointer, expected: expectedValue, actual: actualValue
                ))))
                return false
            }
        case .finishStage:
            latch(.result(.passed))
        case .exitStage:
            latch(.exited)
        }
        threads[index].instructionPointer += 1
        return true
    }

    private mutating func latch(_ ending: HarnessEnding) {
        if harness.ending == nil {
            harness.ending = ending
        }
    }
}
