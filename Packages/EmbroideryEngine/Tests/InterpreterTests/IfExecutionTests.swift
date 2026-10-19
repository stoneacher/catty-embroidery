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
        var interpreter = Interpreter(
            program: Program(scenes: [Scene(objects: [Object(scripts: scripts.map { Script(bricks: $0) })])]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        return stepToCompletion(&interpreter).map { batch in
            batch.compactMap {
                if case let .needleMoved(_, update) = $0 { update.position.y } else { nil }
            }
        }
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
}
