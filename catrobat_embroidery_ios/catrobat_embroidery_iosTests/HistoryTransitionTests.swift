@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Samples
import StagePreview
import Testing

/// US-408: what a toolbar undo or redo does to the rest of the window — and since US-411, a
/// system-driven one through the `UndoManager` bridge, which must carry the same consequences.
///
/// Undo restores a snapshot from **outside** the `EditAction` vocabulary, so nothing that
/// hangs off an applied edit follows it automatically — `RunViewModel.reset()` and
/// `onRunDiscarded` are explicit calls that observe nothing. The story's concrete case is the
/// first test: delete a loop from P to get Q, run Q to completion, undo back to P. Without the
/// wiring, Q's preview and its prepared `.dst` stay on screen and shareable beside P's script,
/// which is the ADR-026 export-consistency and ADR-038 violation this story exists to prevent.
///
/// Driven through `AppModel` for the `WorkingProgramTests` reason: every claim is about the
/// wire between the editor, the run, the exporter and the autosave.
@MainActor
@Suite("History transitions")
struct HistoryTransitionTests {
    private static func settle(until condition: () -> Bool, turns: Int = 100_000) async {
        for _ in 0 ..< turns where !condition() {
            await Task.yield()
        }
    }

    private struct Window {
        let model: AppModel
        let store: InMemoryProgramStore
        let writer: RecordingDSTFileWriter
    }

    private static func window() -> Window {
        let store = InMemoryProgramStore()
        let writer = RecordingDSTFileWriter()
        let model = AppModel(
            autosave: ProgramAutosave(store: store),
            runner: RunViewModel(driver: InterpreterDriver(pacing: ImmediateRunPacing())),
            exporter: ExportViewModel(writer: writer)
        )
        return Window(model: model, store: store, writer: writer)
    }

    /// Square Coil's first loop — "Repeat 31 times", its body and its end.
    private static let deleteTheFirstLoop = EditAction.delete(at: BrickAddress(brickIndex: 3))

    /// Runs whatever the window holds to the end and requires that a file was prepared.
    private static func finish(_ window: Window) async throws {
        window.model.play()
        await settle(until: { window.model.runner.run.state == .finished(.programFinished) })
        try #require(window.model.runner.run.state == .finished(.programFinished))
        try #require(window.model.exporter.state != .idle, "the premise: a file was prepared")
    }

    /// Everything a history transition must leave behind: no run, no file, and the program on
    /// screen saved exactly once.
    private static func expectVoidedAndSaved(
        _ window: Window, program: Program, savesBefore: Int, removalsBefore: Int
    ) {
        #expect(window.model.runner.run.state == .idle)
        #expect(window.model.runner.run.display.isEmpty)
        #expect(window.model.runner.run.exportModel == nil)
        #expect(window.model.exporter.state == .idle, "a file describing the other program is still offered")
        #expect(window.writer.removeAllCount > removalsBefore)
        #expect(window.store.saves.count == savesBefore + 1)
        #expect(window.store.saves.last == program)
    }

    /// The two doors a history transition comes through (US-411): the toolbar drives the package
    /// stack directly, and the system — shake, ⌘Z, the edit menu — drives it through the bridge's
    /// `UndoManager`. The consequences must not depend on which.
    enum HistorySurface: CaseIterable {
        case toolbar, system
    }

    private static func undo(_ window: Window, via surface: HistorySurface) throws -> Bool {
        switch surface {
        case .toolbar:
            return window.model.editor.undo()
        case .system:
            let manager = try #require(window.model.editor.systemUndoManager)
            guard manager.canUndo else { return false }
            manager.undo()
            return true
        }
    }

    private static func redo(_ window: Window, via surface: HistorySurface) throws -> Bool {
        switch surface {
        case .toolbar:
            return window.model.editor.redo()
        case .system:
            let manager = try #require(window.model.editor.systemUndoManager)
            guard manager.canRedo else { return false }
            manager.redo()
            return true
        }
    }

    @Test("undo after running an edit voids the run, discards its file and saves the restored program",
          .timeLimit(.minutes(1)), arguments: HistorySurface.allCases)
    func undoVoidsTheRunAndSaves(via surface: HistorySurface) async throws {
        let window = Self.window()
        let sample = SampleLibrary[.squareCoil]
        window.model.select(sample)
        window.model.editor.apply(Self.deleteTheFirstLoop)
        try await Self.finish(window)
        let savesBefore = window.store.saves.count
        let removalsBefore = window.writer.removeAllCount

        #expect(try Self.undo(window, via: surface))

        #expect(window.model.editor.program == sample.program)
        Self.expectVoidedAndSaved(
            window, program: sample.program, savesBefore: savesBefore, removalsBefore: removalsBefore
        )
        // The save is not an edit: the history is exactly where the undo left it.
        #expect(window.model.editor.undoStack.undoDepth == 0)
        #expect(window.model.editor.undoStack.redoDepth == 1)
    }

    @Test("redo after running the undone program voids the run, discards its file and saves",
          .timeLimit(.minutes(1)), arguments: HistorySurface.allCases)
    func redoVoidsTheRunAndSaves(via surface: HistorySurface) async throws {
        let window = Self.window()
        window.model.select(SampleLibrary[.squareCoil])
        window.model.editor.apply(Self.deleteTheFirstLoop)
        let edited = window.model.editor.program
        window.model.editor.undo()
        try await Self.finish(window)
        let savesBefore = window.store.saves.count
        let removalsBefore = window.writer.removeAllCount

        #expect(try Self.redo(window, via: surface))

        #expect(window.model.editor.program == edited)
        Self.expectVoidedAndSaved(
            window, program: edited, savesBefore: savesBefore, removalsBefore: removalsBefore
        )
        #expect(window.model.editor.undoStack.undoDepth == 1)
        #expect(window.model.editor.undoStack.redoDepth == 0)
    }

    /// The other half, as `WorkingProgramTests` pins it for a rejected edit: an undo with
    /// nothing to undo leaves a finished design and its file exactly where they were.
    @Test("undo with nothing to undo keeps the finished run and saves nothing", .timeLimit(.minutes(1)))
    func emptyUndoKeepsTheRun() async throws {
        let window = Self.window()
        window.model.select(SampleLibrary[.squareCoil])
        try await Self.finish(window)
        let prepared = window.model.exporter.state
        let savesBefore = window.store.saves.count
        let removalsBefore = window.writer.removeAllCount

        #expect(!window.model.editor.undo())
        #expect(!window.model.editor.redo())

        #expect(window.model.runner.run.state == .finished(.programFinished))
        #expect(window.model.exporter.state == prepared)
        #expect(window.writer.removeAllCount == removalsBefore)
        #expect(window.store.saves.count == savesBefore)
    }

    /// An undo is not a selection: like an edit (`WorkingProgramTests`), it keeps the zoom the
    /// user chose and the screen they are on.
    @Test("undo keeps the zoom and the path")
    func undoKeepsTheZoomAndPath() throws {
        let window = Self.window()
        window.model.select(SampleLibrary[.squareCoil])
        let size = ViewSize(width: 390, height: 500)
        let fit = StageTransform.fitting(StageGeometry.box, in: size)
        window.model.interaction.commit(StageGesture(magnification: 4), fitting: fit, in: size)
        window.model.editor.apply(Self.deleteTheFirstLoop)
        let zoomed = window.model.interaction
        let path = window.model.path

        try #require(window.model.editor.undo())

        #expect(window.model.interaction == zoomed)
        #expect(window.model.path == path)
    }
}
