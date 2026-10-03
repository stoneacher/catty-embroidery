@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Samples
import StagePreview
import Testing

/// US-410's presentation wiring: the parameter editor shows exactly while the editor's session
/// is open, and every path that can tear the sheet down without its `onDisappear` — ADR-023's
/// container swap, a pushed stage, a new selection — ends the session itself (test-first item
/// 6, the window half).
@MainActor
@Suite("Parameter editor presentation")
struct ParameterEditorPresentationTests {
    private static func window() -> AppModel {
        let model = AppModel(
            autosave: ProgramAutosave(store: InMemoryProgramStore(stored: nil)),
            runner: RunViewModel(driver: InterpreterDriver(pacing: ImmediateRunPacing())),
            exporter: ExportViewModel(writer: RecordingDSTFileWriter())
        )
        model.editor.insert(.moveNSteps)
        return model
    }

    @Test("Edit opens the editor on the selected brick and closes the palette")
    func opening() {
        let model = Self.window()
        model.isPalettePresented = true

        model.openParameterEditor()

        #expect(model.isParameterEditorPresented)
        #expect(model.editor.parameterSession?.address == BrickAddress(brickIndex: 0))
        #expect(!model.isPalettePresented)
    }

    @Test("with nothing selected, Edit opens nothing")
    func nothingSelected() {
        let model = Self.window()
        model.editor.selectedBrickIndex = nil
        model.openParameterEditor()
        #expect(!model.isParameterEditorPresented)
    }

    /// The sheet's binding writes `false` on a swipe-down, and that is the end of the session.
    @Test("dismissing through the binding ends the session")
    func dismissing() {
        let model = Self.window()
        model.openParameterEditor()
        model.editor.stepNumber(.steps, by: 1)

        model.isParameterEditorPresented = false

        #expect(model.editor.parameterSession == nil)
        #expect(model.editor.undoStack.openSession == nil)
    }

    @Test("pushing the stage ends the session")
    func pushingTheStage() {
        let model = Self.window()
        model.openParameterEditor()
        model.path.append(.stage)
        #expect(!model.isParameterEditorPresented)
        #expect(model.editor.undoStack.openSession == nil)
    }

    /// The case no `path` write covers: the window went compact with the stage on top.
    @Test("a container swap that leaves the stage on top ends the session")
    func containerSwap() {
        let model = Self.window()
        model.openParameterEditor()
        model.path = [.script, .stage]
        model.openParameterEditor() // A regular-width column could still open it.

        model.layoutChanged(isCompact: true)

        #expect(!model.isParameterEditorPresented)
        #expect(model.editor.undoStack.openSession == nil)
    }

    @Test("selecting a sample ends the session")
    func selecting() throws {
        let model = Self.window()
        model.openParameterEditor()
        try model.select(#require(SampleLibrary.all.first))
        #expect(!model.isParameterEditorPresented)
    }

    /// Live-apply reaches the window's consequences (ADR-038) like any other edit: the run is
    /// voided, once per change rather than once per session.
    @Test("a live parameter change voids the run")
    func liveChangeVoidsTheRun() async throws {
        let model = Self.window()
        model.play()
        for _ in 0 ..< 100_000 where model.runner.run.state != .finished(.programFinished) {
            await Task.yield()
        }
        try #require(model.runner.run.state == .finished(.programFinished))

        model.openParameterEditor()
        model.editor.stepNumber(.steps, by: 1)

        #expect(model.runner.run.state == .idle)
    }
}
