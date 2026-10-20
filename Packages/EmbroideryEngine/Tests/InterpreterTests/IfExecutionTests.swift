import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// Variables slice 3 (brief D5, D7; ADR-049): If and If/Else execute as Catroid's
/// `IfLogicAction` inside libgdx's one-child-per-frame `SequenceAction` does.
///
/// - **Truthiness** is `interpretDouble(...).toInt() != 0` (`IfLogicAction.kt:43`): truncate
///   toward zero, so `0.5` and `−0.99` are false. A condition that fails to interpret (NaN)
///   runs **neither** branch (`:56-57`).
/// - **Timing:** the condition is read on the If's own first act, so an If reached after an
///   action in the same tick waits for the next one; the condition and the taken branch's first
///   brick then share a tick (`:51-63`). An If whose taken branch runs no action still costs
///   the tick it was read in — and only that one, so nested empty Ifs cost one tick in total.
///
/// Each brick is tagged by the `y` it sets, so a run reads as a profile of ticks.
@Suite("If execution")
struct IfExecutionTests {
    static let nan = Formula.binary(.divide, .number(0), .number(0))

    static func tag(_ y: Double) -> Brick {
        .setY(.number(y))
    }

    /// The `y` tags each tick set, one inner array per tick.
    static func profile(_ bricks: [Brick]) -> [[Double]] {
        profile(scripts: [bricks])
    }

    static func profile(scripts: [[Brick]]) -> [[Double]] {
        profile(Program(scenes: [Scene(objects: [Object(scripts: scripts.map { Script(bricks: $0) })])]))
    }

    /// Bounded, so a mis-lowered jump that loops forever fails the test instead of hanging the
    /// suite (found by mutation: an else bound to the wrong If jumped back to instruction 0).
    static func profile(_ program: Program, sourceLocation: SourceLocation = #_sourceLocation) -> [[Double]] {
        var interpreter = Interpreter(program: program, clock: InterpreterClock(tickDelta: 0.05))
        var ticks: [[Double]] = []
        while case let .ticked(batch) = interpreter.step() {
            ticks.append(batch.compactMap {
                if case let .needleMoved(_, update) = $0 { update.position.y } else { nil }
            })
            guard ticks.count < 200 else {
                Issue.record("the program did not finish within 200 ticks", sourceLocation: sourceLocation)
                break
            }
        }
        return ticks
    }

    // MARK: - D5: truthiness, per opener

    enum Branch: Sendable { case then, otherwise, neither }

    struct Truth: Sendable, CustomTestStringConvertible {
        let condition: Formula, taken: Branch
        var testDescription: String { "\(condition) → \(taken)" }
    }

    static let truths: [Truth] = [
        Truth(condition: .number(1), taken: .then),
        Truth(condition: .number(0), taken: .otherwise),
        Truth(condition: .number(0.5), taken: .otherwise),
        Truth(condition: .number(-0.99), taken: .otherwise),
        Truth(condition: .number(-1), taken: .then),
        Truth(condition: .number(.greatestFiniteMagnitude), taken: .then),
        Truth(condition: .binary(.smallerThan, .number(1), .number(2)), taken: .then),
        Truth(condition: nan, taken: .neither)
    ]

    @Test("an If/Else takes the then-branch, the else-branch or neither, by Catroid's truthiness",
          arguments: truths)
    func ifElseTruthiness(_ truth: Truth) {
        let ran = Self.profile([.ifElse(condition: truth.condition), Self.tag(1), .elseBranch, Self.tag(2), .ifEnd])
            .flatMap(\.self)
        switch truth.taken {
        case .then: #expect(ran == [1])
        case .otherwise: #expect(ran == [2])
        case .neither: #expect(ran.isEmpty)
        }
    }

    /// Both openers build the same `IfLogicAction` (`IfLogicBeginBrick.java:192-212`,
    /// `IfThenLogicBeginBrick.java:155-169`), so each gets its own rows.
    @Test("an If takes its branch or nothing, by the same truthiness", arguments: truths)
    func ifThenTruthiness(_ truth: Truth) {
        let ran = Self.profile([.ifThen(condition: truth.condition), Self.tag(1), .ifEnd]).flatMap(\.self)
        #expect(ran == (truth.taken == .then ? [1] : []))
    }

    // MARK: - D7: ticks

    @Test("the condition and the branch's first brick share a tick")
    func conditionAndFirstBrickShareATick() {
        let bricks: [Brick] = [.ifThen(condition: .constant(.true)), Self.tag(1), .ifEnd, Self.tag(2)]
        #expect(Self.profile(bricks) == [[1], [2]])
    }

    @Test("a branch runs one brick per tick, and the else-jump costs nothing")
    func branchesRunOneBrickPerTick() {
        let bricks: [Brick] = [
            .ifElse(condition: .constant(.true)), Self.tag(1), Self.tag(2), .elseBranch, Self.tag(3), .ifEnd,
            Self.tag(4)
        ]
        #expect(Self.profile(bricks) == [[1], [2], [4]])
        var otherwise = bricks
        otherwise[0] = .ifElse(condition: .constant(.false))
        #expect(Self.profile(otherwise) == [[3], [4]])
    }

    @Test("an If reached after an action waits for the next tick")
    func deferredAfterAnAction() {
        let bricks: [Brick] = [Self.tag(1), .ifThen(condition: .constant(.true)), Self.tag(2), .ifEnd]
        #expect(Self.profile(bricks) == [[1], [2]])
    }

    /// The tick table of brief D7: an If whose taken branch runs no action still costs its tick.
    @Test("an If that runs no action costs the tick it was read in", arguments: [
        [.ifThen(condition: .constant(.true)), .ifEnd, tag(2)],
        [.ifThen(condition: .constant(.false)), tag(1), .ifEnd, tag(2)],
        [.ifElse(condition: .constant(.false)), tag(1), .elseBranch, .ifEnd, tag(2)],
        [.ifThen(condition: nan), tag(1), .ifEnd, tag(2)],
        [.ifThen(condition: .constant(.true)), .repeatLoop(times: .number(0)), tag(1), .loopEnd, .ifEnd, tag(2)],
        // An empty then-branch reaches the end through the else-jump (found by mutation).
        [.ifElse(condition: .constant(.true)), .elseBranch, tag(3), .ifEnd, tag(2)]
    ] as [[Brick]])
    func emptyIfCostsItsTick(_ bricks: [Brick]) {
        #expect(Self.profile(bricks) == [[], [2]])
    }

    @Test("an empty If between two actions makes three ticks")
    func emptyIfBetweenActions() {
        let bricks: [Brick] = [Self.tag(1), .ifThen(condition: .constant(.true)), .ifEnd, Self.tag(2)]
        #expect(Self.profile(bricks) == [[1], [], [2]])
    }

    /// libgdx advances one child per frame, and an empty If is done in the frame it starts, so
    /// nesting adds no frame; yielding at each end would add one per level.
    @Test("nested empty Ifs cost one tick in total")
    func nestedEmptyIfs() {
        let bricks: [Brick] = [
            .ifThen(condition: .constant(.true)), .ifThen(condition: .constant(.true)),
            .ifThen(condition: .constant(.true)), .ifEnd, .ifEnd, .ifEnd, Self.tag(2)
        ]
        #expect(Self.profile(bricks) == [[], [2]])
    }

    /// The end costs a tick only when its If was read in that tick: an If around an empty
    /// `repeat 3` finishes when the loop does, as a bare `repeat 3` does — four ticks either way.
    @Test("an If around a loop costs no tick of its own")
    func ifAroundALoop() {
        let bare = Self.profile([.repeatLoop(times: .number(3)), .loopEnd, Self.tag(2)])
        let wrapped = Self.profile([
            .ifThen(condition: .constant(.true)), .repeatLoop(times: .number(3)), .loopEnd, .ifEnd, Self.tag(2)
        ])
        #expect(wrapped == bare)
        #expect(wrapped == [[], [], [], [2]])
    }

    /// The end takes the tick and folds on; it does not yield. Yielding is invisible before
    /// another action, which defers anyway, but not at a script's end or before a loop's end,
    /// where it would add a tick (both found by mutation).
    @Test("an empty If finishes a script in its own tick, and an empty If in a loop costs one tick per iteration")
    func emptyIfFoldsOn() {
        var interpreter = Interpreter(
            program: Program(scenes: [Scene(objects: [Object(scripts: [
                Script(bricks: [.ifThen(condition: .constant(.true)), .ifEnd])
            ])])]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        #expect(stepToCompletion(&interpreter).count == 1)
        let loop: [Brick] = [
            .repeatLoop(times: .number(2)), .ifThen(condition: .constant(.true)), .ifEnd, .loopEnd, Self.tag(2)
        ]
        #expect(Self.profile(loop) == [[], [], [2]])
    }

    @Test("an If inside a loop body runs on every iteration")
    func ifInsideALoop() {
        let bricks: [Brick] = [
            .repeatLoop(times: .number(2)),
            .ifElse(condition: .constant(.true)), Self.tag(1), .elseBranch, Self.tag(2), .ifEnd,
            .loopEnd, Self.tag(3)
        ]
        #expect(Self.profile(bricks) == [[1], [1], [3]])
    }

    /// Read on the If's own first act: the If in A is reached after A's action in tick 1, so it
    /// reads `v` in tick 2, after B set it in tick 1. Reading it a tick early would see 0.
    @Test("a deferred If reads what another script wrote in the tick before")
    func crossScriptTiming() {
        let readsV = Formula.binary(.equal, .variable("v"), .number(1))
        let profile = Self.profile(scripts: [
            [Self.tag(1), .ifElse(condition: readsV), Self.tag(5), .elseBranch, Self.tag(9), .ifEnd],
            [.setVariable(name: "v", to: .number(1))]
        ])
        #expect(profile == [[1], [5]])
    }

    // MARK: - Codex slice review of slice 3

    /// Every branch distinct, so a compiler that patched the wrong opener's targets — a FIFO
    /// stack, say — runs the wrong brick rather than the same empty ones.
    @Test("nested If/Elses each jump to their own else and end")
    func nestedIfElseTargets() {
        let nested: [Brick] = [
            .ifElse(condition: .constant(.true)),
            .ifElse(condition: .constant(.false)), Self.tag(1), .elseBranch, Self.tag(2), .ifEnd,
            .elseBranch, Self.tag(3), .ifEnd, Self.tag(4)
        ]
        #expect(Self.profile(nested) == [[2], [4]])
        let withALoop: [Brick] = [
            .ifElse(condition: .constant(.false)), Self.tag(1), .elseBranch,
            .repeatLoop(times: .number(2)), .ifThen(condition: .constant(.true)), Self.tag(2), .ifEnd, .loopEnd,
            .ifEnd, Self.tag(4)
        ]
        #expect(Self.profile(withALoop) == [[2], [2], [4]])
    }

    /// ADR-018: objects run round-robin in creation order within a tick, and the project store is
    /// shared and written immediately — so an If in a later object sees an earlier object's write
    /// from the same tick, and an earlier one does not. An object's own variable shadows it.
    @Test("an If reads the project variable another object wrote, in round-robin order")
    func crossObjectVisibility() {
        let writer = Object(name: "A", scripts: [Script(bricks: [.setVariable(name: "v", to: .number(1))])])
        let reader = Object(name: "B", scripts: [Script(bricks: [
            .ifElse(condition: .binary(.equal, .variable("v"), .number(1))), Self.tag(5), .elseBranch, Self.tag(9),
            .ifEnd
        ])])
        let project = [Variable(name: "v")]
        #expect(Self.profile(Program(scenes: [Scene(objects: [writer, reader])], variables: project)) == [[5]])
        #expect(Self.profile(Program(scenes: [Scene(objects: [reader, writer])], variables: project)) == [[9]])
        var shadowing = reader
        shadowing.variables = [Variable(name: "v")]
        #expect(Self.profile(Program(scenes: [Scene(objects: [writer, shadowing])], variables: project)) == [[9]])
    }

    // MARK: - swift-code-reviewer, slice 3 (three surviving mutants)

    /// The read waits after an action-free If too, since that If took the tick: two empty Ifs
    /// are two ticks, and the second reads what another script wrote in the first.
    @Test("an If after an empty If reads its condition a tick later")
    func deferredAfterAnEmptyIf() {
        let empty: [Brick] = [.ifThen(condition: .constant(.true)), .ifEnd]
        #expect(Self.profile(empty + empty + [Self.tag(2)]) == [[], [], [2]])
        let readsV = Formula.binary(.equal, .variable("v"), .number(1))
        let profile = Self.profile(scripts: [
            empty + [.ifElse(condition: readsV), Self.tag(5), .elseBranch, Self.tag(9), .ifEnd],
            [.setVariable(name: "v", to: .number(1))]
        ])
        #expect(profile == [[], [5]])
    }

    /// The else-jump costs nothing even when nothing has acted yet: an If/Else with an empty
    /// then-branch is one tick, alone and per loop iteration.
    @Test("an empty then-branch of an If/Else costs one tick, alone and in a loop")
    func emptyThenBranchFoldsOn() {
        let ifElse: [Brick] = [.ifElse(condition: .constant(.true)), .elseBranch, Self.tag(3), .ifEnd]
        var interpreter = Interpreter(
            program: Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: ifElse)])])]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        #expect(stepToCompletion(&interpreter).count == 1)
        #expect(Self.profile([.repeatLoop(times: .number(2))] + ifElse + [.loopEnd, Self.tag(2)]) == [[], [], [2]])
    }

    /// An If/Else inside each branch of another, every branch tagged: an else bound to the
    /// wrong open If runs the wrong brick.
    @Test("an If/Else nested in either branch binds its else to itself", arguments: [
        (true, true, [1.0]), (true, false, [2.0]), (false, true, [3.0]), (false, false, [4.0])
    ])
    func nestedInBothBranches(_ outer: Bool, _ inner: Bool, _ expected: [Double]) {
        let innerCondition = Formula.constant(inner ? .true : .false)
        let bricks: [Brick] = [
            .ifElse(condition: .constant(outer ? .true : .false)),
            .ifElse(condition: innerCondition), Self.tag(1), .elseBranch, Self.tag(2), .ifEnd,
            .elseBranch,
            .ifElse(condition: innerCondition), Self.tag(3), .elseBranch, Self.tag(4), .ifEnd,
            .ifEnd
        ]
        #expect(Self.profile(bricks).flatMap(\.self) == expected)
    }

    /// Brief D7's planned case: an action-free If in a `forever` costs one tick per iteration and
    /// never spins.
    @Test("forever around an empty If ticks without spinning")
    func foreverAroundAnEmptyIf() {
        var interpreter = Interpreter(
            program: Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: [
                .forever, .ifThen(condition: .constant(.false)), Self.tag(1), .ifEnd, .loopEnd
            ])])])]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        for _ in 0 ..< 5 {
            #expect(interpreter.step() == .ticked([]))
        }
        #expect(!interpreter.isFinished)
    }
}

