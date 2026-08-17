@testable import catrobat_embroidery_ios
import EmbroideryEngine
import Samples
import StagePreview
import Testing

/// The app's selection state: what the picker shows, what selecting does, and
/// the one property US-306 will hang "start over" off.
///
/// Every test here is a plain value comparison. That is the point of the design
/// under test: "re-selecting re-publishes" is expressed as a *value* that
/// changes, not as an observation that fires, so proving it needs no
/// `withObservationTracking`, no SwiftUI and no simulator behaviour. The
/// alternative — relying on `@Observable`'s setter firing unconditionally — is
/// real but untestable, because the model's before and after states would be
/// identical.
@MainActor
struct AppModelTests {
    /// One row per `SampleLibrary.all` entry, in library order.
    ///
    /// **Deliberately a weak test, and the comment says so rather than letting
    /// the name imply more.** `samples` is a pass-through, so equality with the
    /// library is close to tautological. What it does pin is that the app layer
    /// adds no filter and no reordering of its own, and that no sample appears
    /// twice — the two ways a pass-through stops being one. The property earns
    /// its keep as M5's swap point (the real project list replaces it there),
    /// not as this test's subject.
    ///
    /// It also carries the *app-layer* form of the story's fifth test-first
    /// item. The engine-side claim — `SampleLibrary.all` is non-empty — is
    /// already green in `SampleLinkageTests.theSampleLibraryShipsAtLeastOneProgram`
    /// and is not duplicated here. The new claim is that the **picker's own
    /// source** is non-empty, which is what makes the list's empty state
    /// unreachable rather than merely unlikely.
    @Test func thePickerOffersEverySampleInLibraryOrderAndNoneTwice() {
        let model = AppModel()
        let ids = model.samples.map(\.id)

        #expect(!ids.isEmpty)
        #expect(ids == SampleLibrary.all.map(\.id))
        #expect(Set(ids).count == ids.count, "a sample appears twice: \(ids)")
    }

    /// Selecting publishes the sample, and the selection exposes its `Program`.
    ///
    /// The `program` reach-through is the story's second test-first item and is
    /// what a later consumer actually needs: US-306 constructs an `Interpreter`
    /// from it. Asserted through the selection rather than through the sample so
    /// that the seam US-306 uses is the seam under test.
    /// Parameterised over the whole library rather than its first entry: the
    /// `program` reach-through is precisely the seam US-306 consumes, and an
    /// implementation that resolved it through anything other than the passed
    /// sample would still pass a one-sample test. (In-loop review.)
    @Test(arguments: SampleLibrary.all)
    func selectingASamplePublishesItAndExposesItsProgram(_ sample: SampleProgram) throws {
        let model = AppModel()
        #expect(model.selection == nil, "nothing is selected before the first tap")

        model.select(sample)

        let selection = try #require(model.selection)
        #expect(selection.sample == sample)
        #expect(selection.program == sample.program)
    }

    /// `SampleSelection` must not become `Identifiable`.
    ///
    /// Its doc comment explains why — `.task(id: selection.id)` would compile
    /// and silently dedupe re-selection, defeating the generation — but a
    /// comment does not stop anyone adding the conformance in a later story to
    /// put the value in a `ForEach`. This does, and it fails at the moment the
    /// conformance is added rather than at the moment a run stops restarting.
    @Test func theSelectionIsDeliberatelyNotIdentifiable() throws {
        let sample = try #require(SampleLibrary.all.first)
        let selection: Any = SampleSelection(sample: sample, generation: 0)

        #expect(
            !(selection is any Identifiable),
            "SampleSelection became Identifiable — see its doc comment before removing this test"
        )
    }

    /// Re-selecting the currently selected sample re-publishes it.
    ///
    /// The whole reason `SampleSelection` carries a generation. Without it the
    /// two states are byte-identical and no expectation can tell them apart —
    /// and, worse, the consumers US-306 will write (`.onChange(of:)`,
    /// `.task(id:)`) compare `Equatable` values and would dedupe the second
    /// selection away. The notification would be sent and swallowed.
    ///
    /// All three expectations are needed: inequality alone would pass if
    /// `select` replaced the sample, sample-identity alone would pass for a
    /// no-op, and the generation is what pins *which* of the two changed.
    @Test func reselectingTheSameSamplePublishesAgainRatherThanBeingANoOp() throws {
        let model = AppModel()
        let sample = try #require(SampleLibrary.all.first)

        model.select(sample)
        let first = try #require(model.selection)
        model.select(sample)
        let second = try #require(model.selection)

        #expect(second != first, "re-selecting was a no-op")
        #expect(second.sample.id == first.sample.id)
        #expect(second.generation == first.generation + 1)
    }

    /// Selecting shows the stage — once, however often it is selected.
    ///
    /// `select` assigns the path rather than appending to it. Appending would
    /// stack a second stage on top of the first, so Back would return to a stage
    /// instead of to the list. Asserting the whole array (rather than
    /// `NavigationPath`, which exposes only `count`) is why the model stores
    /// `[StageDestination]`.
    @Test func selectingTwiceLeavesExactlyOneStageOnThePath() throws {
        let model = AppModel()
        let sample = try #require(SampleLibrary.all.first)
        #expect(model.path.isEmpty)

        model.select(sample)
        #expect(model.path == [.stage])

        model.select(sample)
        #expect(model.path == [.stage], "a second selection pushed a second stage")
    }

    /// Going back keeps the selection.
    ///
    /// **A guard against a coupling that does not exist yet, not a test of one
    /// that does** — stated plainly because the name reads stronger than the
    /// test is. `selection` is `private(set)` with a single writer and `path`
    /// has no observer, so no implementation reachable from here could fail
    /// this. What it buys is that adding a deselect-on-pop later turns red
    /// instead of quietly changing behaviour US-306 depends on: on regular the
    /// detail column always shows *something*, and a run must outlive a stop.
    ///
    /// The visible consequence is intended rather than tolerated: popping in
    /// compact and then widening to regular shows that design in the detail
    /// column again. What is *not* intended, and is handled in the view rather
    /// than here, is the picker row staying highlighted after Back in compact —
    /// see `SamplePickerView.showsSelection`.
    @Test func poppingTheStageKeepsTheSelection() throws {
        let model = AppModel()
        let sample = try #require(SampleLibrary.all.first)
        model.select(sample)

        // What the back button and the interactive swipe both do.
        model.path = []

        #expect(model.selection?.sample.id == sample.id)
    }

    /// Only the selected sample reports as selected.
    ///
    /// Drives the row highlight and the `.isSelected` VoiceOver trait. The
    /// `#require` on the count is deliberate: with a one-sample library the
    /// "only" half of this claim would be vacuously true, and the test would go
    /// on passing while saying nothing.
    @Test func onlyTheSelectedSampleReportsAsSelected() throws {
        try #require(SampleLibrary.all.count >= 2)
        let model = AppModel()
        let chosen = try #require(SampleLibrary.all.first)
        let other = try #require(SampleLibrary.all.last)

        #expect(!model.isSelected(chosen), "nothing is selected before the first tap")

        model.select(chosen)

        #expect(model.isSelected(chosen))
        #expect(!model.isSelected(other))
    }

    /// Choosing a design discards whatever the previous one left on the stage.
    ///
    /// **Driven from `select(_:)`, not from a view.** ADR-023 records that `RootView`
    /// swaps navigation containers on a horizontal size-class change, and the natural
    /// view-side spellings for this — `.onChange(of:initial:)`, `.task(id:)` — re-fire
    /// when the surviving container is rebuilt, which on an iPad window resize would
    /// wipe a design the user had just finished watching. `select(_:)` already has
    /// exactly one writer and says so; this belongs there.
    /// **Seeded by a real run, not by a direct `apply`.** An earlier version called
    /// `model.runner.apply(...)` to put a stitch on the stage, which stopped working the
    /// moment `PreviewRunState.apply` began refusing updates outside a running run — and,
    /// more importantly, it never exercised the thing that actually goes wrong here, which is
    /// a *live* run's buffered frames arriving after the reset (`swift-code-reviewer`).
    ///
    /// `AppModel` owns a `RunViewModel` with the real display pacing, so this waits for a few
    /// real frames rather than injecting anything: at 1/60 s a handful of frames is a few tens
    /// of milliseconds, and `squareCoil` stitches on its very first tick.
    @Test(.timeLimit(.minutes(1)))
    func selectingASampleDiscardsThePreviousRun() async throws {
        let model = AppModel()
        let chosen = try #require(SampleLibrary.all.first)

        model.runner.play(chosen.program)
        for _ in 0 ..< 100_000 where model.runner.run.display.isEmpty {
            await Task.yield()
        }
        try #require(!model.runner.run.display.isEmpty, "the run must have something to discard")

        model.select(chosen)

        #expect(model.runner.run.state == .idle)
        #expect(model.runner.run.display.isEmpty)

        // And it stays discarded once the orphaned consumer has had its turns.
        for _ in 0 ..< 5000 {
            await Task.yield()
        }
        #expect(model.runner.run.state == .idle)
        #expect(model.runner.run.display.isEmpty)
        #expect(model.runner.run.exportModel == nil)
    }
}
