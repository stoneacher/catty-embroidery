import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// Slice 6 of the language-test runner (brief D8): WaitTillIdle releases when
/// every other script has ended, observed live at its position in the tick.
/// Catroid's action is true iff every actor runs no script, or only the one
/// holding this action (`content/actions/WaitTillIdleAction.java:35-58`); libgdx
/// acts actors in order and drops a finished sequence as it goes.
struct WaitTillIdleTests {
    private static let clock = InterpreterClock(tickDelta: 1.0 / 60)
    private static let move = ScriptStep.brick(.moveNSteps(.number(10)))
    private static let waiter: [ScriptStep] = [.waitTillIdle, .finishStage]

    private static func object(_ scripts: [[ScriptStep]]) -> HarnessObject {
        HarnessObject(Object(name: "A", startHeading: 90), scripts: scripts)
    }

    private func run(_ objects: [HarnessObject], budget: Int = 40) -> HarnessRun {
        var interpreter = Interpreter(harness: objects, clock: Self.clock)
        return interpreter.runHarness(budget: budget)
    }

    /// A worker visited before the waiter, finishing in this tick, releases it in
    /// this tick: the poll (tick 1) and then the finish (tick 2).
    @Test func aWorkerVisitedEarlierReleasesInTheSameTick() {
        let result = run([Self.object([[Self.move], Self.waiter])])
        #expect(result.outcome == .passed)
        #expect(result.ticks == 2)
    }

    /// A worker visited before the waiter but still running keeps it waiting, until
    /// the tick it ends in: there it is visited first, so the release is that tick.
    @Test func anEarlierWorkerStillRunningKeepsItWaiting() {
        let result = run([Self.object([[Self.move, Self.move, Self.move], Self.waiter])])
        #expect(result.outcome == .passed)
        #expect(result.ticks == 4) // worker ends in tick 3, released in 3, finish in 4
        #expect(result.events.count == 3)
    }

    /// A worker visited after the waiter is still running at the poll, so the
    /// release comes a tick later. The corpus's
    /// `testWaitUntilAllOtherScriptsHaveStopped` has this ordering.
    @Test func aWorkerVisitedLaterReleasesInTheNextTick() {
        let result = run([Self.object([Self.waiter, [Self.move]])])
        #expect(result.outcome == .passed)
        #expect(result.ticks == 3)
    }

    /// Every object's scripts count, not just the waiter's own.
    @Test func anotherObjectsScriptKeepsItWaiting() {
        let worker = Self.object([[Self.move, Self.move, Self.move]])
        let result = run([Self.object([Self.waiter]), worker])
        #expect(result.outcome == .passed)
        #expect(result.ticks == 5) // worker ends in tick 3, seen at tick 4, finish in 5
    }

    /// An object with no scripts (Catroid's Background in the corpus test) is idle.
    @Test func anObjectWithNoScriptsIsIdle() {
        let result = run([Self.object([]), Self.object([Self.waiter])])
        #expect(result.outcome == .passed)
        #expect(result.ticks == 2)
    }

    /// Neither waiter counts the other as idle, as neither of Catroid's actors
    /// holds only its own WaitTillIdle.
    @Test func twoWaitersNeverReleaseEachOther() {
        #expect(run([Self.object([Self.waiter, Self.waiter])]).outcome == .budgetExhausted)
        #expect(run([Self.object([Self.waiter]), Self.object([Self.waiter])]).outcome == .budgetExhausted)
    }

    /// A poll is one action: alone it takes its tick even when idle at once, and
    /// after another action it waits for the next tick.
    @Test func aPollIsOneAction() {
        #expect(run([Self.object([Self.waiter])]).ticks == 2)
        #expect(run([Self.object([[Self.move] + Self.waiter])]).ticks == 3)
    }

    /// While waiting it polls every tick, and releases on the first idle one.
    @Test func itPollsUntilTheOthersEnd() {
        let worker = Array(repeating: Self.move, count: 6)
        let result = run([Self.object([Self.waiter, worker])])
        #expect(result.outcome == .passed)
        #expect(result.ticks == 8) // worker ends in tick 6, seen at 7, finish in 8
    }
}
