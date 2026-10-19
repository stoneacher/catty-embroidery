import EditorCore
import ProgramModel
import Testing

/// Variables slice 2 (brief D13; Codex brief review, finding 5): the accessibility moves across
/// If blocks. The move-out pair generalizes from loops to every block; crossing the else is a
/// pair of its own, **Move Below Else** and **Move Above Else**, defined for a leaf and for
/// a whole nested block. The reachability property must still hold, and must observe a crossing
/// in both directions.
///
/// ```
/// 0  moveNSteps(1)
/// 1  ifElse(1 < 2)   ─┐
/// 2    stitch          │ then-branch
/// 3    forever    ─┐   │
/// 4      sewUp      │  │
/// 5    loopEnd    ─┘   │
/// 6  elseBranch        │
/// 7    turnLeft(2)     │ else-branch
/// 8  ifEnd           ─┘
/// 9  stopRunningStitch
/// ```
@Suite("If block accessibility moves")
struct IfBlockAccessibilityMoveTests {
    static let condition = Formula.binary(.smallerThan, .number(1), .number(2))
    static let bricks: [Brick] = [
        .moveNSteps(.number(1)), .ifElse(condition: condition), .stitch, .forever, .sewUp, .loopEnd,
        .elseBranch, .turnLeft(.number(2)), .ifEnd, .stopRunningStitch
    ]
    static let script = Script(bricks: bricks)
    static let address = ScriptAddress()

    static func program(_ bricks: [Brick]) -> Program {
        Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: bricks)])])])
    }

    static func applied(_ action: EditAction?) -> EditResult? {
        action.map { EditorCore.apply($0, to: program(bricks)) }
    }

    static func reordered(_ indices: [Int]) -> EditResult {
        .applied(program(indices.map { bricks[$0] }))
    }

    // MARK: - Crossing the else

    @Test("Move Below Else takes the then-branch's last block to the top of the else-branch")
    func intoElse() {
        // The nested loop is the last block of the then-branch, and travels whole.
        #expect(Self.applied(Self.script.moveBelowElseAction(ofBrickAt: 3, in: Self.address))
            == Self.reordered([0, 1, 2, 6, 3, 4, 5, 7, 8, 9]))
    }

    @Test("Move Above Else takes the else-branch's first block to the bottom of the then-branch")
    func intoThen() {
        #expect(Self.applied(Self.script.moveAboveElseAction(ofBrickAt: 7, in: Self.address))
            == Self.reordered([0, 1, 2, 3, 4, 5, 7, 6, 8, 9]))
    }

    @Test("the crossing is offered only at the else")
    func crossingOnlyAtTheElse() {
        let script = Self.script
        for index in Self.bricks.indices where index != 3 {
            #expect(script.moveBelowElseAction(ofBrickAt: index, in: Self.address) == nil, "\(index)")
        }
        for index in Self.bricks.indices where index != 7 {
            #expect(script.moveAboveElseAction(ofBrickAt: index, in: Self.address) == nil, "\(index)")
        }
    }

    /// Conservative on a malformed script, like the move-out pair: an If/Else that never closes
    /// offers no crossing (found by mutation).
    @Test("no crossing is offered in an If/Else that never closes")
    func noCrossingInAnUnclosedIf() {
        let script = Script(bricks: [.ifElse(condition: Self.condition), .stitch, .elseBranch, .sewUp])
        #expect(script.moveBelowElseAction(ofBrickAt: 1, in: Self.address) == nil)
        #expect(script.moveAboveElseAction(ofBrickAt: 3, in: Self.address) == nil)
    }

    // MARK: - Out of a block, and into one

    @Test("the then-branch's first block leaves above the opener")
    func outAbove() {
        #expect(Self.applied(Self.script.moveOutAboveAction(ofBrickAt: 2, in: Self.address))
            == Self.reordered([0, 2, 1, 3, 4, 5, 6, 7, 8, 9]))
        #expect(Self.script.moveOutAboveAction(ofBrickAt: 7, in: Self.address) == nil, "above it is the else")
    }

    @Test("the else-branch's last block leaves below the end")
    func outBelow() {
        #expect(Self.applied(Self.script.moveOutBelowAction(ofBrickAt: 7, in: Self.address))
            == Self.reordered([0, 1, 2, 3, 4, 5, 6, 8, 7, 9]))
        #expect(Self.script.moveOutBelowAction(ofBrickAt: 3, in: Self.address) == nil, "below it is the else")
    }

    /// Into an If from outside: from above, first of the then-branch; from below, last of the
    /// block's last branch, which for an If/Else is the else-branch.
    @Test("a block beside an If enters it as the move-into pair says")
    func intoAnIf() {
        #expect(Self.applied(Self.script.moveIntoBlockBelowAction(ofBrickAt: 0, in: Self.address))
            == Self.reordered([1, 0, 2, 3, 4, 5, 6, 7, 8, 9]))
        #expect(Self.applied(Self.script.moveIntoBlockAboveAction(ofBrickAt: 9, in: Self.address))
            == Self.reordered([0, 1, 2, 3, 4, 5, 6, 7, 9, 8]))
    }

    @Test("the else and the end offer no move", arguments: [6, 8])
    func markersOfferNoMove(_ index: Int) {
        let script = Self.script
        let actions = [
            script.moveUpAction(ofBrickAt: index, in: Self.address),
            script.moveDownAction(ofBrickAt: index, in: Self.address),
            script.moveOutAboveAction(ofBrickAt: index, in: Self.address),
            script.moveOutBelowAction(ofBrickAt: index, in: Self.address),
            script.moveIntoBlockAboveAction(ofBrickAt: index, in: Self.address),
            script.moveIntoBlockBelowAction(ofBrickAt: index, in: Self.address),
            script.moveBelowElseAction(ofBrickAt: index, in: Self.address),
            script.moveAboveElseAction(ofBrickAt: index, in: Self.address)
        ]
        #expect(actions.allSatisfy { $0 == nil })
    }

    @Test("a dragged else or end is refused, so no drop can split the block")
    func draggedMarkerIsRefused() {
        for (index, toOffset) in [(6, 0), (8, 0), (6, 10)] {
            let action = Self.script.moveAction(fromOffsets: [index], toOffset: toOffset, in: Self.address)
            #expect(Self.applied(action) == .rejected(.cannotMoveIfMarker(at: BrickAddress(brickIndex: index))))
        }
    }

    // MARK: - Reachability

    private static func reachable(from start: Script, by actions: (Script) -> [EditAction]) -> Set<String> {
        var seen: Set<String> = [String(describing: start.bricks)]
        var frontier = [start]
        while let script = frontier.popLast() {
            for action in actions(script) {
                guard case let .applied(next) = EditorCore.apply(action, to: program(script.bricks)) else { continue }
                let moved = next.scenes[0].objects[0].scripts[0]
                if seen.insert(String(describing: moved.bricks)).inserted {
                    frontier.append(moved)
                }
            }
        }
        return seen
    }

    private static func drags(_ script: Script) -> [EditAction] {
        script.bricks.indices.flatMap { index in
            (0 ... script.bricks.count).compactMap {
                script.moveAction(fromOffsets: [index], toOffset: $0, in: address)
            }
        }
    }

    private static func accessibilityMoves(_ script: Script) -> [EditAction] {
        script.bricks.indices.flatMap { index in
            [
                script.moveUpAction(ofBrickAt: index, in: address),
                script.moveDownAction(ofBrickAt: index, in: address),
                script.moveOutAboveAction(ofBrickAt: index, in: address),
                script.moveOutBelowAction(ofBrickAt: index, in: address),
                script.moveIntoBlockAboveAction(ofBrickAt: index, in: address),
                script.moveIntoBlockBelowAction(ofBrickAt: index, in: address),
                script.moveBelowElseAction(ofBrickAt: index, in: address),
                script.moveAboveElseAction(ofBrickAt: index, in: address)
            ].compactMap(\.self)
        }
    }

    /// A start, and the arrangements one crossing of the else makes from it, down and up.
    struct Crossing: Sendable {
        let start, down, up: [Brick]
        init(_ start: [Brick], _ down: [Brick], _ up: [Brick]) {
            (self.start, self.down, self.up) = (start, down, up)
        }
    }

    /// The crossing pair applied once from `script`, at every row.
    private static func crossings(_ script: Script) -> Set<String> {
        Set(script.bricks.indices.flatMap { index in
            [
                script.moveBelowElseAction(ofBrickAt: index, in: address),
                script.moveAboveElseAction(ofBrickAt: index, in: address)
            ].compactMap(\.self)
        }.compactMap { action -> String? in
            guard case let .applied(next) = EditorCore.apply(action, to: program(script.bricks)) else { return nil }
            return String(describing: next.scenes[0].objects[0].scripts[0].bricks)
        })
    }

    /// The parity claim of `AccessibilityMoveTests`, over If blocks. Equal sets alone could be
    /// two equally incomplete graphs (Codex brief review, finding 5), so each fixture also names
    /// the two arrangements one crossing of the else makes — a block from the then-branch to
    /// the top of the else-branch, and one from the else-branch to the bottom of the
    /// then-branch — and requires that a drag reaches them and that the crossing pair makes each
    /// in **one** action. (A block could also go round, out of the If and back in from the
    /// other end; the single step is what the pair adds.)
    @Test("the accessibility actions reach exactly what a drag reaches, and cross the else in one step",
          arguments: [
              Crossing(
                  [.ifElse(condition: condition), .stitch, .elseBranch, .sewUp, .ifEnd],
                  [.ifElse(condition: condition), .elseBranch, .stitch, .sewUp, .ifEnd],
                  [.ifElse(condition: condition), .stitch, .sewUp, .elseBranch, .ifEnd]
              ),
              Crossing(
                  [.ifElse(condition: condition), .forever, .stitch, .loopEnd, .elseBranch, .moveNSteps(.number(1)),
                   .ifEnd],
                  [.ifElse(condition: condition), .elseBranch, .forever, .stitch, .loopEnd, .moveNSteps(.number(1)),
                   .ifEnd],
                  [.ifElse(condition: condition), .forever, .stitch, .loopEnd, .moveNSteps(.number(1)), .elseBranch,
                   .ifEnd]
              ),
              Crossing(
                  [.forever, .ifElse(condition: condition), .stitch, .elseBranch, .sewUp, .ifEnd, .loopEnd],
                  [.forever, .ifElse(condition: condition), .elseBranch, .stitch, .sewUp, .ifEnd, .loopEnd],
                  [.forever, .ifElse(condition: condition), .stitch, .sewUp, .elseBranch, .ifEnd, .loopEnd]
              )
          ])
    func reachability(_ fixture: Crossing) {
        let script = Script(bricks: fixture.start)
        let crossedDown = String(describing: fixture.down), crossedUp = String(describing: fixture.up)
        let byDrag = Self.reachable(from: script, by: Self.drags)
        let byAction = Self.reachable(from: script, by: Self.accessibilityMoves)

        #expect(byDrag.count > 4, "the fixture is too small to say anything")
        #expect(byDrag.contains(crossedDown) && byDrag.contains(crossedUp), "the witnesses are not drag-reachable")
        #expect(Self.crossings(script).contains(crossedDown), "no single action crosses the else downward")
        #expect(Self.crossings(script).contains(crossedUp), "no single action crosses the else upward")
        #expect(byAction == byDrag, "\(byDrag.subtracting(byAction).count) arrangements only a drag reaches")
    }

    /// Parity alone, for shapes with no else to cross: an If/Then, and two Ifs side by side.
    @Test("the accessibility actions reach exactly what a drag reaches, beside and inside If blocks",
          arguments: [
              [.stitch, .ifThen(condition: condition), .sewUp, .ifEnd],
              [.stitch, .ifThen(condition: condition), .sewUp, .ifEnd, .ifElse(condition: condition), .elseBranch,
               .ifEnd]
          ] as [[Brick]])
    func reachabilityWithoutACrossing(_ start: [Brick]) {
        let script = Script(bricks: start)
        let byDrag = Self.reachable(from: script, by: Self.drags)
        #expect(byDrag.count > 4, "the fixture is too small to say anything")
        #expect(Self.reachable(from: script, by: Self.accessibilityMoves) == byDrag)
    }
}
