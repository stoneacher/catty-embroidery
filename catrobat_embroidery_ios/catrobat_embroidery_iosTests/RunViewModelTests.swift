@testable import catrobat_embroidery_ios
import EmbroideryEngine
import Observation
import Samples
import StagePreview
import Testing

/// The app layer's half of the run: that a play drives the model to a finished state
/// with an export model, that a stop keeps both, and that a batch is **one**
/// observable mutation.
///
/// The state machine itself is `PreviewRunStateTests`, in the package, on the fast
/// gate. What can only be tested here is the wiring: two tasks, one observed
/// property, and the ownership rules ADR-023 makes load-bearing.
@MainActor
@Suite("Run view model")
struct RunViewModelTests {
    private static func immediateModel() -> RunViewModel {
        RunViewModel(driver: InterpreterDriver(pacing: ImmediateRunPacing()))
    }

    /// Waits until `condition` holds, letting the consumer task run in between.
    ///
    /// A bounded spin rather than a sleep: the consumer is a main-actor task, so
    /// yielding is what lets it make progress, and there is no interval to guess.
    /// Bounded so a broken implementation fails instead of hanging the suite.
    private static func settle(
        until condition: () -> Bool, turns: Int = 100_000
    ) async {
        for _ in 0 ..< turns where !condition() {
            await Task.yield()
        }
    }

    @Test("a fresh view model is idle with nothing to show")
    func aFreshViewModelIsIdle() {
        let model = Self.immediateModel()

        #expect(model.run.state == .idle)
        #expect(model.run.display.isEmpty)
        #expect(model.run.exportModel == nil)
    }

    /// Playing drives the model to `.finished(.programFinished)`, with the sample's
    /// full stitch count and an export model — the whole thread from a tap to
    /// something US-308 can write out.
    @Test("playing a sample runs it to a finished state with an export model",
          .timeLimit(.minutes(1)))
    func playingASampleRunsItToAFinishedState() async {
        let model = Self.immediateModel()
        let sample = SampleLibrary[.squareCoil]

        model.play(sample.program)
        await Self.settle(until: { model.run.state == .finished(.programFinished) })

        #expect(model.run.state == .finished(.programFinished))
        #expect(model.run.display.count == 2976)
        #expect(model.run.exportModel != nil)
        #expect((model.run.exportModel?.count ?? 0) > 0)
    }

    /// Story item 2 at the app layer.
    ///
    /// **`revision` is what makes this discriminating, and a `withObservationTracking`
    /// counter is not.** `onChange` is one-shot: a view model that appended stitch by
    /// stitch would fire it on the first stitch and the remaining thousands would go
    /// unobserved, so the naive counter reports 1 either way and is green against the
    /// very implementation this criterion forbids. Counting mutations of the single
    /// observed property is the honest form — and the two numbers being compared differ
    /// by more than an order of magnitude, so the failure is loud.
    @Test("the view model mutates its observed state once per batch, not once per stitch",
          .timeLimit(.minutes(1)))
    func theViewModelMutatesOncePerBatch() async {
        let model = Self.immediateModel()

        model.play(SampleLibrary[.octagonRosette].program)
        await Self.settle(until: { model.run.state == .finished(.programFinished) })

        #expect(model.run.display.count == 3194)
        // 139 frames against 3194 stitches: the claim is only meaningful because these
        // are far apart.
        #expect(model.run.revision < 200)
        #expect(model.run.revision * 10 < model.run.display.count)
    }

    /// One delivered update produces exactly one observable notification.
    ///
    /// A fresh one-shot registration per update, created by the test between updates —
    /// so the observation is deterministic and there is no re-arming race. This proves
    /// the notification happens and is per-update; the *count* of mutations is the
    /// `revision` assertion above.
    @Test("each applied batch notifies observers of the run")
    func eachAppliedBatchNotifiesObservers() {
        let model = Self.immediateModel()
        let counter = NotificationCounter()

        for index in 0 ..< 3 {
            withObservationTracking {
                _ = model.run
            } onChange: {
                // `onChange` is `@Sendable`, so the count cannot be a captured `var`.
                // `assumeIsolated` is sound rather than convenient: the only writer is
                // `apply(_:)`, which is `@MainActor`, and `onChange` fires
                // synchronously inside that mutation.
                MainActor.assumeIsolated { counter.count += 1 }
            }
            model.apply(RunUpdate(batch: RunBatch(
                stitches: (0 ..< 100).map { PreviewStitch(
                    position: StagePoint(x: Double(index * 100 + $0), y: 0), color: .black
                ) }
            )))
        }

        #expect(counter.count == 3)
        #expect(model.run.revision == 3)
        #expect(model.run.display.count == 300)
    }

    /// The story's central criterion at the app layer: after a stop, the design is
    /// still there **and** so is the export model.
    ///
    /// Gated pacing, because under immediate pacing the producer races to completion and
    /// the stop would land after a natural finish. The gate is duplicated from the
    /// package's test target rather than shared: SwiftPM forbids a test target depending
    /// on another test target, and an app test target cannot import one at all.
    @Test("stopping mid-run keeps the design and still yields an export model",
          .timeLimit(.minutes(1)))
    func stoppingMidRunKeepsTheDesignAndTheExportModel() async {
        let pacing = GatedPacing()
        let model = RunViewModel(driver: InterpreterDriver(pacing: pacing))

        model.play(SampleLibrary[.squareCoil].program)
        // Three frames of real stitching before the stop.
        for _ in 0 ..< 3 {
            await pacing.grant()
        }
        await Self.settle(until: { !model.run.display.isEmpty })

        model.stop()
        await pacing.grant()
        await Self.settle(until: { model.run.state == .finished(.stoppedByUser) })

        #expect(model.run.state == .finished(.stoppedByUser))
        #expect(!model.run.display.isEmpty)
        #expect(model.run.exportModel != nil)
        // Fewer stitches than a complete run: a "stop" that quietly ran to completion
        // would satisfy every assertion above.
        #expect(model.run.display.count < 2976)
    }

    @Test("resetting returns to idle and clears the design", .timeLimit(.minutes(1)))
    func resettingReturnsToIdleAndClearsTheDesign() async throws {
        let model = Self.immediateModel()

        model.play(SampleLibrary[.squareCoil].program)
        await Self.settle(until: { model.run.state == .finished(.programFinished) })
        // Without this, the test passes against a `play` that does nothing — which is
        // exactly what it did in the red phase, where it was the one assertion in this
        // suite that could not fail.
        try #require(!model.run.display.isEmpty)

        model.reset()

        #expect(model.run.state == .idle)
        #expect(model.run.display.isEmpty)
        #expect(model.run.exportModel == nil)
    }

    /// Playing twice must not draw the second run on top of the first.
    @Test("playing again replaces the previous run rather than adding to it",
          .timeLimit(.minutes(1)))
    func playingAgainReplacesThePreviousRun() async {
        let model = Self.immediateModel()
        let program = SampleLibrary[.squareCoil].program

        model.play(program)
        await Self.settle(until: { model.run.state == .finished(.programFinished) })
        model.play(program)
        await Self.settle(until: { model.run.state == .finished(.programFinished) })

        #expect(model.run.display.count == 2976)
    }
}

/// A counter an `@Sendable` `onChange` closure can write to.
@MainActor
final class NotificationCounter {
    var count = 0
}

/// Pacing the test drives frame by frame. See
/// `RunViewModelTests.stoppingMidRunKeepsTheDesignAndTheExportModel` for why this is
/// duplicated from the package's test target rather than shared.
actor GatedPacing: RunPacing {
    private var credits = 0
    private var waiting: CheckedContinuation<Void, Never>?

    func grant() {
        if let continuation = waiting {
            waiting = nil
            continuation.resume()
        } else {
            credits += 1
        }
    }

    nonisolated func waitForNextFrame() async {
        await gate()
    }

    private func gate() async {
        if credits > 0 {
            credits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiting = continuation
        }
    }
}
