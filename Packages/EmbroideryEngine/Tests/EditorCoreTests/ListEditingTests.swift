import EditorCore
import ProgramModel
import Testing

/// US-408's test-first plan, the package half: what a list gesture or an accessibility action
/// means as an `EditAction`.
///
/// Every assertion is on the **whole `Program`** that `EditorCore.apply` makes of the built
/// action (ADR-006 pattern 3), on the decoy-shaped fixture, so an action that resolved the
/// right index in the wrong script fails too.
///
/// ```
/// 0  moveNSteps(1)      leaf before
/// 1  repeatLoop(2)      opener A  ─┐  five bricks
/// 2    stitch            │         │
/// 3    turnRight(3)      │         │
/// 4    sewUp             │         │
/// 5  loopEnd            end A     ─┘
/// 6  forever            opener B  ─┐  three bricks
/// 7    changeXBy(4)      │         │
/// 8  loopEnd            end B     ─┘
/// 9  stopRunningStitch  leaf after
/// ```
@Suite("Script list editing")
struct ListEditingTests {
    typealias Fixtures = EditorCoreFixtures

    private static let script = Fixtures.script

    /// The fixture's bricks in the order `indices` names them — so an expectation reads as the
    /// permutation it is, and cannot disagree with the fixture about a payload.
    private static func reordered(_ indices: [Int]) -> Program {
        Fixtures.expecting(indices.map { Fixtures.bricks[$0] })
    }

    /// What the fixture becomes under `action`; `nil` in, `nil` out.
    private static func applied(_ action: EditAction?) -> EditResult? {
        action.map { EditorCore.apply($0, to: Fixtures.program) }
    }

    private static func drag(_ source: [Int], to toOffset: Int) -> EditResult? {
        applied(script.moveAction(fromOffsets: source, toOffset: toOffset, in: Fixtures.address))
    }

    // MARK: 1–3c — the destination conversion

    /// Item 1, the conversion in its simplest form: a leaf dropped below loop A. `.onMove`
    /// says 6 (before `forever`, counted with the leaf still in place); the model's index
    /// with the leaf removed is 5.
    @Test("a downward single-brick move lands where it was dropped")
    func downwardLeafMove() {
        #expect(Self.drag([0], to: 6) == .applied(Self.reordered([1, 2, 3, 4, 5, 0, 6, 7, 8, 9])))
    }

    /// Item 2 — the test the conversion bug fails and item 1 passes. Loop A is five bricks, so
    /// the difference between the two conventions is five, not one: dropped before the
    /// trailing leaf (`toOffset` 9), it belongs at 4 in the list without it. Subtract-one gives
    /// 8, which is out of bounds for the five bricks that remain.
    @Test("a downward move of a multi-brick loop lands where it was dropped")
    func downwardPairMove() {
        #expect(Self.drag([1], to: 9) == .applied(Self.reordered([0, 6, 7, 8, 1, 2, 3, 4, 5, 9])))
    }

    /// Item 3 — upward, where the two conventions agree. It is the test that catches
    /// subtracting the block length unconditionally, which gives −3 here.
    @Test("an upward move of a loop lands where it was dropped")
    func upwardPairMove() {
        #expect(Self.drag([6], to: 0) == .applied(Self.reordered([6, 7, 8, 0, 1, 2, 3, 4, 5, 9])))
    }

    /// Item 3b. A pair dropped inside its own original range — or at either edge of it — goes
    /// back where it was, so there is no edit to make. `nil` rather than a `.move` that would
    /// need to be rejected: this is not a refusal, the user put it back.
    @Test("a drop within the moving block's own range is no edit", arguments: 1 ... 6)
    func dropInsideOwnRange(toOffset: Int) {
        #expect(Self.script.moveAction(fromOffsets: [1], toOffset: toOffset, in: Fixtures.address) == nil)
    }

    /// The same rule for a leaf, whose range is itself: above it and below it.
    @Test("a leaf dropped where it already is is no edit", arguments: [0, 1])
    func leafDroppedInPlace(toOffset: Int) {
        #expect(Self.script.moveAction(fromOffsets: [0], toOffset: toOffset, in: Fixtures.address) == nil)
    }

    /// Item 3c, and the story's own worked example: `[R, A, E, B]`, the loop dropped at the
    /// very end (`toOffset` 4), belongs at 1. **It does not discriminate the block-length
    /// mutant** — at the end, `n − L == remaining.count` exactly, so both agree; item 3 does
    /// that. Its value is catching a naive subtract-one for a multi-brick block (3).
    @Test("a downward move to the very end lands at the end")
    func downwardMoveToTheEnd() {
        let rae = Script(bricks: [.repeatLoop(times: .number(2)), .stitch, .loopEnd, .sewUp])
        let program = Program(name: "rae", scenes: [Scene(name: "only", objects: [
            Object(name: "only", scripts: [rae])
        ])])
        let action = rae.moveAction(fromOffsets: [0], toOffset: 4, in: ScriptAddress())

        #expect(action == .move(from: BrickAddress(brickIndex: 0), to: 1))
        var expected = program
        expected.scenes[0].objects[0].scripts[0].bricks = [.sewUp, .repeatLoop(times: .number(2)), .stitch, .loopEnd]
        #expect(action.map { EditorCore.apply($0, to: program) } == .applied(expected))

        // And on the fixture: loop B to the end.
        #expect(Self.drag([6], to: 10) == .applied(Self.reordered([0, 1, 2, 3, 4, 5, 9, 6, 7, 8])))
    }

    // MARK: 4–5 — refusals

    /// Item 4. The adapter does not screen a `loopEnd` — `apply` is the one authority on what
    /// is refused, and it says why.
    @Test("a drag from a loop end is refused and changes nothing")
    func dragFromALoopEnd() {
        #expect(Self.drag([5], to: 0) == .rejected(.cannotMoveLoopEnd(at: Fixtures.at(5))))
    }

    /// Item 5. The closure's `IndexSet` permits several rows; a single finger gives one.
    /// Moving the first and dropping the rest silently would be a lie about what happened.
    @Test("a move of several rows, or none, is no edit", arguments: [[0, 9], [0, 1, 2], []] as [[Int]])
    func multiRowMove(source: [Int]) {
        #expect(Self.script.moveAction(fromOffsets: source, toOffset: 3, in: Fixtures.address) == nil)
    }

    // MARK: 6 — delete

    /// Item 6: at the opener, opener, body and end go (ADR-035); at the end, the same program.
    @Test("a swipe on a loop opener or its end deletes the whole loop", arguments: [1, 5])
    func deletingALoop(index: Int) {
        let action = Self.script.deleteAction(atOffsets: [index], in: Fixtures.address)

        #expect(action == .delete(at: Fixtures.at(index)))
        #expect(Self.applied(action) == .applied(Self.reordered([0, 6, 7, 8, 9])))
    }

    /// A pair delete removes several rows, so every other index in the set would be stale.
    @Test("a delete of several rows, or none, is no edit", arguments: [[0, 9], []] as [[Int]])
    func multiRowDelete(offsets: [Int]) {
        #expect(Self.script.deleteAction(atOffsets: offsets, in: Fixtures.address) == nil)
    }

    // MARK: Inputs SwiftUI does not produce

    /// The two promises the adapter's comments make about rows no drag can come from, pinned
    /// because a mutant of each survived review: an out-of-range source is still `apply`'s to
    /// refuse, and an opener that never closes counts as one row.
    @Test("an out-of-range source is built and refused by apply, with its reason")
    func outOfRangeSource() {
        #expect(Self.drag([10], to: 0) == .rejected(.addressOutOfBounds(.brick, at: Fixtures.at(10))))
    }

    @Test("an opener that never closes counts as one row")
    func unclosedOpenerIsOneRow() {
        let script = Script(bricks: [.repeatLoop(times: .number(2)), .moveNSteps(.number(10)), .stitch])

        #expect(script.moveAction(fromOffsets: [0], toOffset: 1, in: ScriptAddress()) == nil)
        #expect(
            script.moveAction(fromOffsets: [0], toOffset: 3, in: ScriptAddress())
                == .move(from: BrickAddress(brickIndex: 0), to: 2)
        )
    }

    // MARK: 7 — balance

    /// Item 7, exhaustively rather than sampled: every drag from every row to every offset,
    /// every swipe, and every accessibility action, on the fixture. Each applied result must
    /// validate, and enough of them must have actually moved something that the property is
    /// not vacuous (ADR-032 invariant 2).
    @Test("every move and delete leaves the script balanced")
    func everyGestureKeepsBalance() throws {
        let count = Self.script.bricks.count
        var actions: [EditAction] = []
        for index in 0 ..< count {
            for toOffset in 0 ... count {
                if let action = Self.script.moveAction(fromOffsets: [index], toOffset: toOffset, in: Fixtures.address) {
                    actions.append(action)
                }
            }
            actions += [
                Self.script.deleteAction(atOffsets: [index], in: Fixtures.address),
                Self.script.moveUpAction(ofBrickAt: index, in: Fixtures.address),
                Self.script.moveDownAction(ofBrickAt: index, in: Fixtures.address),
                Self.script.moveAboveLoopAction(ofBrickAt: index, in: Fixtures.address),
                Self.script.moveBelowLoopAction(ofBrickAt: index, in: Fixtures.address),
                Self.script.moveIntoLoopAboveAction(ofBrickAt: index, in: Fixtures.address),
                Self.script.moveIntoLoopBelowAction(ofBrickAt: index, in: Fixtures.address)
            ].compactMap(\.self)
        }

        var changed = 0
        for action in actions {
            guard case let .applied(program) = EditorCore.apply(action, to: Fixtures.program) else { continue }
            let edited = program.scenes[1].objects[2].scripts[1]
            try edited.validate()
            if program != Fixtures.program {
                changed += 1
            }
        }
        #expect(changed > 60, "only \(changed) gestures changed the program")
    }
}
