@testable import catrobat_embroidery_ios
import EditorCore
import EmbroideryEngine
import Foundation
import ProgramModel
import Projects
import StagePreview
import SwiftUI
import Testing

/// The roadmap's haptic map, and nothing else (Release readiness D3, ADR-052): a selection
/// tick on brick add and reorder drop, success on a completed run whose export can be shared,
/// an error on each failed export attempt.
///
/// The tests observe `AppModel.haptic`, the pulse one root `.sensoryFeedback` plays. A pulse
/// carries a serial, so "pulsed once" is "the serial moved by one", and "pulsed nothing" is
/// "the pulse is unchanged".
@MainActor
@Suite("Haptic map")
struct HapticMapTests {
    // MARK: Selection

    @Test("a palette insert the editor accepts pulses selection once")
    func paletteInsertPulsesSelectionOnce() {
        let model = Self.window()
        let before = model.haptic

        model.addFromPalette(.stitch)

        #expect(model.haptic?.kind == .selection)
        #expect(Self.pulses(from: before, to: model.haptic) == 1)
    }

    @Test("a palette insert the editor refuses pulses nothing")
    func refusedPaletteInsertPulsesNothing() {
        let model = Self.window()
        let before = model.haptic

        model.addFromPalette(.loopEnd)

        #expect(model.haptic == before)
    }

    @Test("two inserts in a row are two pulses, not one")
    func consecutiveInsertsEachPulse() {
        let model = Self.window()
        let before = model.haptic

        model.addFromPalette(.stitch)
        let first = model.haptic
        model.addFromPalette(.wait)

        #expect(model.haptic != first, "the second insert must be a new trigger")
        #expect(Self.pulses(from: before, to: model.haptic) == 2)
    }

    @Test("a reorder drop that changes the program pulses selection")
    func dropThatMovesPulsesSelection() {
        let model = Self.windowWithRows()
        let before = model.haptic
        let program = model.editor.program

        model.dropRows(fromOffsets: [0], toOffset: 2)

        #expect(model.editor.program != program, "the fixture's drop must really move a row")
        #expect(model.haptic?.kind == .selection)
        #expect(Self.pulses(from: before, to: model.haptic) == 1)
    }

    @Test("a drop that changes nothing, or that the editor refuses, pulses nothing")
    func refusedOrNoOpDropPulsesNothing() {
        let model = Self.windowWithRows()
        let before = model.haptic

        model.dropRows(fromOffsets: [0], toOffset: 0)
        model.dropRows(fromOffsets: [0], toOffset: 1)
        model.dropRows(fromOffsets: [99], toOffset: 0)

        #expect(model.haptic == before)
    }

    /// The editor refuses a drop back onto its own place, but swapping two identical rows is
    /// an applied move that changes nothing. Only this case tells "applied" from "changed"
    /// (a mutant that pulsed on any applied move survived without it).
    @Test("a drop that swaps two identical rows is applied, changes nothing, and pulses nothing")
    func dropBetweenIdenticalRowsPulsesNothing() {
        let model = Self.window()
        for kind in [BrickKind.stitch, .stitch, .sewUp] {
            _ = model.editor.insert(kind)
        }
        let before = model.haptic
        let program = model.editor.program

        // The premise, on a separate editor: the swap is applied, not refused. (It leaves no
        // undo entry, so probing on `model.editor` and undoing would undo the last insert.)
        let probe = EditorViewModel(program: program)
        if case .applied = probe.moveRows(fromOffsets: [0], toOffset: 2) {} else {
            Issue.record("the fixture's swap must be an applied move")
        }

        model.dropRows(fromOffsets: [0], toOffset: 2)

        #expect(model.editor.program == program)
        #expect(model.haptic == before)
    }

    @Test("edits other than an add or a drop pulse nothing, however they reach the program")
    func nonDropEditsPulseNothing() {
        let model = Self.windowWithRows()
        let before = model.haptic

        _ = model.editor.insert(.stitch)
        _ = model.editor.undo()
        _ = model.editor.redo()
        _ = model.editor.moveRows(fromOffsets: [0], toOffset: 2)
        _ = model.editor.deleteRows(atOffsets: [0])
        // The accessibility move actions and the replace sheet reach the editor through
        // `ScriptListView.perform`, i.e. `editor.apply`, never `dropRows`.
        _ = model.editor.apply(.move(from: BrickAddress(brickIndex: 0, script: ScriptAddress()), to: 1))
        _ = model.editor.apply(.replaceBrick(at: BrickAddress(brickIndex: 0, script: ScriptAddress()), with: .sewUp))
        model.nameDraft = "Renamed"
        model.commitName()

        #expect(model.haptic == before)
    }

    // MARK: Success

    @Test("a finished run whose export can be shared pulses success")
    func programFinishedWithEligibleExportPulsesSuccess() async {
        let model = await Self.runningWindow()
        let before = model.haptic

        model.runner.apply(Self.terminal(.programFinished, Self.stitches(3)))

        #expect(model.exporter.state != .idle)
        #expect(model.haptic?.kind == .success)
        #expect(Self.pulses(from: before, to: model.haptic) == 1)
    }

    @Test("a finished run whose export cannot be shared pulses nothing", arguments: [0, 1])
    func programFinishedWithIneligibleExportPulsesNothing(stitches: Int) async {
        let model = await Self.runningWindow()
        let before = model.haptic

        model.runner.apply(Self.terminal(.programFinished, Self.stitches(stitches)))

        #expect(model.runner.run.state == .finished(.programFinished), "the terminal must have landed")

        #expect(model.haptic == before)
    }

    @Test("a finished run under an invalid name pulses nothing")
    func programFinishedWithInvalidNamePulsesNothing() async {
        let model = await Self.runningWindow()
        model.exporter.name = ""
        let before = model.haptic

        model.runner.apply(Self.terminal(.programFinished, Self.stitches(3)))

        #expect(model.runner.run.state == .finished(.programFinished), "the terminal must have landed")

        #expect(model.haptic == before)
    }

    @Test(
        "a stop or the stitch limit is not a success, even with a good export",
        arguments: [RunCompletion.stoppedByUser, .stitchLimitReached]
    )
    func stopOrStitchLimitWithGoodExportPulsesNothing(completion: RunCompletion) async {
        let model = await Self.runningWindow()
        let before = model.haptic

        model.runner.apply(Self.terminal(completion, Self.stitches(3)))

        #expect(model.exporter.state != .idle, "the export is prepared all the same")
        #expect(model.haptic == before)
    }

    @Test("the terminal pulse comes after the export is prepared, never during")
    func noTerminalPulseWhileTheWriterRuns() async {
        let writer = ObservingDSTFileWriter()
        let model = await Self.runningWindow(writer: writer)
        let before = model.haptic
        var seenDuringWrite: HapticPulse??
        writer.onWrite = { seenDuringWrite = model.haptic }

        model.runner.apply(Self.terminal(.programFinished, Self.stitches(3)))

        #expect(seenDuringWrite == .some(before), "the pulse fired before the file was written")
        #expect(model.haptic?.kind == .success)
    }

    // MARK: Error

    @Test("an export failure at run end pulses error, not success")
    func exportFailureAtRunEndPulsesErrorNotSuccess() async {
        let model = await Self.runningWindow(writer: ThrowingDSTFileWriter())
        let before = model.haptic

        model.runner.apply(Self.terminal(.programFinished, Self.stitches(3)))

        #expect(model.haptic?.kind == .error)
        #expect(Self.pulses(from: before, to: model.haptic) == 1)
    }

    @Test(
        "a stop or the stitch limit whose export fails pulses error",
        arguments: [RunCompletion.stoppedByUser, .stitchLimitReached]
    )
    func stopOrStitchLimitWithFailingExportPulsesError(completion: RunCompletion) async {
        let model = await Self.runningWindow(writer: ThrowingDSTFileWriter())
        let before = model.haptic

        model.runner.apply(Self.terminal(completion, Self.stitches(3)))

        #expect(model.haptic?.kind == .error)
        #expect(Self.pulses(from: before, to: model.haptic) == 1)
    }

    @Test("a failed export, then a re-run that fails again, pulses error again")
    func failedExportThenRerunFailingPulsesErrorAgain() async {
        let model = await Self.runningWindow(writer: ThrowingDSTFileWriter())
        model.runner.apply(Self.terminal(.programFinished, Self.stitches(3)))
        let afterFirst = model.haptic
        #expect(afterFirst?.kind == .error, "the first run's failure must have pulsed")

        model.play()
        await Self.settle { model.runner.run.state == .running }
        model.runner.apply(Self.terminal(.programFinished, Self.stitches(3)))

        #expect(model.haptic?.kind == .error)
        #expect(Self.pulses(from: afterFirst, to: model.haptic) == 1)
    }

    @Test("each rename that fails to re-prepare is one error pulse")
    func failedExportThenFailingRenamePulsesOncePerAttempt() async {
        let model = await Self.runningWindow(writer: ThrowingDSTFileWriter())
        model.runner.apply(Self.terminal(.programFinished, Self.stitches(3)))
        let afterRun = model.haptic

        model.nameDraft = "Second"
        model.commitName()
        #expect(model.haptic?.kind == .error)
        #expect(Self.pulses(from: afterRun, to: model.haptic) == 1, "from an already-failed state")

        model.nameDraft = "Third"
        model.commitName()
        #expect(Self.pulses(from: afterRun, to: model.haptic) == 2)
    }

    @Test("a rename during a run pulses nothing until the run ends, then exports the new name")
    func renameDuringRunPulsesNothingUntilTermination() async {
        let writer = RecordingDSTFileWriter()
        let model = await Self.runningWindow(writer: writer)
        let before = model.haptic

        model.nameDraft = "Later"
        model.commitName()
        #expect(model.haptic == before)

        model.runner.apply(Self.terminal(.programFinished, Self.stitches(3)))
        #expect(model.haptic?.kind == .success)
        #expect(writer.written.last?.name.value.hasPrefix("Later") == true)
    }

    // MARK: Isolation and mapping

    @Test("two windows pulse independently")
    func twoWindowModelsPulseIndependently() {
        let first = Self.window()
        let second = Self.window()
        let untouched = second.haptic

        first.addFromPalette(.stitch)

        #expect(first.haptic?.kind == .selection)
        #expect(second.haptic == untouched)
    }

    @Test("each kind plays its system feedback")
    func hapticKindMapsToSensoryFeedback() {
        #expect(HapticKind.selection.feedback == .selection)
        #expect(HapticKind.success.feedback == .success)
        #expect(HapticKind.error.feedback == .error)
    }

    // MARK: Fixtures

    private static func window(writer: any DSTFileWriting = RecordingDSTFileWriter()) -> AppModel {
        let model = AppModel(
            library: .inMemory(),
            runner: RunViewModel(driver: InterpreterDriver(pacing: StalledRunPacing())),
            exporter: ExportViewModel(writer: writer)
        )
        _ = model.editor.apply(.renameProgram("Design"))
        return model
    }

    /// Three distinct rows, so dropping row 0 at offset 2 really changes the order.
    private static func windowWithRows() -> AppModel {
        let model = window()
        for kind in [BrickKind.stitch, .wait, .sewUp] {
            _ = model.editor.insert(kind)
        }
        return model
    }

    /// A window whose run has started and stays `.running`, so a test applies the terminal.
    private static func runningWindow(
        writer: any DSTFileWriting = RecordingDSTFileWriter()
    ) async -> AppModel {
        let model = window(writer: writer)
        model.play()
        await settle { model.runner.run.state == .running }
        // A terminal is ignored unless the run is `.running`, so without this a broken fixture
        // would let every "pulses nothing" test pass vacuously (swift-code-reviewer, whole PR).
        #expect(model.runner.run.state == .running, "the fixture's run never started")
        return model
    }

    private static func terminal(_ completion: RunCompletion, _ stream: EmbroideryStream) -> RunUpdate {
        RunUpdate(batch: RunBatch(), termination: RunTermination(reason: completion, exportModel: stream))
    }

    private static func stitches(_ count: Int) -> EmbroideryStream {
        var stream = EmbroideryStream()
        for x in 0 ..< count {
            stream.addStitch(at: StagePoint(x: Double(x), y: 0))
        }
        return stream
    }

    /// How many pulses happened between two observations, from the serial.
    private static func pulses(from before: HapticPulse?, to after: HapticPulse?) -> Int {
        (after?.serial ?? 0) - (before?.serial ?? 0)
    }

    private static func settle(until condition: () -> Bool) async {
        for _ in 0 ..< 100_000 where !condition() {
            await Task.yield()
        }
    }
}

/// Pacing that never delivers a frame until its task is cancelled, so a run stays `.running`
/// and the test decides how it ends.
private struct StalledRunPacing: RunPacing {
    func waitForNextFrame() async {
        try? await Task.sleep(for: .seconds(3600))
    }
}

/// A writer that lets a test look at the window while the file is being written.
@MainActor
private final class ObservingDSTFileWriter: DSTFileWriting {
    var onWrite: () -> Void = {}

    func write(_: DSTFile, named name: DSTFileName) throws -> URL {
        onWrite()
        return URL.temporaryDirectory.appending(path: "observed/\(name.value)")
    }

    func removeAll() {}
}
