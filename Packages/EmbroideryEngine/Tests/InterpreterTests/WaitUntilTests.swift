import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// Variables slice 5 (brief D5, D9; ADR-049): WaitUntil as Catroid's `WaitUntilAction`
/// (`WaitUntilAction.java:52-71`) inside libgdx's one-child-per-frame sequence.
///
/// - Each tick it waits is one poll and costs the tick, like `wait`; it completes in the tick
///   it finds the condition true, emitting one `.waited`, and the next brick runs a tick later.
/// - Reached after an action in the same tick, it first polls in the next tick.
/// - **Truthiness** is `interpretBoolean`, i.e. `interpretDouble(...).intValue() != 0`
///   (`Formula.java:258-259`): `0.5` is false. A condition that does not interpret keeps it
///   waiting (`WaitUntilAction.java:66-69`).
/// - **Pinned divergence:** Catroid polls at most every 0.02 s (`:58-63`), so at 60 frames a
///   second every other frame; here every tick, whatever the clock.
@Suite("WaitUntil execution")
struct WaitUntilTests {
    static func tag(_ y: Double) -> Brick {
        .setY(.number(y))
    }

    @Test("a WaitUntil completes in the tick it finds the condition true, and the next brick runs a tick later")
    func completesThenNext() {
        #expect(tagProfile(scripts: [[.waitUntil(condition: .constant(.true)), Self.tag(2)]]) == [[], [2]])
    }

    /// After an action it does not poll in that tick: a condition already true still costs the
    /// next tick. Polling (and completing) in the acted tick would let the next brick run a tick
    /// early.
    @Test("a WaitUntil reached after an action first polls in the next tick")
    func deferredAfterAnAction() {
        #expect(tagProfile(scripts: [[Self.tag(1), .waitUntil(condition: .constant(.true)), Self.tag(2)]])
            == [[1], [], [2]])
    }

    /// B's wait takes ticks 1–2 and its write lands in tick 3 after A's poll; A sees it in tick 4.
    static func released(by condition: Formula, writing name: String, _ value: Double) -> [[Double]] {
        tagProfile(scripts: [
            [.waitUntil(condition: condition), Self.tag(2)],
            [.wait(seconds: .number(0.1)), .setVariable(name: name, to: .number(value))]
        ])
    }

    @Test("a condition that does not interpret keeps it waiting until it does")
    func nanKeepsWaiting() {
        #expect(Self.released(by: .binary(.divide, .number(1), .variable("w")), writing: "w", 1)
            == [[], [], [], [], [2]])
    }

    @Test("0.5 is false: the condition truncates, as Catroid's interpretBoolean does")
    func halfIsFalse() {
        #expect(Self.released(by: .binary(.plus, .number(0.5), .variable("v")), writing: "v", 1)
            == [[], [], [], [], [2]])
    }

    @Test("a WaitUntil emits one waited event, when it completes")
    func oneWaitedEvent() {
        var interpreter = Interpreter(
            program: Program(scenes: [Scene(objects: [Object(scripts: [
                Script(bricks: [.waitUntil(condition: .binary(.equal, .variable("v"), .number(1)))]),
                Script(bricks: [.wait(seconds: .number(0.1)), .setVariable(name: "v", to: .number(1))])
            ])])]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        let events = interpreter.run(maxTicks: 20)
        #expect(events.count { if case .waited = $0 { true } else { false } } == 2, "one per wait brick")
    }

    @Test("a WaitUntil that never holds waits one tick per poll and never spins")
    func neverHolds() {
        var interpreter = Interpreter(
            program: Program(scenes: [Scene(objects: [Object(scripts: [
                Script(bricks: [.waitUntil(condition: .constant(.false)), Self.tag(2)])
            ])])]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        for _ in 0 ..< 5 {
            #expect(interpreter.step() == .ticked([]))
        }
        #expect(!interpreter.isFinished)
    }

    /// Every tick, not every 0.02 s: at a 1/60 s clock Catroid would poll every other frame.
    @Test("it polls every tick, whatever the clock (pinned divergence from Catroid's 0.02 s throttle)")
    func pollsEveryTick() {
        var interpreter = Interpreter(
            program: Program(scenes: [Scene(objects: [Object(scripts: [
                Script(bricks: [.waitUntil(condition: .constant(.true)), Self.tag(2)])
            ])])]),
            clock: InterpreterClock(tickDelta: 1.0 / 60)
        )
        let first = interpreter.step()
        #expect(first == .ticked([.waited(actor: ActorID(0))]))
    }

    // MARK: - Codex slice review of slice 5

    @Test("−1 and MAX hold at once; −0.99 waits until it truncates to something nonzero")
    func negativeAndLargeTruthiness() {
        for holding in [Formula.number(-1), .number(.greatestFiniteMagnitude)] {
            #expect(tagProfile(scripts: [[.waitUntil(condition: holding), Self.tag(2)]]) == [[], [2]])
        }
        // −0.99 − v: −0.99 truncates to 0; with v = 1 it is −1.99, which truncates to −1.
        #expect(Self.released(by: .binary(.minus, .number(-0.99), .variable("v")), writing: "v", 1)
            == [[], [], [], [], [2]])
    }

    @Test("a WaitUntil after a wait, as a loop body's last brick, and as an If branch's last brick")
    func positions() {
        let afterAWait: [Brick] = [.wait(seconds: .number(0.1)), .waitUntil(condition: .constant(.true)), Self.tag(2)]
        #expect(tagProfile(scripts: [afterAWait]) == [[], [], [], [2]])
        #expect(tagProfile(scripts: [[
            .repeatLoop(times: .number(2)), .waitUntil(condition: .constant(.true)), .loopEnd, Self.tag(9)
        ]]) == [[], [], [9]])
        #expect(tagProfile(scripts: [[
            .ifThen(condition: .constant(.true)), .waitUntil(condition: .constant(.true)), .ifEnd, Self.tag(9)
        ]]) == [[], [9]])
        var interpreter = Interpreter(
            program: Program(scenes: [Scene(objects: [Object(scripts: [
                Script(bricks: [.waitUntil(condition: .constant(.true))])
            ])])]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        #expect(stepToCompletion(&interpreter).count == 1, "a script ending in one finishes in its tick")
    }

    @Test("a WaitUntil reads a project variable another object wrote, in creation order")
    func crossObject() {
        let reader = Object(name: "R", scripts: [Script(bricks: [
            .waitUntil(condition: .binary(.equal, .variable("v"), .number(1))), Self.tag(2)
        ])])
        let writer = Object(name: "W", scripts: [Script(bricks: [.setVariable(name: "v", to: .number(1))])])
        let project = [Variable(name: "v")]
        #expect(tagProfile(Program(scenes: [Scene(objects: [reader, writer])], variables: project)) == [[], [], [2]])
        #expect(tagProfile(Program(scenes: [Scene(objects: [writer, reader])], variables: project)) == [[], [2]])
        // Read in the waiting object's own scope: an object 0 whose own `v` shadows the project's
        // must not decide it (found by mutation).
        let shadow = Object(name: "S", variables: [Variable(name: "v")], scripts: [])
        #expect(tagProfile(Program(scenes: [Scene(objects: [shadow, reader, writer])], variables: project))
            == [[], [], [2]])
    }

    /// The event belongs to the tick of completion and to the waiting object, not to the first
    /// poll or to object 0.
    @Test("the waited event comes in the tick of completion, from the waiting object")
    func waitedEventTimingAndActor() {
        var interpreter = Interpreter(
            program: Program(scenes: [Scene(objects: [
                Object(name: "idle", scripts: [Script(bricks: [.setVariable(name: "x", to: .number(0))])]),
                Object(name: "waiter", scripts: [Script(bricks: [
                    .waitUntil(condition: .binary(.equal, .variable("v"), .number(1)))
                ])]),
                Object(name: "writer", scripts: [Script(bricks: [
                    .wait(seconds: .number(0.1)), .setVariable(name: "v", to: .number(1))
                ])])
            ])], variables: [Variable(name: "v")]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        let ticks = stepToCompletion(&interpreter)
        let waiterEvents = ticks.map { $0.filter { $0 == .waited(actor: ActorID(1)) }.count }
        #expect(waiterEvents == [0, 0, 0, 1])
    }

    /// No state survives an iteration: the second pass waits for a fresh release.
    @Test("a WaitUntil in a loop waits afresh on each pass")
    func reentry() {
        let profile = tagProfile(scripts: [
            [.repeatLoop(times: .number(2)), .waitUntil(condition: .binary(.equal, .variable("v"), .number(1))),
             .setVariable(name: "v", to: .number(0)), Self.tag(1), .loopEnd],
            [.setVariable(name: "v", to: .number(1)), .wait(seconds: .number(0.2)),
             .setVariable(name: "v", to: .number(1))]
        ])
        #expect(profile == [[], [], [], [1], [], [], [], [], [1]])
    }
}
