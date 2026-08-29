@testable import catrobat_embroidery_ios
import EmbroideryEngine
import Foundation
import Samples
import StagePreview
import Testing

/// The app's end of the export thread: who tells the exporter that a run has finished, and
/// what a new selection does to a file already on disk.
///
/// **The termination hook is a closure on `RunViewModel`, not an `.onChange` in a view**, and
/// that is the same decision `AppModel.select(_:)` already records for the run reset and the
/// fit: the view-side spellings (`.onChange(of:initial:)`, `.task(id:)`) re-fire when
/// `RootView` rebuilds a navigation container after a horizontal size-class change (ADR-023),
/// so on an iPad window resize they would re-prepare — writing a file again for a design
/// nobody touched. The run is the thing that knows it has terminated, so it is the thing that
/// says so.
@MainActor
@Suite("Export wiring")
struct ExportWiringTests {
    /// Waits until `condition` holds, letting the consumer task run in between — the bounded
    /// spin `RunViewModelTests` uses, for the reason it gives there: the consumer is a
    /// main-actor task, so yielding is what lets it progress, and there is no interval to
    /// guess.
    private static func settle(until condition: () -> Bool, turns: Int = 100_000) async {
        for _ in 0 ..< turns where !condition() {
            await Task.yield()
        }
    }

    private static func immediateModel(
        writer: RecordingDSTFileWriter
    ) -> AppModel {
        AppModel(
            runner: RunViewModel(driver: InterpreterDriver(pacing: ImmediateRunPacing())),
            exporter: ExportViewModel(writer: writer)
        )
    }

    // MARK: - The hook

    /// The run reports its own termination exactly once, carrying the terminal's export
    /// model — not *some* stream, the one the terminal carried.
    @Test("a terminating run reports its export model exactly once", .timeLimit(.minutes(1)))
    func aTerminatingRunReportsItsExportModel() async {
        let runner = RunViewModel(driver: InterpreterDriver(pacing: ImmediateRunPacing()))
        var reported: [EmbroideryStream] = []
        runner.onRunTerminated = { reported.append($0) }

        let sample = SampleLibrary[.squareCoil]
        runner.play(sample.program)
        await Self.settle(until: { runner.run.state == .finished(.programFinished) })

        #expect(reported.count == 1, "once, not once per frame")
        #expect(reported.first == runner.run.exportModel)
    }

    /// **The guard that an in-loop review deleted without breaking anything.**
    /// `RunViewModel.apply` reads `isRunning` *before* folding, so an update carrying a
    /// terminal that `PreviewRunState` rejects is not announced. Through the app's own wiring
    /// the producer never yields after a terminal, so the guard is defence in depth — but
    /// deleting it was invisible to all 114 tests, and a rule with no test is a rule that
    /// will be "simplified" away. Driving `apply` directly is the one way to reach it.
    @Test("a terminal update applied to an already-finished run announces nothing")
    func aSecondTerminalIsNotAnnounced() async {
        let runner = RunViewModel(driver: InterpreterDriver(pacing: ImmediateRunPacing()))
        var reported = 0
        runner.onRunTerminated = { _ in reported += 1 }

        runner.play(SampleLibrary[.squareCoil].program)
        await Self.settle(until: { runner.run.state == .finished(.programFinished) })
        #expect(reported == 1)

        // The run is `.finished`, so `PreviewRunState.apply` drops this — and the callback
        // must not fire for a termination the state never accepted.
        // Any non-empty stream: the assertion is about how many times the callback fires,
        // not about what it carries. (`assembledStream(of:)` is a package *test* helper, and
        // SwiftPM forbids reaching one test target from another.)
        runner.apply(RunUpdate(
            batch: RunBatch(),
            termination: RunTermination(
                reason: .stoppedByUser, exportModel: Self.threeStitchStream()
            )
        ))

        #expect(reported == 1, "a rejected terminal was announced anyway")
    }

    // MARK: - Selection

    /// **The default name comes from `SampleID.resourceName`, not from `displayName`.**
    /// `displayName` is a `LocalizedStringResource` from the `Samples` bundle and "Octagon
    /// Rosette" is *exactly* 15 characters in English — so any locale whose translation is one
    /// character longer, or not Latin at all, would open the screen already in a validation
    /// error the user did not cause. `resourceName` is ASCII, locale-independent, and already
    /// the canonical file stem.
    @Test("selecting a design seeds a name that is valid in every locale")
    func selectingSeedsAValidName() throws {
        let writer = RecordingDSTFileWriter()
        let model = Self.immediateModel(writer: writer)

        model.select(SampleLibrary[.octagonRosette])
        #expect(model.exporter.name == "OctagonRosette")
        #expect(throws: Never.self) { try model.exporter.validatedName.get() }

        model.select(SampleLibrary[.squareCoil])
        #expect(model.exporter.name == "SquareCoil")
    }

    /// Every bundled sample's seeded name is valid — the guard that makes the claim above a
    /// property of the library rather than of two hand-checked strings, so a third sample
    /// added in M5 cannot ship a name the field rejects on first sight.
    @Test("every bundled sample seeds a valid name", arguments: SampleID.allCases)
    func everySampleSeedsAValidName(id: SampleID) throws {
        let writer = RecordingDSTFileWriter()
        let model = Self.immediateModel(writer: writer)

        model.select(SampleLibrary[id])

        let name = try model.exporter.validatedName.get()
        #expect(name.value == id.resourceName)
    }

    /// A new selection throws the previous design's file away. Leaving it would offer a share
    /// button that sends the *last* design — the same class of staleness ADR-023 exists to
    /// prevent, one layer up.
    @Test("selecting a new design discards the file prepared for the old one")
    func selectingDiscardsThePreparedFile() {
        let writer = RecordingDSTFileWriter()
        let model = Self.immediateModel(writer: writer)
        model.exporter.name = "Rose"
        model.exporter.prepare(exportModel: Self.threeStitchStream())
        #expect(model.exporter.state != .idle)

        model.select(SampleLibrary[.squareCoil])

        #expect(model.exporter.state == .idle)
    }

    // MARK: - End to end

    /// The whole thread, through the objects the app actually wires together: pick a design,
    /// run it, and a file is on disk under the design's own name with that name in its bytes.
    ///
    /// This is the test that would fail if the hook were never connected — every other test
    /// here exercises one half.
    @Test("playing a selected design leaves a named file ready to share",
          .timeLimit(.minutes(1)))
    func playingLeavesAFileReady() async throws {
        let writer = RecordingDSTFileWriter()
        let model = Self.immediateModel(writer: writer)

        model.select(SampleLibrary[.squareCoil])
        model.runner.play(SampleLibrary[.squareCoil].program)
        await Self.settle(until: { model.runner.run.state == .finished(.programFinished) })

        let written = try #require(writer.written.last)
        #expect(written.name.value == "SquareCoil.dst")
        #expect(model.exporter.state == .ready(written.url))

        // The gate agrees, which is what the share control reads.
        #expect(model.runner.run.isExportable)
    }

    /// Committing an edited name re-prepares from the run's export model, because the name is
    /// in the `LA` **bytes** and not only in the file name — so a rename genuinely invalidates
    /// the previous file rather than merely relabelling it.
    @Test("committing a new name rewrites the file", .timeLimit(.minutes(1)))
    func committingANameRewritesTheFile() async {
        let writer = RecordingDSTFileWriter()
        let model = Self.immediateModel(writer: writer)

        model.select(SampleLibrary[.squareCoil])
        model.runner.play(SampleLibrary[.squareCoil].program)
        await Self.settle(until: { model.runner.run.state == .finished(.programFinished) })
        let afterRun = writer.written.count

        model.exporter.name = "Renamed"
        model.commitName()

        #expect(writer.written.count == afterRun + 1)
        #expect(writer.written.last?.name.value == "Renamed.dst")
    }

    /// Committing a name before anything has run writes nothing: there is no design to
    /// serialise, and a file named after a design that does not exist would be a lie the share
    /// control would then happily offer.
    @Test("committing a name before a run writes nothing")
    func committingBeforeARunWritesNothing() {
        let writer = RecordingDSTFileWriter()
        let model = Self.immediateModel(writer: writer)

        model.select(SampleLibrary[.squareCoil])
        model.exporter.name = "Renamed"
        model.commitName()

        #expect(writer.written.isEmpty)
        #expect(model.exporter.state == .idle)
    }

    private static func threeStitchStream() -> EmbroideryStream {
        var stream = EmbroideryStream()
        for x in 0 ..< 3 {
            stream.addStitch(at: StagePoint(x: Double(x), y: 0))
        }
        return stream
    }
}
