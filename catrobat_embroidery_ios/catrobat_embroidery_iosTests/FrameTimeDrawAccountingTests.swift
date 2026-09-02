@testable import catrobat_embroidery_ios
import Testing

/// Draw accounting: which frames of a capture the renderer actually drew in.
///
/// **Separate from `FrameTimeRecorderTests` because it is a separate claim.** That suite is
/// about the interval arithmetic — first-frame handling, deltas, interruption, the buffer.
/// This one is about attribution: a `CADisplayLink` callback fires on every display refresh
/// whether or not SwiftUI drew anything, so knowing *when* the canvas drew is what separates
/// a measurement of the renderer from a measurement of the display (Codex rounds 1 and 2).
/// The split also puts the recorder suite back under SwiftLint's 400-line file limit.
///
/// `StageDrawCounter` is driven directly here: the production increment lives inside a
/// `Canvas` drawing closure that no unit test can run, so what is testable — and what would
/// actually go wrong — is the bookkeeping around it.
///
/// `.serialized` because `StageDrawCounter` is process-wide mutable state and this is the
/// only suite that writes it. Each capture takes its own baseline in `start()`, so the
/// counter's absolute value is already irrelevant — and these bodies are synchronous on the
/// main actor, so they cannot interleave today. The trait removes the need to re-derive that
/// argument the next time one of them gains an `await`.
@MainActor
@Suite(.serialized)
struct FrameTimeDrawAccountingTests {

    /// **Codex round 1, finding 1**: a capture reports how many times the canvas actually
    /// drew, because a display-link callback is not evidence that anything was rendered.
    ///
    /// Driven here through `StageDrawCounter` directly — the counter is written inside a
    /// `Canvas` closure that no unit test can run — so what is pinned is the accounting: a
    /// capture attributes exactly the draws that happened between its own start and stop, and
    /// nothing from before it.
    @Test("a capture counts only the draws inside its own window")
    func aCaptureCountsOnlyTheDrawsInsideItsOwnWindow() {
        let recorder = FrameTimeRecorder()
        StageDrawCounter.record()
        StageDrawCounter.record()

        recorder.start()
        StageDrawCounter.record()
        StageDrawCounter.record()
        StageDrawCounter.record()
        recorder.record(timestamp: 1.000)
        recorder.record(timestamp: 1.016)
        _ = recorder.stop()

        #expect(recorder.drawCount == 3, "the two draws before start() are not this capture's")
    }

    /// A static stage draws nothing, which is exactly the case the draw count exists to make
    /// visible: perfect frame times, no rendering.
    @Test("a capture over a static stage reports no draws")
    func aCaptureOverAStaticStageReportsNoDraws() throws {
        let recorder = FrameTimeRecorder()
        recorder.start()
        for index in 0 ... 700 {
            recorder.record(timestamp: Double(index) * 0.016)
        }
        let stats = try #require(recorder.stop())

        // The numbers look perfect...
        #expect(stats.meetsSixtyFps)
        #expect(stats.isLongEnoughToQuote)
        // ...and the capture still measured nothing about the renderer.
        #expect(recorder.drawCount == 0)
    }

    /// A capture over a static stage publishes **no** drawn statistics, which is what the
    /// verdict reads.
    ///
    /// **This replaces a test that was vacuous** (Codex round 2, finding 1): the earlier
    /// version asserted `stats.frameCount / 10 == 0` and `drawCount == 0` — the *inputs* the
    /// guard would have been handed — and never invoked the guard, which lived in a `private`
    /// method on a `View` and could not be called. It passed while the rule was still wrong.
    /// The rule is now `FrameCaptureVerdict`, tested directly in its own suite; what belongs
    /// here is the recorder's half, which is that no draws means no drawn statistics.
    @Test("a static-stage capture publishes no drawn statistics")
    func aStaticStageCapturePublishesNoDrawnStatistics() throws {
        let recorder = FrameTimeRecorder()
        recorder.start()
        for index in 0 ... 5 {
            recorder.record(timestamp: Double(index) * 0.016)
        }
        let stats = try #require(recorder.stop())

        #expect(stats.frameCount == 5)
        #expect(recorder.drawnStatistics == nil, "nothing was drawn, so there is nothing to quote")
        // The frames themselves look perfect, which is precisely the trap.
        #expect(stats.meetsSixtyFps)
        #expect(FrameCaptureVerdict.of(
            all: stats,
            drawn: recorder.drawnStatistics,
            wasInterrupted: recorder.wasInterrupted
        ) == .noDraws)
    }

    /// **Only the intervals in which the canvas drew land in `drawnStatistics`.**
    ///
    /// The tag is applied as each interval is recorded, because a draw *count* over a whole
    /// capture cannot be apportioned to intervals afterwards. Here two of four intervals
    /// contain a draw, and they are the slow ones — so the capture as a whole looks healthy
    /// and the drawn frames do not, which is the distinction the whole exercise is about.
    @Test("only the intervals containing a draw are quoted")
    func onlyTheIntervalsContainingADrawAreQuoted() throws {
        let recorder = FrameTimeRecorder()
        recorder.start()
        recorder.record(timestamp: 0.000)             // seeds the baseline, records nothing
        recorder.record(timestamp: 0.016)             // idle 16 ms
        StageDrawCounter.record()
        recorder.record(timestamp: 0.066)             // drew, 50 ms
        recorder.record(timestamp: 0.082)             // idle 16 ms
        StageDrawCounter.record()
        recorder.record(timestamp: 0.132)             // drew, 50 ms

        let all = try #require(recorder.stop())
        let drawn = try #require(recorder.drawnStatistics)

        #expect(all.frameCount == 4)
        #expect(drawn.frameCount == 2)
        #expect(abs(drawn.median - 50) < 0.001, "the drawn frames are the 50 ms ones")
        #expect(!drawn.meetsSixtyFps)
        // And the whole-capture median is one of the idle frames, which is the flattery.
        #expect(abs(all.median - 16) < 0.001)
    }

    /// **The drawn subset's worst-frame position is in *capture* time, not in drawn time.**
    ///
    /// Found on the running app: a spike 22 s into a 37 s capture was labelled `@4.5s`,
    /// because summing only the drawn intervals measures a position in the sub-series' own
    /// time. Locating the spike within the run is the entire purpose of that number
    /// (hand-off capture 5), so a position that reads like wall-clock and is not one is worse
    /// than no position at all. Here two drawn frames sit either side of a long idle stretch.
    @Test("a drawn frame's position is measured from the start of the capture")
    func aDrawnFramesPositionIsMeasuredFromTheStartOfTheCapture() throws {
        let recorder = FrameTimeRecorder()
        recorder.start()
        recorder.record(timestamp: 0.000)          // baseline
        StageDrawCounter.record()
        recorder.record(timestamp: 0.020)          // drew, 20 ms, starting at 0 ms
        // A second of idle frames, none of them drawn.
        for index in 1 ... 60 {
            recorder.record(timestamp: 0.020 + Double(index) * 0.016)
        }
        StageDrawCounter.record()
        recorder.record(timestamp: 1.100)          // drew, the worst frame
        // `drawnStatistics` is published by `stop()`, like `statistics` — reading it before
        // the capture ends gives `nil`, which is how this test first failed.
        _ = recorder.stop()

        let drawn = try #require(recorder.drawnStatistics)
        #expect(drawn.frameCount == 2)
        // The worst drawn frame starts after the idle stretch — ~980 ms into the capture, not
        // the ~20 ms that summing only the drawn intervals would give.
        #expect(drawn.worstAtMilliseconds > 900, "\(drawn.worstAtMilliseconds) ms is drawn-only time, not capture time")
        let all = try #require(recorder.statistics)
        #expect(drawn.worstAtMilliseconds < all.totalMilliseconds)
    }
}
