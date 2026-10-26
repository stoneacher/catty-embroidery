@testable import catrobat_embroidery_ios
import EditorCore
import EmbroideryEngine
import Foundation
import ProgramModel
import Samples
import StagePreview
import Testing

/// One name (project management slice 5b; brief D4, D8): the project's name is
/// `program.name`, which is the export's `LA` and, sanitised, its file name. The stage's field
/// edits a draft of it that reaches the program only as a valid rename, and a change that
/// differs only in the name keeps the run and re-prepares the export.
@MainActor
@Suite("Project name")
struct ProjectNameTests {
    private struct Window {
        let model: AppModel
        let store: InMemoryProjectStore
        let writer: RecordingDSTFileWriter
    }

    private static func window(
        _ store: InMemoryProjectStore = InMemoryProjectStore(),
        library: ProjectLibrary? = nil
    ) -> Window {
        let writer = RecordingDSTFileWriter()
        let model = AppModel(
            library: library ?? ProjectLibrary(store: store, lastOpened: .disposable()),
            runner: RunViewModel(driver: InterpreterDriver(pacing: ImmediateRunPacing())),
            exporter: ExportViewModel(writer: writer)
        )
        model.launch(sceneID: nil)
        return Window(model: model, store: store, writer: writer)
    }

    /// The bounded spin `ExportWiringTests` uses, for the reason it gives there.
    private static func settle(until condition: () -> Bool, turns: Int = 100_000) async {
        for _ in 0 ..< turns where !condition() {
            await Task.yield()
        }
    }

    private static func finish(_ window: Window) async throws {
        window.model.play()
        await settle(until: { window.model.runner.run.state == .finished(.programFinished) })
        try #require(window.model.runner.run.state == .finished(.programFinished))
        try #require(window.model.exporter.state != .idle, "the premise: a file was prepared")
    }

    /// The `LA` field of the last file written, trimmed of its padding.
    private static func label(_ window: Window) throws -> String {
        let header = try #require(window.writer.written.last).file.data.prefix(20)
        let text = try #require(String(bytes: header, encoding: .ascii))
        try #require(text.hasPrefix("LA:"))
        // Fifteen characters, space-padded, then a carriage return (ADR-012).
        return String(text.dropFirst(3).prefix(DesignName.maximumLength)).trimmingCharacters(in: .whitespaces)
    }

    private static let finishedState = RunState.finished(.programFinished)

    // MARK: A fresh window (US-320)

    @Test("a fresh window's design is named Design, a valid name, with nothing to correct")
    func aFreshWindowHasAValidName() throws {
        let window = Self.window()

        #expect(window.model.editor.program.name == "Design")
        #expect(window.model.nameDraft == "Design")
        #expect(try window.model.exporter.validatedName.get().value == "Design")
        #expect(window.store.saves.isEmpty, "naming the draft is not a change")
    }

    @Test("a second fresh window's design is named uniquely")
    func aSecondFreshWindowIsUniqued() {
        let library = ProjectLibrary(store: InMemoryProjectStore(), lastOpened: .disposable())
        let first = Self.window(library: library)

        let second = Self.window(library: library)

        // The registry holds windows weakly, so the first must still be open.
        withExtendedLifetime(first) {
            #expect(second.model.editor.program.name == "Design 2")
        }
    }

    // MARK: One name for the export (D4)

    @Test("a sample's export name is its program's name", arguments: SampleID.shipping)
    func aSamplesExportNameIsItsProgramName(id: SampleID) throws {
        let window = Self.window()

        window.model.select(SampleLibrary[id])

        #expect(window.model.exporter.name == SampleLibrary[id].program.name)
        #expect(try window.model.exporter.validatedName.get().value == SampleLibrary[id].program.name)
    }

    /// ADR-026 keeps the two apart: `A/B` is a valid `LA` name, and only the file name is
    /// sanitised.
    @Test("the export's LA is the program's name and its file name is the sanitised form")
    func theLabelIsTheNameAndTheFileIsSanitised() async throws {
        let window = Self.window()
        window.model.select(SampleLibrary[.squareCoil])
        window.model.nameDraft = "A/B"
        #expect(window.model.commitName())

        try await Self.finish(window)

        #expect(try Self.label(window) == "A/B")
        #expect(try #require(window.writer.written.last).name.value == "A_B.dst")
    }

    // MARK: The draft buffer (D8)

    @Test("committing a valid draft renames the program, trimmed, as one undoable edit")
    func committingAValidDraftRenames() {
        let window = Self.window()

        window.model.nameDraft = "  Moon  "
        #expect(window.model.commitName())

        #expect(window.model.editor.program.name == "Moon")
        #expect(window.model.nameDraft == "Moon")
        #expect(window.store.saves.last?.program.name == "Moon")
        window.model.editor.undo()
        #expect(window.model.editor.program.name == "Design")
        #expect(window.model.nameDraft == "Design", "the draft follows the program back")
    }

    /// An invalid name never reaches the program, the export, the history or the disk.
    @Test("committing an invalid draft changes nothing and returns the field to the name")
    func committingAnInvalidDraftReverts() {
        let window = Self.window()

        window.model.nameDraft = "far too long a name for LA"
        #expect(!window.model.commitName())

        #expect(window.model.editor.program.name == "Design")
        #expect(window.model.nameDraft == "Design")
        #expect(!window.model.editor.canUndo)
        #expect(window.store.saves.isEmpty)
    }

    // MARK: Rename-only changes keep the run (D8)

    @Test("a rename keeps a finished run and re-prepares the export under the new name")
    func aRenameKeepsTheRun() async throws {
        let window = Self.window()
        window.model.select(SampleLibrary[.squareCoil])
        try await Self.finish(window)
        let writes = window.writer.written.count

        window.model.nameDraft = "Moon"
        window.model.commitName()

        #expect(window.model.runner.run.state == Self.finishedState)
        #expect(window.writer.written.count == writes + 1)
        #expect(try Self.label(window) == "Moon")
        #expect(window.store.saves.last?.program.name == "Moon", "a rename is still saved")
    }

    @Test("undoing and redoing a rename keep the run and re-prepare the export each time")
    func undoAndRedoOfARenameKeepTheRun() async throws {
        let window = Self.window()
        window.model.select(SampleLibrary[.squareCoil])
        try await Self.finish(window)
        window.model.nameDraft = "Moon"
        window.model.commitName()

        window.model.editor.undo()
        #expect(window.model.runner.run.state == Self.finishedState)
        #expect(try Self.label(window) == SampleLibrary[.squareCoil].program.name)

        window.model.editor.redo()
        #expect(window.model.runner.run.state == Self.finishedState)
        #expect(try Self.label(window) == "Moon")
    }

    @Test("consecutive renames keep the run, and the export carries the last name")
    func consecutiveRenames() async throws {
        let window = Self.window()
        window.model.select(SampleLibrary[.squareCoil])
        try await Self.finish(window)

        for name in ["Moon", "Star", "Sun"] {
            window.model.nameDraft = name
            window.model.commitName()
        }

        #expect(window.model.runner.run.state == Self.finishedState)
        #expect(try Self.label(window) == "Sun")
    }

    /// A content change voids the run; undoing back to a state that differs from the voided
    /// one only by name must not bring a run back, and neither must redoing.
    @Test("a run voided by a content change stays void through undo and redo")
    func aVoidedRunStaysVoid() async throws {
        let window = Self.window()
        window.model.select(SampleLibrary[.squareCoil])
        try await Self.finish(window)
        window.model.nameDraft = "Moon"
        window.model.commitName()

        window.model.editor.apply(.delete(at: BrickAddress(brickIndex: 3)))
        #expect(window.model.runner.run.state == .idle)
        #expect(window.model.exporter.state == .idle)

        window.model.editor.undo()
        #expect(window.model.runner.run.state == .idle)
        #expect(window.model.exporter.state == .idle)
        window.model.editor.undo()
        #expect(window.model.runner.run.state == .idle, "undoing the rename brings nothing back")
        window.model.editor.redo()
        window.model.editor.redo()
        #expect(window.model.runner.run.state == .idle)
    }

    /// Stopped rather than finished, so the test holds the run open: a stopped run terminates
    /// and prepares its export like a finished one.
    @Test("a rename while running keeps the run, and its file is named for the new name", .hangGuard)
    func aRenameWhileRunning() async throws {
        let pacing = GatedPacing()
        let writer = RecordingDSTFileWriter()
        let model = AppModel(
            library: .inMemory(),
            runner: RunViewModel(driver: InterpreterDriver(pacing: pacing)),
            exporter: ExportViewModel(writer: writer)
        )
        model.launch(sceneID: nil)
        model.select(SampleLibrary[.squareCoil])
        model.play()
        for _ in 0 ..< 3 {
            await pacing.grant()
        }
        await Self.settle(until: { !model.runner.run.display.isEmpty })
        try #require(model.runner.run.state.isRunning)

        model.nameDraft = "Moon"
        model.commitName()
        #expect(model.runner.run.state.isRunning, "a rename does not stop the run")
        #expect(!model.runner.run.display.isEmpty, "nor clear what it has stitched")

        model.runner.stop()
        await Self.settle(until: { model.runner.run.state == .finished(.stoppedByUser) })
        #expect(try #require(writer.written.last).name.value == "Moon.dst")
    }

    @Test("a rename with nothing prepared prepares nothing, and is saved")
    func aRenameWithNothingPrepared() {
        let window = Self.window()

        window.model.nameDraft = "Moon"
        window.model.commitName()

        #expect(window.writer.written.isEmpty)
        #expect(window.model.exporter.state == .idle)
        #expect(window.store.saves.map(\.program.name) == ["Moon"])
    }

    // MARK: The title is the name (D4)

    private static func title(_ window: Window) throws -> String {
        String(localized: try #require(window.model.selection?.title))
    }

    @Test("the stage is titled with the project's name, and follows a rename and its undo")
    func theTitleFollowsTheName() throws {
        let window = Self.window()
        #expect(try Self.title(window) == "Design")

        window.model.select(SampleLibrary[.squareCoil])
        #expect(try Self.title(window) == "Square Coil")

        window.model.nameDraft = "Moon"
        window.model.commitName()
        #expect(try Self.title(window) == "Moon")

        window.model.editor.undo()
        #expect(try Self.title(window) == "Square Coil")
    }

    /// ADR-038: any change means the program is no longer the bundled sample, a rename too.
    @Test("a rename clears the sample's highlight")
    func aRenameClearsProvenance() {
        let window = Self.window()
        window.model.select(SampleLibrary[.squareCoil])

        window.model.nameDraft = "Moon"
        window.model.commitName()

        #expect(window.model.selection?.provenance == nil)
    }

    // MARK: The chokepoint reports both programs (D8)

    @Test("every change reports the program before and after it")
    func changesReportBeforeAndAfter() {
        let editor = EditorViewModel(program: SampleLibrary[.squareCoil].program)
        var reports: [(Program, Program)] = []
        editor.onProgramChanged = { before, after in reports.append((before, after)) }
        let original = editor.program

        editor.apply(.renameProgram("Moon"))
        let renamed = editor.program
        editor.undo()
        editor.redo()

        #expect(reports.map(\.0) == [original, renamed, original])
        #expect(reports.map(\.1) == [renamed, original, renamed])
    }
}
