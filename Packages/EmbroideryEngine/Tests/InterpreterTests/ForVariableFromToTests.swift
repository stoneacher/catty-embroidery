import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// Variables slice 6 (brief D10; ADR-049): ForVariableFromTo as Catroid's
/// `ForVariableFromToAction` (`ForVariableFromToAction.java:47-117`) in libgdx's
/// one-child-per-frame sequence.
///
/// - On its own first act it reads `from` and `to` once, as `interpretDouble(...).intValue()`
///   (truncate, saturate to Int32), sets the step to `+1` if `from ≤ to` else `−1`, writes `from`
///   into the variable and runs the body's first brick in the same tick. Bounds that do not
///   interpret skip the loop, leave the variable alone and take the tick.
/// - After every pass it re-reads the variable — edits in the body count — and exits if
///   `step > 0 ∧ v ≥ to` or `step < 0 ∧ v ≤ to`, else adds the step. So the body always runs at
///   least once, and `to` is fixed at the start.
/// - An exit that comes in a tick where nothing acted (an empty body) takes that tick, as
///   Catroid's action returns in its own frame.
/// - The variable resolves like `setVariable` (object shadows project; unknown → object-local);
///   an empty name keeps its count in the loop and writes no variable (brief D10).
@Suite("ForVariableFromTo execution")
struct ForVariableFromToTests {
    static func tag(_ y: Double) -> Brick {
        .setY(.number(y))
    }

    static func loop(from: Formula, to: Formula, _ body: [Brick], name: String = "i") -> [Brick] {
        [.forVariableFromTo(name: name, from: from, to: to)] + body + [.loopEnd]
    }

    static let showI = Brick.setY(.variable("i"))

    @Test("it counts up or down by one, the first body brick sees from, and the next brick waits a tick")
    func countsByOne() {
        #expect(tagProfile(scripts: [Self.loop(from: .number(1), to: .number(3), [Self.showI]) + [Self.tag(9)]])
            == [[1], [2], [3], [9]])
        #expect(tagProfile(scripts: [Self.loop(from: .number(3), to: .number(1), [Self.showI]) + [Self.tag(9)]])
            == [[3], [2], [1], [9]])
    }

    @Test("from equal to to runs the body once")
    func runsOnce() {
        #expect(tagProfile(scripts: [Self.loop(from: .number(5), to: .number(5), [Self.showI])]) == [[5]])
    }

    /// `from == to` counts up (`from ≤ to`): a body that drops the variable below `to` once makes
    /// the loop climb back, where a `−1` step would end at once (found by mutation).
    @Test("from equal to to counts up")
    func equalBoundsCountUp() {
        let bricks = Self.loop(from: .number(5), to: .number(5), [
            Self.showI,
            .ifThen(condition: .binary(.equal, .variable("f"), .number(0))),
            .setVariable(name: "f", to: .number(1)), .setVariable(name: "i", to: .number(3)),
            .ifEnd
        ])
        #expect(tagProfile(scripts: [bricks]).flatMap(\.self) == [5, 4, 5])
    }

    @Test("the bounds truncate toward zero")
    func truncation() {
        #expect(tagProfile(scripts: [Self.loop(from: .number(1.9), to: .number(3.9), [Self.showI])]).flatMap(\.self)
            == [1, 2, 3])
        #expect(tagProfile(scripts: [Self.loop(from: .number(-1.9), to: .number(-3.9), [Self.showI])]).flatMap(\.self)
            == [-1, -2, -3])
    }

    @Test("an edit to the variable in the body counts")
    func bodyEditCounts() {
        let bricks = Self.loop(
            from: .number(1), to: .number(5), [Self.showI, .changeVariableBy(name: "i", value: .number(1))]
        )
        #expect(tagProfile(scripts: [bricks]).flatMap(\.self) == [1, 3, 5])
    }

    @Test("to is read once at the start")
    func toIsFixed() {
        let bricks: [Brick] = [.setVariable(name: "n", to: .number(3))]
            + Self.loop(from: .number(1), to: .variable("n"), [Self.showI, .setVariable(name: "n", to: .number(10))])
        #expect(tagProfile(scripts: [bricks]).flatMap(\.self) == [1, 2, 3])
    }

    @Test("bounds that do not interpret skip the loop, leave the variable alone and take the tick")
    func nanBoundsSkip() {
        let bricks: [Brick] = [.setVariable(name: "i", to: .number(7))]
            + Self.loop(from: .binary(.divide, .number(0), .number(0)), to: .number(3), [Self.showI]) + [Self.showI]
        #expect(tagProfile(scripts: [bricks]) == [[], [], [7]])
    }

    @Test("the bounds saturate to Int32")
    func saturation() {
        let max = Formula.number(.greatestFiniteMagnitude)
        #expect(tagProfile(scripts: [Self.loop(from: max, to: max, [Self.showI])]) == [[Double(Int32.max)]])
    }

    @Test("a For re-starts from from each time an outer loop re-enters it")
    func reentry() {
        let bricks: [Brick] = [.repeatLoop(times: .number(2))]
            + Self.loop(from: .number(1), to: .number(2), [Self.showI]) + [.loopEnd]
        #expect(tagProfile(scripts: [bricks]).flatMap(\.self) == [1, 2, 1, 2])
    }

    /// One empty pass per tick, and the exit takes its tick: Catroid ends in frame 3, and the
    /// next brick runs in frame 4.
    @Test("an empty body counts one pass per tick, and the exit takes its tick")
    func emptyBody() {
        #expect(tagProfile(scripts: [Self.loop(from: .number(1), to: .number(3), []) + [Self.tag(9)]])
            == [[], [], [], [9]])
    }

    /// The loop writes the project's `i` when the object has none, and the object's own when it
    /// declares one; B reads the project's.
    @Test("the variable resolves like Set variable: object first, then project")
    func resolution() {
        func run(_ counter: Object) -> [[Double]] {
            let reader = Object(name: "B", scripts: [Script(bricks: [.wait(seconds: .number(0.25)), Self.showI])])
            return tagProfile(Program(scenes: [Scene(objects: [counter, reader])], variables: [Variable(name: "i")]))
        }
        let plain = Object(name: "A", scripts: [Script(bricks: Self.loop(from: .number(1), to: .number(3), []))])
        #expect(run(plain).last == [3])
        var shadowing = plain
        shadowing.variables = [Variable(name: "i")]
        #expect(run(shadowing).last == [0])
    }

    /// Catroid counts into a hidden dummy variable no formula can reach; a store key `""` would
    /// be readable through `.variable("")`, which the file format round-trips (Codex brief review).
    @Test("an empty name counts inside the loop and writes no variable")
    func emptyName() {
        let bricks = Self.loop(from: .number(1), to: .number(1), [.setY(.variable(""))], name: "")
        #expect(tagProfile(scripts: [bricks]) == [[0]])
    }

    // MARK: - Codex slice round: test gaps

    @Test("nested Fors keep separate state, and an inner exit leaves the outer running")
    func nested() {
        let inner = Self.loop(from: .number(1), to: .number(2), [Self.showI, .setY(.variable("j"))], name: "j")
        let bricks = Self.loop(from: .number(1), to: .number(2), inner, name: "i")
        #expect(tagProfile(scripts: [bricks]).flatMap(\.self) == [1, 1, 1, 2, 2, 1, 2, 2])
    }

    /// The inner loop leaves the shared `i` at 1 every pass, so the outer never reaches 3 — as in
    /// Catroid, where both actions write the same variable.
    @Test("nested Fors on one variable interact through it")
    func nestedSharedName() {
        let inner = Self.loop(from: .number(1), to: .number(1), [])
        #expect(!Self.finishes(Self.loop(from: .number(1), to: .number(3), [Self.showI] + inner)))
    }

    @Test("an unnamed loop counts every pass without a variable")
    func unnamedPasses() {
        let bricks = Self.loop(from: .number(1), to: .number(3), [.setY(.variable(""))], name: "") + [Self.tag(9)]
        #expect(tagProfile(scripts: [bricks]) == [[0], [0], [0], [9]])
    }

    @Test("an unnamed loop counts down too")
    func unnamedDescending() {
        let bricks = Self.loop(from: .number(3), to: .number(1), [Self.tag(1)], name: "") + [Self.tag(9)]
        #expect(tagProfile(scripts: [bricks]) == [[1], [1], [1], [9]])
    }

    /// A For in the second object reads its bounds and counter, and writes, in its own scope —
    /// every other test runs the loop in object 0 (`swift-code-reviewer`, slice 6).
    @Test("a For in a later object reads and writes its own variables")
    func laterObject() {
        let idle = Object(name: "A", scripts: [Script(bricks: [])])
        var counter = Object(name: "B", scripts: [Script(bricks: [.setVariable(name: "n", to: .number(3))]
                + Self.loop(from: .number(1), to: .variable("n"), [Self.showI]))])
        counter.variables = [Variable(name: "i"), Variable(name: "n")]
        let program = Program(scenes: [Scene(objects: [idle, counter])], variables: [Variable(name: "i")])
        #expect(tagProfile(program).flatMap(\.self) == [1, 2, 3])
    }

    @Test("a to that does not interpret skips the loop and leaves the variable alone")
    func nanToSkips() {
        let bricks: [Brick] = [.setVariable(name: "i", to: .number(7))]
            + Self.loop(from: .number(1), to: .binary(.divide, .number(0), .number(0)), [Self.showI]) + [Self.showI]
        #expect(tagProfile(scripts: [bricks]) == [[], [], [7]])
    }

    @Test("both bounds are read before the variable is written")
    func boundsBeforeWrite() {
        let bricks: [Brick] = [.setVariable(name: "i", to: .number(3))]
            + Self.loop(from: .number(1), to: .variable("i"), [Self.showI])
        #expect(tagProfile(scripts: [bricks]).flatMap(\.self) == [1, 2, 3])
    }

    @Test("a fractional variable steps by one and is compared as it is")
    func fractionalVariable() {
        let half = Brick.changeVariableBy(name: "i", value: .number(0.5))
        #expect(tagProfile(scripts: [Self.loop(from: .number(1), to: .number(3), [Self.showI, half])])
            .flatMap(\.self) == [1, 2.5])
    }

    /// Wait until ends its pass's tick; the next pass waits for the following tick.
    @Test("a blocking body brick keeps the loop's state")
    func blockingBody() {
        let holds = Brick.waitUntil(condition: .binary(.equal, .number(1), .number(1)))
        #expect(tagProfile(scripts: [Self.loop(from: .number(1), to: .number(2), [holds, Self.showI]) + [Self.tag(9)]])
            == [[], [1], [], [2], [9]])
    }

    @Test("a For ending an If branch or an outer loop's body folds into its last tick")
    func lastInBlock() {
        let once = Self.loop(from: .number(1), to: .number(2), [Self.showI])
        let ifBranch: [Brick] = [.ifThen(condition: .binary(.smallerThan, .number(1), .number(2)))] + once + [.ifEnd]
        #expect(tagProfile(scripts: [ifBranch + [Self.tag(9)]]) == [[1], [2], [9]])
        let outer: [Brick] = [.repeatLoop(times: .number(2)), Self.tag(8)]
            + Self.loop(from: .number(1), to: .number(1), [Self.showI]) + [.loopEnd]
        #expect(tagProfile(scripts: [outer]) == [[8], [1], [8], [1]])
    }

    /// Script B runs after A in each tick: its write lands between A's passes.
    @Test("another script's write to the counter counts at the next pass's end")
    func crossScriptCounter() {
        let counter = Self.loop(from: .number(1), to: .number(5), [Self.showI])
        #expect(tagProfile(scripts: [counter, [.setVariable(name: "i", to: .number(4))]]) == [[1], [4], [5]])
    }

    /// The head after an action reads its bounds next tick, after B has written `n`.
    @Test("a head deferred after an action reads bounds another script wrote meanwhile")
    func deferredBounds() {
        let counter = [Self.tag(1)] + Self.loop(from: .number(1), to: .variable("n"), [Self.showI])
        #expect(tagProfile(scripts: [counter, [.setVariable(name: "n", to: .number(2))]]) == [[1], [1], [2]])
    }

    @Test("an undeclared variable is created on the object, unseen by others")
    func undeclaredIsObjectLocal() {
        let counting = Self.loop(from: .number(1), to: .number(3), [], name: "k") + [.setY(.variable("k"))]
        let counter = Object(name: "A", scripts: [Script(bricks: counting)])
        let reader = Object(name: "B", scripts: [Script(bricks: [.wait(seconds: .number(0.5)), .setY(.variable("k"))])])
        #expect(tagProfile(Program(scenes: [Scene(objects: [counter, reader])])).flatMap(\.self) == [3, 0])
    }

    /// Above 2^53 adding one changes nothing; at −2^53 it still does. Catroid's raw `Double` step.
    @Test("the step is raw Double addition, which stops progressing beyond 2^53", arguments: [
        (-9_007_199_254_740_992.0, -9_007_199_254_740_991.0),
        (-18_014_398_509_481_984.0, -18_014_398_509_481_984.0)
    ])
    func doublePrecision(_ start: Double, _ next: Double) {
        let bricks = Self.loop(from: .number(1), to: .number(3), [
            .ifThen(condition: .binary(.equal, .variable("f"), .number(0))),
            .setVariable(name: "f", to: .number(1)), .setVariable(name: "i", to: .number(start)),
            .ifEnd,
            Self.showI
        ])
        var interpreter = Interpreter(
            program: Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: bricks)])])]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        var shown: [Double] = []
        while shown.count < 2, case let .ticked(batch) = interpreter.step() {
            shown += batch.compactMap { if case let .needleMoved(_, update) = $0 { update.position.y } else { nil } }
        }
        #expect(shown == [start, next])
    }

    /// All three of PR 2b's bricks in one program (Codex, PR 2b handover). A polls the wait in T1
    /// while B sets `go`; the wait completes in T2 and B moves the counter to 2; T3 shows 2 and
    /// the For exits; T4 sets `done` and the RepeatUntil exits at its end; T5 runs the tail.
    @Test("RepeatUntil, For and WaitUntil compose across scripts")
    func composition() {
        let flag = { (name: String) in Formula.binary(.equal, .variable(name), .number(1)) }
        let inner = Self.loop(from: .number(1), to: .number(2), [.waitUntil(condition: flag("go")), Self.showI])
        let counter: [Brick] = [.repeatUntil(condition: flag("done"))] + inner
            + [.setVariable(name: "done", to: .number(1)), .loopEnd, Self.tag(9)]
        let other: [Brick] = [.setVariable(name: "go", to: .number(1)), .setVariable(name: "i", to: .number(2))]
        #expect(tagProfile(scripts: [counter, other]) == [[], [], [2], [], [9]])
    }

    // MARK: - Direction and non-finite values (Codex brief review, finding 3)

    static func finishes(_ bricks: [Brick]) -> Bool {
        var interpreter = Interpreter(
            program: Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: bricks)])])]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        _ = interpreter.run(maxTicks: 100)
        return interpreter.isFinished
    }

    /// Twice by ±MAX makes ±∞. Up, +∞ exits and −∞ never does; down, the reverse. A value at MAX
    /// does not move by one (`MAX − 1 == MAX`), so a loop held there never ends. All as Catroid's
    /// raw `Double` comparison and step.
    @Test("non-finite and non-progressing values follow the directional exit", arguments: [
        (1.0, 3.0, Double.greatestFiniteMagnitude, true),
        (1.0, 3.0, -Double.greatestFiniteMagnitude, false),
        (3.0, 1.0, -Double.greatestFiniteMagnitude, true),
        (3.0, 1.0, Double.greatestFiniteMagnitude, false)
    ])
    func directionTable(_ from: Double, _ to: Double, _ push: Double, _ ends: Bool) {
        let bricks = Self.loop(from: .number(from), to: .number(to), [
            .changeVariableBy(name: "i", value: .number(push)), .changeVariableBy(name: "i", value: .number(push))
        ])
        #expect(Self.finishes(bricks) == ends)
    }

    @Test("a variable held at −MAX in an ascending loop never progresses")
    func nonProgress() {
        #expect(!Self.finishes(Self.loop(from: .number(1), to: .number(3), [
            .setVariable(name: "i", to: .number(-.greatestFiniteMagnitude))
        ])))
    }
}
