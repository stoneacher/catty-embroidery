@testable import catrobat_embroidery_ios
import EditorCore
import EmbroideryEngine
import Foundation
import ProgramModel
import StagePreview
import Testing

/// M4's exit criteria 1 and 3, each as **one chained test** through the objects the app wires
/// together (Editor UI feature, slice 3). Every link already had a test of its own; what was
/// missing was the chain, which is what the criteria actually claim.
@MainActor
@Suite("M4 exit criteria, end to end")
struct ExitCriteriaTests {
    private static func settle(until condition: () -> Bool, turns: Int = 100_000) async {
        for _ in 0 ..< turns where !condition() {
            await Task.yield()
        }
    }

    private static func immediateRunner() -> RunViewModel {
        RunViewModel(driver: InterpreterDriver(pacing: ImmediateRunPacing()))
    }

    /// A template's single brick, so the expectation follows `BrickDefaults` instead of
    /// restating it.
    private static func head(_ kind: BrickKind) -> Brick {
        kind.template()[0]
    }

    // MARK: Criterion 1

    /// Built from the blank program the app launches with — palette, a parameter, a reorder —
    /// then run and exported. The program is asserted as a **whole value** before it runs, so
    /// the export is known to be of exactly the program the user built; and the file's bytes
    /// are asserted equal to an independent run of that literal program, so the file is known
    /// to be of *that* run.
    @Test("a program built from nothing runs to the end and exports as .dst",
          .timeLimit(.minutes(1)))
    func builtFromNothingRunsAndExports() async throws {
        let writer = RecordingDSTFileWriter()
        let model = AppModel(
            autosave: ProgramAutosave(store: InMemoryProgramStore()),
            runner: Self.immediateRunner(),
            exporter: ExportViewModel(writer: writer)
        )
        try #require(model.editor.program == .blank, "the premise: launch holds the blank program")

        // Palette: a running stitch, then a loop — whose opener is selected, so the next two
        // land inside it (ADR-045's insertion rule).
        model.addFromPalette(.runningStitch)
        model.addFromPalette(.repeatLoop)
        model.addFromPalette(.moveNSteps)
        model.addFromPalette(.turnRight)
        // A parameter: five stepper taps on the move, one session.
        try #require(model.editor.beginParameterEdit(at: 2))
        for _ in 0 ..< 5 {
            model.editor.stepNumber(.steps, by: 1)
        }
        model.editor.endParameterEdit()
        // A reorder: drag the move below the turn, inside the loop.
        model.editor.moveRows(fromOffsets: [2], toOffset: 4)

        guard case let .moveNSteps(.number(defaultSteps)) = Self.head(.moveNSteps) else {
            Issue.record("the move template is not a literal")
            return
        }
        var expected = Program.blank
        expected.scenes[0].objects[0].scripts[0].bricks = [
            Self.head(.runningStitch),
            Self.head(.repeatLoop),
            Self.head(.turnRight),
            .moveNSteps(.number(defaultSteps + 5)),
            .loopEnd
        ]
        #expect(model.editor.program == expected)
        #expect(model.selection?.provenance == nil, "no bundled sample is involved")

        model.exporter.name = "HandBuilt"
        model.play()
        await Self.settle(until: { model.runner.run.state == .finished(.programFinished) })
        try #require(model.runner.run.state == .finished(.programFinished))

        let written = try #require(writer.written.last)
        #expect(written.name.value == "HandBuilt.dst")
        #expect(model.exporter.state == .ready(written.url))

        // The same literal program, run on its own, serialises to the same bytes.
        let reference = Self.immediateRunner()
        reference.play(expected)
        await Self.settle(until: { reference.run.state == .finished(.programFinished) })
        let stream = try #require(reference.run.exportModel)
        #expect(stream.count > 1, "a design with stitches, not just the header")
        #expect(try written.file.data == DSTFile(stream: stream, name: "HandBuilt").data)
    }

    // MARK: Criterion 3

    /// A force-quit runs no lifecycle code, so what survives it is what was saved **at the
    /// change**. This edits through a window on the real Documents store, never calls
    /// `sceneDidLeaveActive()`, and opens a fresh coordinator and window over the same
    /// directory — the process boundary, with nothing carried across but the disk.
    @Test("an edit survives a relaunch with no lifecycle save, through the real disk")
    func editSurvivesRelaunchWithoutLifecycleSave() throws {
        try inDisposableDirectory { directory in
            let before = AppModel(autosave: ProgramAutosave(store: DocumentsProgramStore(directory: directory)))
            before.restoreSavedProgram()
            before.addFromPalette(.stitch)
            before.editor.apply(.renameProgram("Kept"))
            let edited = before.editor.program

            let after = AppModel(autosave: ProgramAutosave(store: DocumentsProgramStore(directory: directory)))
            after.restoreSavedProgram()

            #expect(after.editor.program == edited)
            #expect(after.editor.program != .blank)
        }
    }
}
