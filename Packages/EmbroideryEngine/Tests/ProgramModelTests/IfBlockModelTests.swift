import Foundation
import ProgramModel
import Testing

/// Variables slice 2 (brief D12, D14; ADR-008 amendment): If and If/Else as blocks in the flat
/// list. An `ifThen` opens a block that an `ifEnd` closes; an `ifElse` opens one that holds
/// exactly one `elseBranch` directly inside it before its `ifEnd`. Loops keep closing with
/// `loopEnd`, and a closer of the other family closes nothing.
///
/// ```
/// 0  ifElse(1 < 2)   opener ─┐
/// 1    stitch                │ then-branch
/// 2  elseBranch      divider │
/// 3    sewUp                 │ else-branch
/// 4  ifEnd           closer ─┘
/// ```
@Suite("If blocks in the program model")
struct IfBlockModelTests {
    static let condition = Formula.binary(.smallerThan, .number(1), .number(2))

    static let ifElse: [Brick] = [.ifElse(condition: condition), .stitch, .elseBranch, .sewUp, .ifEnd]
    static let ifThen: [Brick] = [.ifThen(condition: condition), .stitch, .ifEnd]

    private static func json(_ brick: Brick) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try String(bytes: encoder.encode(brick), encoding: .utf8) ?? "<not UTF-8>"
    }

    // MARK: - Vocabulary and roles

    /// The case names are coding keys (D12): two openers, as Catroid has two brick classes.
    @Test("the four If bricks have their file shapes")
    func shapes() throws {
        #expect(try Self.json(.ifThen(condition: .constant(.true)))
            == #"{"ifThen":{"condition":{"constant":{"_0":{"true":{}}}}}}"#)
        #expect(try Self.json(.ifElse(condition: .constant(.true)))
            == #"{"ifElse":{"condition":{"constant":{"_0":{"true":{}}}}}}"#)
        #expect(try Self.json(.elseBranch) == #"{"elseBranch":{}}"#)
        #expect(try Self.json(.ifEnd) == #"{"ifEnd":{}}"#)
    }

    @Test("each brick has its block role")
    func roles() {
        #expect(Brick.ifThen(condition: Self.condition).blockRole == .opener(.conditional))
        #expect(Brick.ifElse(condition: Self.condition).blockRole == .opener(.conditional))
        #expect(Brick.elseBranch.blockRole == .divider)
        #expect(Brick.ifEnd.blockRole == .closer(.conditional))
        #expect(Brick.repeatLoop(times: .number(2)).blockRole == .opener(.loop))
        #expect(Brick.forever.blockRole == .opener(.loop))
        #expect(Brick.loopEnd.blockRole == .closer(.loop))
        #expect(Brick.stitch.blockRole == .leaf)
        #expect(Brick.wait(seconds: .number(1)).blockRole == .leaf)
    }

    /// `opensLoop` and `isLoopEnd` keep meaning loops only: the interpreter's loop lowering
    /// reads them, and an If is not a loop.
    @Test("the loop predicates stay about loops")
    func loopPredicatesStayLoops() {
        #expect(!Brick.ifThen(condition: Self.condition).opensLoop)
        #expect(!Brick.ifEnd.isLoopEnd)
        #expect(Brick.ifThen(condition: Self.condition).opensBlock)
        #expect(Brick.ifEnd.closesBlock)
        #expect(Brick.loopEnd.closesBlock)
        #expect(!Brick.elseBranch.opensBlock && !Brick.elseBranch.closesBlock)
    }

    @Test("only If/Else expects an else")
    func expectsElse() {
        #expect(Brick.ifElse(condition: Self.condition).expectsElse)
        #expect(!Brick.ifThen(condition: Self.condition).expectsElse)
        #expect(!Brick.repeatLoop(times: .number(2)).expectsElse)
    }

    // MARK: - Matching

    @Test("an If opener's end is its own ifEnd, past nested blocks")
    func matchingEnd() {
        let nested = Script(bricks: [
            .ifElse(condition: Self.condition), .forever, .stitch, .loopEnd, .elseBranch,
            .ifThen(condition: Self.condition), .ifEnd, .ifEnd
        ])
        #expect(nested.matchingEnd(ofBrickAt: 0) == 7)
        #expect(nested.matchingEnd(ofBrickAt: 1) == 3)
        #expect(nested.matchingEnd(ofBrickAt: 5) == 6)
        #expect(nested.range(ofPairAt: 0) == 0 ... 7)
    }

    /// A closer of the other family closes nothing: a loop is not ended by `ifEnd`.
    @Test("a closer of the wrong family does not match")
    func wrongFamilyDoesNotMatch() {
        #expect(Script(bricks: [.forever, .stitch, .ifEnd]).matchingEnd(ofBrickAt: 0) == nil)
        #expect(Script(bricks: [.ifThen(condition: Self.condition), .loopEnd]).matchingEnd(ofBrickAt: 0) == nil)
    }

    @Test("an If/Else's else is the divider directly inside it")
    func matchingElse() {
        let nested = Script(bricks: [
            .ifElse(condition: Self.condition), .ifElse(condition: Self.condition), .elseBranch, .ifEnd,
            .elseBranch, .stitch, .ifEnd
        ])
        #expect(nested.matchingElse(ofBrickAt: 0) == 4)
        #expect(nested.matchingElse(ofBrickAt: 1) == 2)
        #expect(Script(bricks: Self.ifThen).matchingElse(ofBrickAt: 0) == nil)
        #expect(Script(bricks: Self.ifElse).matchingElse(ofBrickAt: 1) == nil, "not an opener")
    }

    // MARK: - Validation

    @Test("well-formed If blocks validate", arguments: [
        ifElse,
        ifThen,
        [.ifElse(condition: condition), .elseBranch, .ifEnd],
        [.ifThen(condition: condition), .ifEnd],
        [.forever, .ifElse(condition: condition), .repeatLoop(times: .number(2)), .loopEnd, .elseBranch,
         .ifThen(condition: condition), .stitch, .ifEnd, .ifEnd, .loopEnd]
    ] as [[Brick]])
    func wellFormed(_ bricks: [Brick]) throws {
        try Script(bricks: bricks).validate()
    }

    @Test("malformed If blocks report the first fault", arguments: [
        ([.ifThen(condition: condition), .stitch], .unmatchedIfOpener(index: 0)),
        ([.stitch, .ifEnd], .unmatchedIfEnd(index: 1)),
        ([.forever, .ifEnd], .mismatchedEnd(index: 1)),
        ([.ifThen(condition: condition), .loopEnd], .mismatchedEnd(index: 1)),
        ([.elseBranch], .misplacedElse(index: 0)),
        ([.ifThen(condition: condition), .elseBranch, .ifEnd], .misplacedElse(index: 1)),
        ([.ifElse(condition: condition), .forever, .elseBranch, .loopEnd, .ifEnd], .misplacedElse(index: 2)),
        ([.ifElse(condition: condition), .elseBranch, .elseBranch, .ifEnd], .duplicateElse(index: 2)),
        ([.ifElse(condition: condition), .stitch, .ifEnd], .missingElse(index: 0)),
        ([.ifElse(condition: condition), .elseBranch], .unmatchedIfOpener(index: 0)),
        ([.repeatLoop(times: .number(2)), .ifThen(condition: condition)], .unmatchedIfOpener(index: 1)),
        ([.ifThen(condition: condition), .forever], .unmatchedLoopOpener(index: 1))
    ] as [([Brick], ScriptValidationError)])
    func malformed(_ bricks: [Brick], _ expected: ScriptValidationError) {
        #expect(throws: expected) { try Script(bricks: bricks).validate() }
    }

    // MARK: - Moving a block as one unit

    @Test("an If/Else moves as one block, else and end included")
    func moveIfBlock() throws {
        let script = Script(bricks: [.moveNSteps(.number(1))] + Self.ifElse)
        let moved = try script.movingPair(at: 1, to: 0)
        #expect(moved.bricks == Self.ifElse + [.moveNSteps(.number(1))])
    }

    @Test("an If opener without an end does not move")
    func unclosedIfDoesNotMove() {
        let script = Script(bricks: [.stitch, .ifThen(condition: Self.condition), .sewUp])
        #expect(throws: ScriptMoveError.unbalancedPair(index: 1)) { try script.movingPair(at: 1, to: 0) }
    }
}
