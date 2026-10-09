import EditorCore
import ProgramModel
import Testing

/// US-411 test-plan items 1 and 2, the **totality proof**: every `EditAction` case
/// round-trips through the history — apply, undo to the seed, redo to the result.
///
/// `EditAction` has associated values, so it cannot be `CaseIterable`, and an
/// exhaustive `switch` beside a separately iterated fixture array ties nothing
/// together: adding a case and handling it in the switch leaves the old array green
/// (ADR-026 records that exact failure). So case identity is bound to an executable
/// fixture through **two exhaustive switches with no `default:`** —
/// `EditAction → EditActionCase` and `EditActionCase → fixture` — and the test sweeps
/// `EditActionCase.allCases`.
///
/// **What adding an `EditAction` case does: it fails to compile** — first in
/// `editActionCase`, then, once a tag is added, in `fixture(for:)`. A fixture copied
/// from another case compiles but fails `fixtureIsBoundToItsCase`.
///
/// Every fixture must **apply and change the program** before it is undone. A
/// rejected or no-op fixture leaves the program unchanged and the round trip would
/// pass while testing nothing — the test that cannot fail (ADR-032 invariant 2), in
/// the very suite written to prove coverage.
@Suite("UndoStack — every EditAction case round-trips")
struct UndoEnumerationTests {
    typealias Fixtures = EditorCoreFixtures

    /// One tag per `EditAction` case, and nothing else.
    enum EditActionCase: CaseIterable {
        case insert, delete, move, replaceBrick, renameProgram, declareVariable
    }

    /// The seed program and the action applied to it.
    struct Fixture {
        let seed: Program
        let action: EditAction
    }

    static func fixture(for tag: EditActionCase) -> Fixture {
        switch tag {
        case .insert:
            Fixture(seed: Fixtures.program, action: .insert(.stitch, at: Fixtures.at(10)))
        case .delete:
            // Loop A — opener, body and end — so the undo restores a whole pair.
            Fixture(seed: Fixtures.program, action: .delete(at: Fixtures.at(1)))
        case .move:
            Fixture(seed: Fixtures.program, action: .move(from: Fixtures.at(0), to: 5))
        case .replaceBrick:
            Fixture(
                seed: Fixtures.program,
                action: .replaceBrick(at: Fixtures.at(3), with: .turnRight(.number(90)))
            )
        case .renameProgram:
            Fixture(seed: Fixtures.program, action: .renameProgram("renamed"))
        case .declareVariable:
            // The US-410 amendment's fixture: a fresh name on the blank program.
            Fixture(seed: .blank, action: .declareVariable(name: "Side", script: ScriptAddress()))
        }
    }

    @Test("each fixture's action is the case it stands for", arguments: EditActionCase.allCases)
    func fixtureIsBoundToItsCase(tag: EditActionCase) {
        #expect(Self.fixture(for: tag).action.editActionCase == tag)
    }

    @Test("apply changes the program, undo restores the seed, redo restores the result",
          arguments: EditActionCase.allCases)
    func roundTrip(tag: EditActionCase) throws {
        let fixture = Self.fixture(for: tag)
        var stack = UndoStack(program: fixture.seed)

        let result = stack.apply(fixture.action)
        guard case let .applied(edited) = result else {
            Issue.record("the \(tag) fixture must apply, got \(result)")
            return
        }
        try #require(edited != fixture.seed, "the \(tag) fixture must change the program")
        try #require(stack.current == edited)

        #expect(stack.undo() == fixture.seed)
        #expect(stack.current == fixture.seed)
        #expect(!stack.canUndo)

        #expect(stack.redo() == edited)
        #expect(stack.current == edited)
        #expect(!stack.canRedo)
    }
}

extension EditAction {
    /// Exhaustive with no `default:` — a new `EditAction` case is a compile error here.
    var editActionCase: UndoEnumerationTests.EditActionCase {
        switch self {
        case .insert: .insert
        case .delete: .delete
        case .move: .move
        case .replaceBrick: .replaceBrick
        case .renameProgram: .renameProgram
        case .declareVariable: .declareVariable
        }
    }
}
