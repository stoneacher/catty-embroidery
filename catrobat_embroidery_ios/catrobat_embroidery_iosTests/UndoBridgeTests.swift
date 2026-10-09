@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Testing

/// US-411's `UndoManager` bridge (ADR-036, 2026-10-09 amendment): **full agreement**. The
/// editor owns an `UndoManager` (`groupsByEvent == false`) that a first-responder anchor vends
/// to shake, ⌘Z and the edit menu, and after every history transition it holds exactly as many
/// undo and redo steps as the package stack — no more, no fewer.
///
/// Agreement is asserted by **walking the system manager** and comparing whole programs at
/// every step (ADR-006 pattern 3), not by comparing `canUndo` flags: a bridge that registered
/// one proxy whatever the depth would pass every flag check and fail the walk.
///
/// The manager is a plain `UndoManager` configured exactly as the app configures it, so these
/// tests run the production configuration, with no run loop needed.
@MainActor
@Suite("UndoManager bridge")
struct UndoBridgeTests {
    /// One scene, one object, one script with a stepper-editable brick, named `p0`.
    private static let seed = renamed("p0")

    private static func renamed(_ name: String) -> Program {
        Program(
            name: name,
            scenes: [Scene(objects: [Object(scripts: [Script(bricks: [.moveNSteps(.number(10))])])])]
        )
    }

    private static func editor(_ program: Program = seed) -> (EditorViewModel, UndoManager) {
        let editor = EditorViewModel(program: program, undoManager: .makeEditorHistory())
        // `#require` cannot run in a static helper without `throws`; every caller needs it.
        return (editor, editor.systemUndoManager!)
    }

    /// Renames the editor's program to `p1` … `p\(count)`, one un-keyed edit each.
    private static func rename(_ editor: EditorViewModel, through count: Int) {
        for index in 1 ... count {
            editor.apply(.renameProgram("p\(index)"))
        }
    }

    /// Undoes through the **system** manager until it refuses, recording the program after each
    /// step — the walk that proves exact depth, not just a matching flag.
    private static func systemUndoWalk(_ editor: EditorViewModel, _ manager: UndoManager) -> [String] {
        var names: [String] = []
        while manager.canUndo, names.count <= UndoStack.capacity {
            manager.undo()
            names.append(editor.program.name)
        }
        return names
    }

    private static func systemRedoWalk(_ editor: EditorViewModel, _ manager: UndoManager) -> [String] {
        var names: [String] = []
        while manager.canRedo, names.count <= UndoStack.capacity {
            manager.redo()
            names.append(editor.program.name)
        }
        return names
    }

    // MARK: Configuration

    @Test("the editor's manager is its own, and never groups by event")
    func managerConfiguration() {
        let (_, manager) = Self.editor()
        #expect(!manager.groupsByEvent)
        #expect(!manager.canUndo)
        #expect(!manager.canRedo)
    }

    // MARK: 7d — agreement after every kind of transition

    @Test("after edits, the system manager offers exactly the package's undo steps")
    func agreementAfterEdits() {
        let (editor, manager) = Self.editor()
        Self.rename(editor, through: 3)

        #expect(manager.canUndo)
        #expect(!manager.canRedo)
        #expect(Self.systemUndoWalk(editor, manager) == ["p2", "p1", "p0"])
        #expect(Self.systemRedoWalk(editor, manager) == ["p1", "p2", "p3"])
    }

    /// The story's concrete case: edits A and B, undo B **from the toolbar**. A manager that was
    /// not re-synchronised still holds B's undo registration and no redo.
    @Test("a toolbar undo leaves the system manager one step back, with redo")
    func agreementAfterToolbarUndo() {
        let (editor, manager) = Self.editor()
        Self.rename(editor, through: 2)

        editor.undo()

        #expect(editor.program.name == "p1")
        #expect(manager.canRedo)
        #expect(Self.systemUndoWalk(editor, manager) == ["p0"])
        #expect(Self.systemRedoWalk(editor, manager) == ["p1", "p2"])
    }

    @Test("a toolbar redo leaves the system manager one step forward")
    func agreementAfterToolbarRedo() {
        let (editor, manager) = Self.editor()
        Self.rename(editor, through: 2)
        editor.undo()
        editor.undo()

        editor.redo()

        #expect(editor.program.name == "p1")
        #expect(Self.systemUndoWalk(editor, manager) == ["p0"])
        #expect(Self.systemRedoWalk(editor, manager) == ["p1", "p2"])
    }

    @Test("an edit after an undo clears the system manager's redo, as it clears the package's")
    func agreementAfterEditClearsRedo() {
        let (editor, manager) = Self.editor()
        Self.rename(editor, through: 2)
        editor.undo()

        editor.apply(.renameProgram("q"))

        #expect(!manager.canRedo)
        #expect(Self.systemUndoWalk(editor, manager) == ["p1", "p0"])
    }

    /// A coalesced session is one package entry however many keystrokes it took, so it must be
    /// one system step too — a per-keystroke registration would make shake undo a single tap.
    @Test("a closed coalesced session is one system step")
    func agreementAfterCoalescedSession() {
        let (editor, manager) = Self.editor()
        editor.apply(.renameProgram("p1"))
        editor.beginParameterEdit(at: 0)
        for _ in 0 ..< 3 {
            editor.stepNumber(.steps, by: 1)
        }
        editor.endParameterEdit()

        manager.undo()
        #expect(editor.program == Self.renamed("p1"), "one system undo reverts the whole session")
        manager.undo()
        #expect(editor.program == Self.seed)
        #expect(!manager.canUndo)
    }

    /// ADR-036: pushing past 50 evicts the oldest snapshot silently. A manager synchronised only
    /// on edits it saw would still offer 51 steps.
    @Test("after the 50-entry bound evicts, the system manager offers exactly 50 steps")
    func agreementAfterEviction() throws {
        let (editor, manager) = Self.editor()
        Self.rename(editor, through: UndoStack.capacity + 1)
        try #require(editor.undoStack.undoDepth == UndoStack.capacity, "the premise: one entry evicted")

        let walk = Self.systemUndoWalk(editor, manager)

        #expect(walk.count == UndoStack.capacity)
        #expect(walk.last == "p1", "the oldest snapshot went; p0 is unreachable")
        #expect(!editor.canUndo)
    }

    @Test("loading a program empties the system manager in both directions")
    func loadEmptiesTheManager() {
        let (editor, manager) = Self.editor()
        Self.rename(editor, through: 2)
        editor.undo()
        #expect(manager.canUndo && manager.canRedo, "the premise: history in both directions")

        editor.load(Self.renamed("loaded"))

        #expect(!manager.canUndo)
        #expect(!manager.canRedo)
    }

    // MARK: System-driven transitions

    /// A system undo runs the package undo from **inside** the manager's own handler. Calling the
    /// manager from there throws (probe P6), so the bridge must not re-synchronise by rebuilding
    /// at that point; the handler's own inverse registration is what keeps agreement.
    @Test("a system undo then a system redo walk the package history, and agree afterwards")
    func systemUndoAndRedo() {
        let (editor, manager) = Self.editor()
        Self.rename(editor, through: 3)

        manager.undo()
        #expect(editor.program.name == "p2")
        #expect(editor.canUndo && editor.canRedo)

        manager.redo()
        #expect(editor.program.name == "p3")
        #expect(!editor.canRedo)

        manager.undo()
        manager.undo()
        #expect(editor.program.name == "p1")
        #expect(Self.systemUndoWalk(editor, manager) == ["p0"])
        #expect(Self.systemRedoWalk(editor, manager) == ["p1", "p2", "p3"])
    }

    @Test("a toolbar undo after a system undo keeps agreement")
    func mixedSurfaces() {
        let (editor, manager) = Self.editor()
        Self.rename(editor, through: 3)

        manager.undo()
        editor.undo()

        #expect(editor.program.name == "p1")
        #expect(Self.systemRedoWalk(editor, manager) == ["p2", "p3"])
    }

    /// The system path must reach `undo()`'s consequences: the announcement that drives the run's
    /// void, the export discard and the autosave (ADR-038, ADR-045).
    @Test("a system undo and redo announce the program change, once each")
    func systemTransitionsAnnounce() {
        let (editor, manager) = Self.editor()
        Self.rename(editor, through: 1)
        var changes = 0
        editor.onProgramChanged = { changes += 1 }

        manager.undo()
        #expect(changes == 1)
        manager.redo()
        #expect(changes == 2)
    }

    // MARK: 8 — the US-410 pairing survives the bridge

    /// The parameter editor applies `declareVariable` and the `replaceBrick` that uses the name
    /// under one key: one entry, so one system undo must revert both. Undo can never leave a brick
    /// naming a variable it had just declared, or a declaration with nothing using it.
    @Test("one system undo reverts a created variable and the brick that uses it together")
    func systemUndoRevertsVariablePair() throws {
        let seed = Program(
            name: "p0",
            scenes: [Scene(objects: [Object(scripts: [Script(bricks: [.setVariable(name: "", to: .number(1))])])])]
        )
        let (editor, manager) = Self.editor(seed)
        try #require(editor.beginParameterEdit(at: 0))
        try #require(editor.createVariable(named: "Side", for: .variableName) != nil)
        editor.stepNumber(.value, by: 1)
        editor.endParameterEdit()
        try #require(editor.program != seed, "the premise: the session changed the program")

        manager.undo()

        #expect(editor.program == seed)
        #expect(!manager.canUndo)
    }

    // MARK: 4 — no manager

    @Test("with no UndoManager the toolbar doors still undo and redo")
    func noManager() {
        let editor = EditorViewModel(program: Self.seed, undoManager: nil)
        #expect(editor.systemUndoManager == nil)
        editor.apply(.renameProgram("p1"))

        #expect(editor.undo())
        #expect(editor.program == Self.seed)
        #expect(editor.redo())
        #expect(editor.program.name == "p1")
    }
}
