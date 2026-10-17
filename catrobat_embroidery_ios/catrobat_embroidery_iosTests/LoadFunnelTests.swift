@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Samples
import Testing

/// US-411 test-plan item 5: **every whole-program replacement clears the history in both
/// directions — the package stack and the system `UndoManager` alike.** A manager left holding
/// steps after a load would let shake "undo" into a program the user has replaced.
///
/// The story names three callers. Two exist: picking a sample (`select(_:)`) and the launch
/// restore (`restoreSavedProgram()`). The third, starting a blank program, is not a replacement
/// in M4 — the blank program is the editor's *initial* state (ADR-045), so it is asserted as a
/// fresh window with empty history. A user-initiated "new program" (M5) must go through `load`.
@MainActor
@Suite("Whole-program replacement clears both histories")
struct LoadFunnelTests {
    private static func window() -> AppModel {
        AppModel(autosave: ProgramAutosave(store: InMemoryProgramStore()))
    }

    /// Two edits and an undo, so there is history in **both** directions to clear.
    private static func makeHistory(in model: AppModel) throws {
        model.editor.apply(.renameProgram("one"))
        model.editor.apply(.renameProgram("two"))
        model.editor.undo()
        let manager = try #require(model.editor.systemUndoManager)
        try #require(model.editor.canUndo && model.editor.canRedo, "the premise: package history both ways")
        try #require(manager.canUndo && manager.canRedo, "the premise: system history both ways")
    }

    private static func expectEmpty(_ model: AppModel) throws {
        let manager = try #require(model.editor.systemUndoManager)
        #expect(model.editor.undoStack.undoDepth == 0)
        #expect(model.editor.undoStack.redoDepth == 0)
        #expect(!manager.canUndo)
        #expect(!manager.canRedo)
    }

    @Test("launch: a fresh window holds the blank program with no history anywhere")
    func launchBlank() throws {
        let model = Self.window()
        #expect(model.editor.program == .blank)
        try Self.expectEmpty(model)
    }

    @Test("picking a sample clears both histories")
    func select() throws {
        let model = Self.window()
        try Self.makeHistory(in: model)

        model.select(SampleLibrary[.squareCoil])

        try Self.expectEmpty(model)
    }

    /// The restore runs once, before the user can edit — and every edit autosaves, so history
    /// made through the window would be what the restore reads back. The history is therefore
    /// made on the editor **before** it joins the window, where nothing listens to save it.
    @Test("restoring the saved program clears both histories")
    func restore() throws {
        let saved = SampleLibrary[.octagonRosette].program
        let editor = EditorViewModel()
        editor.apply(.renameProgram("one"))
        editor.apply(.renameProgram("two"))
        editor.undo()
        let model = AppModel(
            autosave: ProgramAutosave(store: InMemoryProgramStore(stored: saved)), editor: editor
        )
        let manager = try #require(model.editor.systemUndoManager)
        try #require(manager.canUndo && manager.canRedo, "the premise: system history both ways")

        model.restoreSavedProgram()

        try #require(model.editor.program == saved, "the premise: the restore happened")
        try Self.expectEmpty(model)
    }
}
