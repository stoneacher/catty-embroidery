import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// Slice 6 of the language-test runner (brief D8): WaitTillIdle releases when
/// every other script has ended, observed live at its position in the tick.
/// Catroid's action is true iff every actor runs no script, or only the one
/// holding this action (`content/actions/WaitTillIdleAction.java:35-58`). Each
/// actor's `ThreadScheduler.tick` acts all of its scripts and only then removes
/// the finished ones (`common/ThreadScheduler.java:59-90`): a script that ends on
/// the waiter's own object is still there at the poll, one on an earlier object
/// is gone (Codex slice 6, finding 1).
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

    /// A worker on an earlier object, ending in this tick, is already removed when
    /// the waiter's object acts: released this tick, the poll (1), the finish (2).
    @Test func aWorkerOnAnEarlierObjectReleasesInTheSameTick() {
        let result = run([Self.object([[Self.move]]), Self.object([Self.waiter])])
        #expect(result.outcome == .passed)
        #expect(result.ticks == 2)
    }

    /// A worker earlier on the waiter's *own* object, ending in this tick, is still
    /// in that object's action list at the poll: released a tick later (3).
    @Test func aWorkerEarlierOnTheSameObjectReleasesInTheNextTick() {
        let result = run([Self.object([[Self.move], Self.waiter])])
        #expect(result.outcome == .passed)
        #expect(result.ticks == 3)
    }

    /// A worker before the waiter but still running keeps it waiting: on the same
    /// object it ends in tick 3, is removed after it, release in 4, finish in 5.
    @Test func anEarlierWorkerStillRunningKeepsItWaiting() {
        let result = run([Self.object([[Self.move, Self.move, Self.move], Self.waiter])])
        #expect(result.outcome == .passed)
        #expect(result.ticks == 5)
        #expect(result.events.count == 3)
        let otherObject = run([Self.object([[Self.move, Self.move, Self.move]]), Self.object([Self.waiter])])
        #expect(otherObject.ticks == 4) // removed before the waiter's object acts in 3
    }

    /// An empty script (or one compiled to nothing) ends in its first tick, and is
    /// removed after it: before or after the waiter, the release is tick 2.
    @Test func anEmptyScriptEndsInItsFirstTick() {
        #expect(run([Self.object([[], Self.waiter])]).ticks == 3)
        #expect(run([Self.object([Self.waiter, []])]).ticks == 3)
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
    /// No thread-level rule can see it; this guards against an object-level rewrite
    /// that would require each object to hold a finished-or-own script.
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

    /// Catroid checks only the top-level children of the waiter's script
    /// (`contains(this, true)`, not recursive), and a loop or If wraps its body in a
    /// nested sequence (`RepeatBrick.java:180-192`, `IfLogicBeginBrick.java:192-212`):
    /// a nested waiter never releases, even alone (review and Codex, slice 6).
    @Test func aNestedWaiterNeverReleases() {
        let once = ScriptStep.brick(.repeatLoop(times: .number(1)))
        let inLoop: [ScriptStep] = [once, .waitTillIdle, .brick(.loopEnd), .finishStage]
        #expect(run([Self.object([inLoop])]).outcome == .budgetExhausted)
        let inIf: [ScriptStep] = [.brick(.ifThen(condition: .number(1))), .waitTillIdle, .brick(.ifEnd), .finishStage]
        #expect(run([Self.object([inIf])]).outcome == .budgetExhausted)
        let topLevel: [ScriptStep] = [.brick(.repeatLoop(times: .number(1))), Self.move, .brick(.loopEnd)] + Self.waiter
        #expect(run([Self.object([topLevel])]).outcome == .passed)
    }

    /// A thread that latches an ending in the tick a waiter is released ends the run
    /// there (D5); the release never lets the waiter's next step into that tick.
    @Test func anEndingInTheReleaseTickWins() {
        let exitThenWait = run([Self.object([[Self.move, .exitStage]]), Self.object([[.waitTillIdle, .finishStage]])])
        #expect(exitThenWait.outcome == .endedWithoutResult)
        #expect(exitThenWait.ticks == 2)
        let finishThenWait = run([Self.object([[.finishStage]]), Self.object([[.waitTillIdle, .exitStage]])])
        #expect(finishThenWait.outcome == .passed)
        #expect(finishThenWait.ticks == 1)
    }
}
