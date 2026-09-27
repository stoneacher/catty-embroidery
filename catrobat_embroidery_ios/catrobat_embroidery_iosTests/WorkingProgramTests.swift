@testable import catrobat_embroidery_ios
import EditorCore
import EmbroideryEngine
import ProgramModel
import Samples
import StagePreview
import Testing

/// US-405 test-plan items 3–8 at the app layer: the working program replaces the sample
/// selection, and an applied edit voids the run (ADR-038).
///
/// Driven through the objects the app actually wires together — `AppModel` with an immediate
/// driver and a recording writer, the `ExportWiringTests` arrangement — because every claim
/// here is about the *wiring* between the editor, the run and the exporter, and a test of any
/// one of them alone would pass with the wire cut.
@MainActor
@Suite("Working program")
struct WorkingProgramTests {
    /// The bounded spin `ExportWiringTests` uses, for the reason it gives there.
    private static func settle(until condition: () -> Bool, turns: Int = 100_000) async {
        for _ in 0 ..< turns where !condition() {
            await Task.yield()
        }
    }

    private static func immediateModel(writer: RecordingDSTFileWriter = RecordingDSTFileWriter()) -> AppModel {
        AppModel(
            runner: RunViewModel(driver: InterpreterDriver(pacing: ImmediateRunPacing())),
            exporter: ExportViewModel(writer: writer)
        )
    }

    /// An edit every shipping sample accepts and that changes it: no sample is called this.
    private static let edit = EditAction.renameProgram("US-405 edited")

    /// Selects `id`, runs it to the end and requires that a file was prepared — the state an
    /// edit has something to void in.
    private static func finishedModel(
        _ id: SampleID, writer: RecordingDSTFileWriter
    ) async throws -> AppModel {
        let model = immediateModel(writer: writer)
        model.select(SampleLibrary[id])
        model.play()
        await settle(until: { model.runner.run.state == .finished(.programFinished) })
        try #require(model.runner.run.state == .finished(.programFinished))
        try #require(model.exporter.state != .idle, "the premise: a file was prepared")
        return model
    }

    // MARK: 8 — launch

    /// The blank program is what the model holds with nothing picked — and, decided at
    /// planning (2026-09-27), the stage does **not** yet treat it as a selection: US-405 is
    /// "nothing new visible", and US-407 owns the blank program's empty state.
    @Test("launch holds the blank program and selects nothing")
    func launchHoldsTheBlankProgramAndSelectsNothing() {
        let model = Self.immediateModel()

        #expect(model.editor.program == .blank)
        #expect(model.selection == nil)
        #expect(!model.samples.contains { model.isSelected($0) })

        model.play()
        #expect(model.runner.run.state == .idle, "play with nothing selected must not run the blank program")
    }

    // MARK: 3 — provenance

    @Test("loading a sample sets its provenance; the first applied edit clears it")
    func loadingSetsProvenanceAndAnEditClearsIt() throws {
        let model = Self.immediateModel()
        let sample = SampleLibrary[.octagonRosette]

        model.select(sample)
        let loaded = try #require(model.selection)
        #expect(loaded.provenance == sample.id)
        #expect(model.isSelected(sample))

        model.editor.apply(Self.edit)

        let edited = try #require(model.selection, "an edit must not clear the selection itself")
        #expect(edited.provenance == nil)
        #expect(!model.isSelected(sample), "the picker highlight still claims the edited program is the sample")
        // What an edit must *not* touch: the title (still this design), the generation (not a
        // new selection), the path (the stage stays on screen) and the name the user may have
        // typed.
        #expect(edited.title == loaded.title)
        #expect(edited.generation == loaded.generation)
        #expect(model.path == [.stage])
        #expect(model.exporter.name == sample.id.resourceName)
    }

    @Test("a rejected edit keeps the provenance")
    func aRejectedEditKeepsTheProvenance() {
        let model = Self.immediateModel()
        let sample = SampleLibrary[.squareCoil]
        model.select(sample)

        let result = model.editor.apply(.insert(.loopEnd, at: BrickAddress(brickIndex: 0)))

        #expect(result == .rejected(.cannotInsertLoopEnd))
        #expect(model.selection?.provenance == sample.id)
        #expect(model.isSelected(sample))
    }

    // MARK: 4 — reloading

    /// US-304's "start over" contract survives the generalisation, and now reaches the
    /// history too: picking the sample again discards the edits, not just the run.
    @Test("loading the same sample twice re-publishes it and resets the history")
    func reloadingRepublishesAndResetsTheHistory() throws {
        let model = Self.immediateModel()
        let sample = SampleLibrary[.squareCoil]
        model.select(sample)
        let first = try #require(model.selection)
        model.editor.apply(Self.edit)
        try #require(model.editor.undoStack.undoDepth == 1, "the premise: there is history to reset")

        model.select(sample)

        let second = try #require(model.selection)
        #expect(second != first)
        #expect(second.generation == first.generation + 1)
        #expect(second.provenance == sample.id)
        #expect(model.editor.program == sample.program)
        #expect(!model.editor.undoStack.canUndo)
        #expect(!model.editor.undoStack.canRedo)
    }

    // MARK: 5 — the library is not the working program

    /// True by construction today — `SampleProgram.program` is a `let` of value type — and
    /// asserted because a refactor to a reference-typed model would make it false without a
    /// compiler error. `SampleLibrary.all` is process-wide: a mutation here would be seen by
    /// every window and by the next pick.
    @Test("editing a loaded sample leaves the library's copy unchanged")
    func editingALoadedSampleLeavesTheLibraryUntouched() throws {
        let model = Self.immediateModel()
        let pristine = SampleLibrary[.octagonRosette].program
        model.select(SampleLibrary[.octagonRosette])

        model.editor.apply(Self.edit)

        #expect(model.editor.program != pristine, "the premise: the working program changed")
        #expect(SampleLibrary[.octagonRosette].program == pristine)
        let listed = try #require(SampleLibrary.all.first { $0.id == .octagonRosette })
        #expect(listed.program == pristine)
    }

    // MARK: 6 — an applied edit voids the run

    @Test("an applied edit discards the finished run and its prepared file", .timeLimit(.minutes(1)))
    func anAppliedEditDiscardsTheRunAndTheFile() async throws {
        let writer = RecordingDSTFileWriter()
        let model = try await Self.finishedModel(.squareCoil, writer: writer)
        let removalsBefore = writer.removeAllCount

        model.editor.apply(Self.edit)

        #expect(model.runner.run.state == .idle)
        #expect(model.runner.run.display.isEmpty)
        #expect(model.runner.run.exportModel == nil)
        #expect(model.exporter.state == .idle, "a file describing the pre-edit program is still offered")
        #expect(writer.removeAllCount > removalsBefore)
    }

    /// The generation bump is what stops a voided run's buffered frames landing after the
    /// reset — ADR-027's discard path, reused rather than reimplemented.
    @Test("an edit applied mid-run leaves nothing behind once the run would have finished",
          .timeLimit(.minutes(1)))
    func anEditMidRunLeavesNothingBehind() async throws {
        let model = Self.immediateModel()
        model.select(SampleLibrary[.squareCoil])
        model.play()
        try #require(model.runner.run.state.isRunning, "the premise: the run is in flight")

        model.editor.apply(Self.edit)

        for _ in 0 ..< 5000 {
            await Task.yield()
        }
        #expect(model.runner.run.state == .idle)
        #expect(model.runner.run.display.isEmpty)
        #expect(model.runner.run.exportModel == nil)
        #expect(model.exporter.state == .idle)
    }

    /// The other half of item 6, and the reason ADR-033 made `apply` return a result: a
    /// rejected edit leaves a finished design, and the file prepared from it, exactly where
    /// they were.
    @Test("a rejected edit keeps the finished run and its prepared file", .timeLimit(.minutes(1)))
    func aRejectedEditKeepsTheRunAndTheFile() async throws {
        let writer = RecordingDSTFileWriter()
        let model = try await Self.finishedModel(.squareCoil, writer: writer)
        let preparedBefore = model.exporter.state
        let removalsBefore = writer.removeAllCount

        model.editor.apply(.insert(.loopEnd, at: BrickAddress(brickIndex: 0)))

        #expect(model.runner.run.state == .finished(.programFinished))
        #expect(!model.runner.run.display.isEmpty)
        #expect(model.exporter.state == preparedBefore)
        #expect(writer.removeAllCount == removalsBefore)
    }

    /// Decided at planning (2026-09-27): an edit that applies and changes nothing voids
    /// nothing.
    @Test("an edit that changes nothing keeps the finished run", .timeLimit(.minutes(1)))
    func anUnchangingEditKeepsTheRun() async throws {
        let writer = RecordingDSTFileWriter()
        let model = try await Self.finishedModel(.squareCoil, writer: writer)
        let preparedBefore = model.exporter.state

        model.editor.apply(.renameProgram(model.editor.program.name))

        #expect(model.runner.run.state == .finished(.programFinished))
        #expect(model.exporter.state == preparedBefore)
        #expect(model.selection?.provenance == .squareCoil)
    }

    /// Play after an edit runs the **edited** program, not the sample it came from — the
    /// reason the selection no longer carries a program for `play()` to reach.
    @Test("playing after an edit runs the working program", .timeLimit(.minutes(1)))
    func playingAfterAnEditRunsTheWorkingProgram() async throws {
        let model = Self.immediateModel()
        model.select(SampleLibrary[.squareCoil])
        // Deleting the first brick changes what is stitched, so the two runs' export models
        // cannot coincide.
        model.editor.apply(.delete(at: BrickAddress(brickIndex: 0)))
        let edited = model.editor.program
        try #require(edited != SampleLibrary[.squareCoil].program)

        model.play()
        await Self.settle(until: { model.runner.run.state == .finished(.programFinished) })
        let editedExport = try #require(model.runner.run.exportModel)

        let reference = Self.immediateModel()
        reference.runner.play(edited)
        await Self.settle(until: { reference.runner.run.state == .finished(.programFinished) })
        #expect(reference.runner.run.exportModel == editedExport)
    }

    // MARK: 7 — the camera

    /// The divergence between the two callers of the discard path: a new *selection* arrives
    /// fitted (`AppModelTests.selectingADesignReturnsTheStageToTheFit`), a new *edit* keeps
    /// the zoom the user chose. Re-fitting on every parameter nudge would be unusable.
    @Test("an applied edit voids the run but keeps the zoom")
    func anAppliedEditKeepsTheZoom() throws {
        let model = Self.immediateModel()
        let sample = SampleLibrary[.squareCoil]
        model.select(sample)
        let size = ViewSize(width: 390, height: 500)
        let fit = StageTransform.fitting(StageGeometry.box, in: size)
        model.interaction.commit(StageGesture(magnification: 4), fitting: fit, in: size)
        try #require(!model.interaction.isFollowingFit, "premise: the stage is zoomed")
        model.play()
        try #require(model.runner.run.state != .idle, "premise: there is a run to void")
        let zoomed = model.interaction

        model.editor.apply(Self.edit)

        #expect(model.runner.run.state == .idle, "the edit must still void the run")
        #expect(!model.interaction.isFollowingFit, "an edit re-fitted the camera")
        // The whole value, not only the flag: an edit that moved the pan or changed the zoom
        // while staying zoomed would pass the line above (Codex US-405 round 1).
        #expect(model.interaction == zoomed, "an edit changed the zoom or pan")

        // And the other caller still does.
        model.select(sample)
        #expect(model.interaction.isFollowingFit)
    }
}
