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

    // MARK: Move Up / Move Down

    /// Item 8 — the pair a VoiceOver user reorders with: "Move Up" on loop B, which follows
    /// loop A, jumps the **whole** of A. Asserted as equality with the drag a sighted user
    /// makes, and against the literal, so the two paths cannot agree on a shared mistake.
    @Test("Move Up on a loop that follows a loop equals dragging it above that loop")
    func moveUpEqualsDrag() {
        let expected = EditResult.applied(Self.reordered([0, 6, 7, 8, 1, 2, 3, 4, 5, 9]))

        #expect(Self.applied(Self.script.moveUpAction(ofBrickAt: 6, in: Fixtures.address)) == expected)
        #expect(Self.drag([6], to: 1) == expected)
    }

    @Test("Move Down on a loop that precedes a loop equals dragging it below that loop")
    func moveDownEqualsDrag() {
        let expected = EditResult.applied(Self.reordered([0, 6, 7, 8, 1, 2, 3, 4, 5, 9]))

        #expect(Self.applied(Self.script.moveDownAction(ofBrickAt: 1, in: Fixtures.address)) == expected)
        #expect(Self.drag([1], to: 9) == expected)
    }

    /// Leaves jump whole sibling pairs too — a Move Down from the top that moved one index
    /// would put the leaf inside loop A.
    @Test("a leaf's Move Up and Move Down jump the sibling loop beside it")
    func leafMovesJumpPairs() {
        #expect(
            Self.applied(Self.script.moveDownAction(ofBrickAt: 0, in: Fixtures.address))
                == .applied(Self.reordered([1, 2, 3, 4, 5, 0, 6, 7, 8, 9]))
        )
        #expect(
            Self.applied(Self.script.moveUpAction(ofBrickAt: 9, in: Fixtures.address))
                == .applied(Self.reordered([0, 1, 2, 3, 4, 5, 9, 6, 7, 8]))
        )
        // Inside a body, between siblings: an ordinary swap.
        #expect(
            Self.applied(Self.script.moveDownAction(ofBrickAt: 2, in: Fixtures.address))
                == .applied(Self.reordered([0, 1, 3, 2, 4, 5, 6, 7, 8, 9]))
        )
    }

    /// Where there is no sibling there is no action — including a body's edges, which the
    /// move-out pair below covers instead.
    @Test("no Move Up or Move Down is offered where there is no sibling")
    func noSiblingNoMove() {
        #expect(Self.script.moveUpAction(ofBrickAt: 0, in: Fixtures.address) == nil)
        #expect(Self.script.moveDownAction(ofBrickAt: 9, in: Fixtures.address) == nil)
        #expect(Self.script.moveUpAction(ofBrickAt: 2, in: Fixtures.address) == nil, "top of a body")
        #expect(Self.script.moveDownAction(ofBrickAt: 4, in: Fixtures.address) == nil, "bottom of a body")
    }

    /// Item 9b, the package half — **decided 2026-09-29: omitted**, matching the row's
    /// `.moveDisabled`. An end row is not a block; the loop is moved from its opener.
    @Test("a loop end offers no move of any kind", arguments: [5, 8])
    func loopEndOffersNoMove(index: Int) {
        #expect(Self.script.moveUpAction(ofBrickAt: index, in: Fixtures.address) == nil)
        #expect(Self.script.moveDownAction(ofBrickAt: index, in: Fixtures.address) == nil)
        #expect(Self.script.moveAboveLoopAction(ofBrickAt: index, in: Fixtures.address) == nil)
        #expect(Self.script.moveBelowLoopAction(ofBrickAt: index, in: Fixtures.address) == nil)
        #expect(Self.script.moveIntoLoopAboveAction(ofBrickAt: index, in: Fixtures.address) == nil)
        #expect(Self.script.moveIntoLoopBelowAction(ofBrickAt: index, in: Fixtures.address) == nil)
    }

    // MARK: Move out of a loop

    /// **Decided 2026-09-29 (Sebastian): the move-out verb ships in US-408.** The sibling jump
    /// cannot take a brick out of a loop — the opener is its parent — while a drag can. These
    /// two actions close that gap at exactly the places Move Up and Move Down are absent.
    @Test("Move Above Loop takes the first block of a body out above its opener")
    func moveAboveLoop() {
        #expect(
            Self.applied(Self.script.moveAboveLoopAction(ofBrickAt: 2, in: Fixtures.address))
                == .applied(Self.reordered([0, 2, 1, 3, 4, 5, 6, 7, 8, 9]))
        )
    }

    @Test("Move Below Loop takes the last block of a body out below its end")
    func moveBelowLoop() {
        let expected = EditResult.applied(Self.reordered([0, 1, 2, 3, 5, 4, 6, 7, 8, 9]))

        #expect(Self.applied(Self.script.moveBelowLoopAction(ofBrickAt: 4, in: Fixtures.address)) == expected)
        #expect(Self.drag([4], to: 6) == expected, "the same place a drag puts it")
    }

    /// A one-brick body is both the first and the last block, so it offers both.
    @Test("a body's only brick can leave in either direction")
    func onlyBrickLeavesEitherWay() {
        #expect(
            Self.applied(Self.script.moveAboveLoopAction(ofBrickAt: 7, in: Fixtures.address))
                == .applied(Self.reordered([0, 1, 2, 3, 4, 5, 7, 6, 8, 9]))
        )
        #expect(
            Self.applied(Self.script.moveBelowLoopAction(ofBrickAt: 7, in: Fixtures.address))
                == .applied(Self.reordered([0, 1, 2, 3, 4, 5, 6, 8, 7, 9]))
        )
    }

    /// A nested loop leaves as a block: on `[stitch, repeat, move, forever, sewUp, end, end,
    /// stop]`, the `forever` pair is the last block of the repeat's body.
    @Test("a nested loop leaves its parent as a whole block")
    func nestedLoopLeavesAsABlock() throws {
        let seed = Fixtures.propertySeed
        let script = seed.scenes[0].objects[0].scripts[0]
        let action = try #require(script.moveBelowLoopAction(ofBrickAt: 3, in: ScriptAddress()))

        var expected = seed
        expected.scenes[0].objects[0].scripts[0].bricks = [
            .stitch, .repeatLoop(times: .number(3)), .moveNSteps(.number(10)), .loopEnd,
            .forever, .sewUp, .loopEnd, .stopRunningStitch
        ]
        #expect(EditorCore.apply(action, to: seed) == .applied(expected))
    }

    /// Offered only at a body's edges, where Move Up or Move Down is absent — never at the
    /// top level, and never mid-body, where the sibling moves already work.
    @Test("no move-out is offered away from a body's edge")
    func moveOutOnlyAtTheEdge() {
        #expect(Self.script.moveAboveLoopAction(ofBrickAt: 3, in: Fixtures.address) == nil, "mid-body")
        #expect(Self.script.moveBelowLoopAction(ofBrickAt: 3, in: Fixtures.address) == nil, "mid-body")
        #expect(Self.script.moveBelowLoopAction(ofBrickAt: 2, in: Fixtures.address) == nil, "top, not bottom")
        #expect(Self.script.moveAboveLoopAction(ofBrickAt: 4, in: Fixtures.address) == nil, "bottom, not top")
        for index in [0, 1, 6, 9] {
            #expect(
                Self.script.moveAboveLoopAction(ofBrickAt: index, in: Fixtures.address) == nil,
                "top level \(index)"
            )
            #expect(
                Self.script.moveBelowLoopAction(ofBrickAt: index, in: Fixtures.address) == nil,
                "top level \(index)"
            )
        }
    }

    /// Conservative on a malformed script, as the sibling jump is: a loop that never closes has
    /// no "below", and a loop whose extent is unknown is not offered as a place to leave.
    @Test("no move-out is offered from a loop that never closes")
    func noMoveOutOfAnUnclosedLoop() {
        let script = Fixtures.withUnclosedOpener.scenes[0].objects[0].scripts[0]

        #expect(script.moveAboveLoopAction(ofBrickAt: 1, in: ScriptAddress()) == nil)
        #expect(script.moveBelowLoopAction(ofBrickAt: 1, in: ScriptAddress()) == nil)
    }

    // MARK: Move into a loop

    /// **Decided 2026-09-29 (Sebastian), at `swift-code-reviewer`'s finding**: the move-out pair
    /// left the mirror gap — the sibling jump steps over a whole loop, so no action could put a
    /// brick *into* one. From below, the block joins the end of the loop above it.
    @Test("Move Into Loop Above makes the block the last of that loop's body")
    func moveIntoLoopAbove() {
        #expect(
            Self.applied(Self.script.moveIntoLoopAboveAction(ofBrickAt: 9, in: Fixtures.address))
                == .applied(Self.reordered([0, 1, 2, 3, 4, 5, 6, 7, 9, 8]))
        )
        // A loop enters a loop as a block.
        #expect(
            Self.applied(Self.script.moveIntoLoopAboveAction(ofBrickAt: 6, in: Fixtures.address))
                == .applied(Self.reordered([0, 1, 2, 3, 4, 6, 7, 8, 5, 9]))
        )
    }

    /// From above, the block becomes the first of the loop below it — just after its opener,
    /// which with the block removed is `opener + 1 − span`.
    @Test("Move Into Loop Below makes the block the first of that loop's body")
    func moveIntoLoopBelow() {
        let expected = EditResult.applied(Self.reordered([1, 0, 2, 3, 4, 5, 6, 7, 8, 9]))

        #expect(Self.applied(Self.script.moveIntoLoopBelowAction(ofBrickAt: 0, in: Fixtures.address)) == expected)
        #expect(Self.drag([0], to: 2) == expected, "the same place a drag puts it")
        #expect(
            Self.applied(Self.script.moveIntoLoopBelowAction(ofBrickAt: 1, in: Fixtures.address))
                == .applied(Self.reordered([0, 6, 1, 2, 3, 4, 5, 7, 8, 9]))
        )
    }

    /// Only where the neighbouring sibling is a loop: a leaf neighbour, no neighbour, or a
    /// `loopEnd` row offer nothing.
    @Test("no move-into is offered where the neighbour is not a loop")
    func moveIntoOnlyBesideALoop() {
        #expect(Self.script.moveIntoLoopBelowAction(ofBrickAt: 2, in: Fixtures.address) == nil, "leaf below")
        #expect(Self.script.moveIntoLoopAboveAction(ofBrickAt: 3, in: Fixtures.address) == nil, "leaf above")
        #expect(Self.script.moveIntoLoopAboveAction(ofBrickAt: 1, in: Fixtures.address) == nil, "leaf above a loop")
        #expect(Self.script.moveIntoLoopBelowAction(ofBrickAt: 9, in: Fixtures.address) == nil, "nothing below")
        #expect(Self.script.moveIntoLoopAboveAction(ofBrickAt: 0, in: Fixtures.address) == nil, "nothing above")
        for end in [5, 8] {
            #expect(Self.script.moveIntoLoopAboveAction(ofBrickAt: end, in: Fixtures.address) == nil)
            #expect(Self.script.moveIntoLoopBelowAction(ofBrickAt: end, in: Fixtures.address) == nil)
        }
    }

    // MARK: Reachability

    /// Every arrangement reachable from `start` by repeatedly applying `actions`.
    private static func reachable(from start: Script, by actions: (Script) -> [EditAction]) -> Set<String> {
        func program(_ script: Script) -> Program {
            Program(name: "", scenes: [Scene(name: "", objects: [Object(name: "", scripts: [script])])])
        }
        var seen: Set<String> = [String(describing: start.bricks)]
        var frontier = [start]
        while let script = frontier.popLast() {
            for action in actions(script) {
                guard case let .applied(next) = EditorCore.apply(action, to: program(script)) else { continue }
                let moved = next.scenes[0].objects[0].scripts[0]
                if seen.insert(String(describing: moved.bricks)).inserted { frontier.append(moved) }
            }
        }
        return seen
    }

    private static func drags(_ script: Script) -> [EditAction] {
        script.bricks.indices.flatMap { index in
            (0 ... script.bricks.count).compactMap {
                script.moveAction(fromOffsets: [index], toOffset: $0, in: ScriptAddress())
            }
        }
    }

    private static func accessibilityMoves(_ script: Script) -> [EditAction] {
        script.bricks.indices.flatMap { index in
            [
                script.moveUpAction(ofBrickAt: index, in: ScriptAddress()),
                script.moveDownAction(ofBrickAt: index, in: ScriptAddress()),
                script.moveAboveLoopAction(ofBrickAt: index, in: ScriptAddress()),
                script.moveBelowLoopAction(ofBrickAt: index, in: ScriptAddress()),
                script.moveIntoLoopAboveAction(ofBrickAt: index, in: ScriptAddress()),
                script.moveIntoLoopBelowAction(ofBrickAt: index, in: ScriptAddress())
            ].compactMap(\.self)
        }
    }

    /// **The parity claim, as a property rather than a comment.** A VoiceOver user cannot drag,
    /// so the six actions are their only way to reorder: whatever a sighted user can arrange
    /// by dragging, they must be able to arrange too — and nothing more, since every action is
    /// a `.move` a drag could make. The first fixture is the review's counterexample: before
    /// the move-into pair, drags reached 12 arrangements of it and the actions only 8.
    @Test("the accessibility actions reach exactly the arrangements a drag reaches", arguments: [
        [.stitch, .repeatLoop(times: .number(2)), .sewUp, .loopEnd],
        [.stitch, .repeatLoop(times: .number(2)), .sewUp, .loopEnd, .forever, .changeXBy(.number(4)), .loopEnd],
        [.stitch, .repeatLoop(times: .number(3)), .moveNSteps(.number(10)), .forever, .sewUp, .loopEnd, .loopEnd]
    ] as [[Brick]])
    func accessibilityReachesWhatADragReaches(bricks: [Brick]) {
        let start = Script(bricks: bricks)
        let byDrag = Self.reachable(from: start, by: Self.drags)
        let byAction = Self.reachable(from: start, by: Self.accessibilityMoves)

        #expect(byDrag.count > 4, "the fixture is too small to say anything")
        #expect(byAction == byDrag, "\(byDrag.subtracting(byAction).count) arrangements only a drag reaches")
    }

    // MARK: Loop ends, again

    /// `swift-code-reviewer`'s two surviving mutants: an **empty** loop, where the row before
    /// the end is its opener, and an end directly after an end. On neither shape may an end
    /// row offer a move — the fixture above has a leaf before each of its ends.
    @Test("a loop end offers no move after an empty body or another end", arguments: [
        ([.stitch, .repeatLoop(times: .number(2)), .loopEnd], 2),
        ([.repeatLoop(times: .number(2)), .forever, .loopEnd, .loopEnd], 2),
        ([.repeatLoop(times: .number(2)), .forever, .loopEnd, .loopEnd], 3)
    ] as [([Brick], Int)])
    func loopEndOnDegenerateShapes(bricks: [Brick], index: Int) {
        let script = Script(bricks: bricks)
        let address = ScriptAddress()

        #expect(script.moveUpAction(ofBrickAt: index, in: address) == nil)
        #expect(script.moveDownAction(ofBrickAt: index, in: address) == nil)
        #expect(script.moveAboveLoopAction(ofBrickAt: index, in: address) == nil)
        #expect(script.moveBelowLoopAction(ofBrickAt: index, in: address) == nil)
        #expect(script.moveIntoLoopAboveAction(ofBrickAt: index, in: address) == nil)
        #expect(script.moveIntoLoopBelowAction(ofBrickAt: index, in: address) == nil)
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
        #expect(script.moveAction(fromOffsets: [0], toOffset: 3, in: ScriptAddress()) == .move(from: BrickAddress(brickIndex: 0), to: 2))
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
