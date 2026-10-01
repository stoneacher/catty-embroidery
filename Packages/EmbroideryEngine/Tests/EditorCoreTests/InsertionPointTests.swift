import EditorCore
import ProgramModel
import Testing

/// US-409's test-first items 3–5, the package half: where a palette tap inserts.
///
/// The rule (ADR-035, and decided 2026-10-01 for a selected `loopEnd`): **directly after the
/// selected row**, or at the end when nothing is selected. "After a loop opener" is the first
/// position of its body, which is what makes a loop fillable by tap-to-add — so the rule needs
/// no special case, and the tests below are what keep someone from adding one (a skip over the
/// whole block would put the brick *after* the loop). After a `loopEnd` is after the loop.
///
/// Every assertion is on the **whole `Program`** `EditorCore.apply` makes of the built action
/// (ADR-006 pattern 3), on the decoy-shaped fixture:
///
/// ```
/// 0  moveNSteps(1)      leaf before
/// 1  repeatLoop(2)      opener A  ─┐
/// 2    stitch            │         │
/// 3    turnRight(3)      │         │
/// 4    sewUp             │         │
/// 5  loopEnd            end A     ─┘
/// 6  forever            opener B  ─┐
/// 7    changeXBy(4)      │         │
/// 8  loopEnd            end B     ─┘
/// 9  stopRunningStitch  leaf after
/// ```
@Suite("Palette insertion point")
struct InsertionPointTests {
    typealias Fixtures = EditorCoreFixtures

    private static let bricks = Fixtures.bricks

    private static func tap(_ kind: BrickKind, after selected: Int?) -> EditResult {
        let action = Fixtures.script.insertAction(of: kind, after: selected, in: Fixtures.address)
        return EditorCore.apply(action, to: Fixtures.program)
    }

    /// The fixture with `kind`'s template spliced in at `index`.
    private static func inserted(_ kind: BrickKind, at index: Int) -> Program {
        var expected = bricks
        expected.insert(contentsOf: kind.template(), at: index)
        return Fixtures.expecting(expected)
    }

    // MARK: 3 — nothing selected, a leaf selected

    @Test("with nothing selected the brick is appended")
    func nothingSelectedAppends() {
        #expect(Self.tap(.wait, after: nil) == .applied(Self.inserted(.wait, at: 10)))
    }

    @Test("with a leaf selected the brick lands directly after it")
    func afterALeaf() {
        #expect(Self.tap(.wait, after: 0) == .applied(Self.inserted(.wait, at: 1)))
    }

    @Test("with a loop body's leaf selected the brick lands after it, still inside the loop")
    func afterALeafInsideALoop() {
        #expect(Self.tap(.wait, after: 3) == .applied(Self.inserted(.wait, at: 4)))
    }

    @Test("with the last row selected the brick lands at the end")
    func afterTheLastRow() {
        #expect(Self.tap(.wait, after: 9) == .applied(Self.inserted(.wait, at: 10)))
    }

    // MARK: 4 — a loop opener selected: inside the loop

    /// The criterion ADR-035 names: between the opener and its `loopEnd`, as the first brick of
    /// the body, one level deeper than the opener.
    @Test("with a loop opener selected the brick lands first inside its body",
          arguments: [(opener: 1, kind: BrickKind.wait), (opener: 6, kind: .stitch)])
    func insideTheSelectedLoop(opener: Int, kind: BrickKind) throws {
        let result = Self.tap(kind, after: opener)

        #expect(result == .applied(Self.inserted(kind, at: opener + 1)))
        let program = try #require(result.program)
        let script = program.scenes[1].objects[2].scripts[1]
        #expect(script.matchingEnd(ofBrickAt: opener) == Fixtures.script.matchingEnd(ofBrickAt: opener).map { $0 + 1 })
        #expect(script.indentDepths[opener + 1] == script.indentDepths[opener] + 1)
    }

    // MARK: A loopEnd selected: after the loop (decided 2026-10-01)

    @Test("with a loop's end selected the brick lands after the loop, at the loop's depth")
    func afterTheSelectedLoopEnd() throws {
        let result = Self.tap(.wait, after: 5)

        #expect(result == .applied(Self.inserted(.wait, at: 6)))
        let script = try #require(result.program).scenes[1].objects[2].scripts[1]
        #expect(script.indentDepths[6] == 0)
    }

    // MARK: A stale selection

    /// Index identity (ADR-034) makes a selection go stale when the program shrinks under it.
    /// Out of bounds is "nothing selected", never a rejected insert.
    @Test("a selection outside the script appends", arguments: [10, 11, 99, -1])
    func staleSelectionAppends(selected: Int) {
        #expect(Self.tap(.wait, after: selected) == .applied(Self.inserted(.wait, at: 10)))
    }

    @Test("an empty script takes the brick at 0, whatever is selected", arguments: [nil, 0, 3] as [Int?])
    func emptyScript(selected: Int?) {
        let script = Script()
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        let action = script.insertAction(of: .stitch, after: selected, in: ScriptAddress())

        #expect(action == .insert(.stitch, at: BrickAddress(brickIndex: 0)))
        var expected = program
        expected.scenes[0].objects[0].scripts[0].bricks = [.stitch]
        #expect(EditorCore.apply(action, to: program) == .applied(expected))
    }

    // MARK: 5 — inserting a loop

    @Test("inserting a loop adds its opener and its end, and the script stays balanced",
          arguments: [
              (kind: BrickKind.repeatLoop, after: 0 as Int?),
              (kind: .forever, after: 1),
              (kind: .repeatLoop, after: nil)
          ])
    func insertingALoop(kind: BrickKind, after selected: Int?) throws {
        let index = selected.map { $0 + 1 } ?? 10
        let result = Self.tap(kind, after: selected)

        #expect(result == .applied(Self.inserted(kind, at: index)))
        let script = try #require(result.program).scenes[1].objects[2].scripts[1]
        #expect(script.bricks.count == Self.bricks.count + 2)
        #expect(script.matchingEnd(ofBrickAt: index) == index + 1)
        #expect(throws: Never.self) { try script.validate() }
    }

    // MARK: 8 — the scroll target is the action's own index

    /// The list scrolls to the insertion index, so the index the action names must be where the
    /// new brick (or the new loop's opener) actually landed.
    @Test("the built action's index is where the new brick's head lands",
          arguments: [nil, 0, 1, 5, 9] as [Int?], [BrickKind.wait, .repeatLoop])
    func scrollTargetIsTheInsertedHead(selected: Int?, kind: BrickKind) throws {
        let action = Fixtures.script.insertAction(of: kind, after: selected, in: Fixtures.address)
        guard case let .insert(insertedKind, address) = action else {
            Issue.record("expected an insert, got \(action)")
            return
        }
        #expect(insertedKind == kind)
        #expect(address.script == Fixtures.address)
        let script = try #require(EditorCore.apply(action, to: Fixtures.program).program)
            .scenes[1].objects[2].scripts[1]
        #expect(script.bricks[address.brickIndex] == kind.template()[0])
    }
}

private extension EditResult {
    var program: Program? {
        if case let .applied(program) = self {
            program
        } else {
            nil
        }
    }
}
