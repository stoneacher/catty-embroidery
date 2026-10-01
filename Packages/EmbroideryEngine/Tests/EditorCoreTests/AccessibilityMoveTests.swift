import EditorCore
import ProgramModel
import Testing

/// US-408's accessibility moves: what a VoiceOver user reorders with, since they cannot drag.
///
/// Six actions, each a plain `.move` the drag adapter could also build — Move Up / Move Down
/// over whole sibling blocks, Move Above / Below Loop out of a body, and Move Into Loop Above /
/// Below into a neighbouring loop — and the property that ties them to the drag: together they
/// reach exactly the arrangements a drag reaches. Split from `ListEditingTests` for length; the
/// fixture and its diagram are the same.
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
@Suite("Script accessibility moves")
struct AccessibilityMoveTests {
    typealias Fixtures = EditorCoreFixtures

    private static let script = Fixtures.script

    private static func reordered(_ indices: [Int]) -> Program {
        Fixtures.expecting(indices.map { Fixtures.bricks[$0] })
    }

    private static func applied(_ action: EditAction?) -> EditResult? {
        action.map { EditorCore.apply($0, to: Fixtures.program) }
    }

    private static func drag(_ source: [Int], to toOffset: Int) -> EditResult? {
        applied(script.moveAction(fromOffsets: source, toOffset: toOffset, in: Fixtures.address))
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
}
