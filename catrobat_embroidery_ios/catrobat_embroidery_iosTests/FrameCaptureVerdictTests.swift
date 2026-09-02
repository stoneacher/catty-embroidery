@testable import catrobat_embroidery_ios
import Testing

/// What a capture is allowed to conclude — the rule that decides whether a set of frame times
/// may be quoted as evidence about the renderer at all.
///
/// **This suite exists because the first version of this logic was untestable and the test
/// written for it was vacuous.** The rule lived in a `private` method on `FrameTimeReadout`,
/// so the test that claimed to pin it asserted the *inputs* it would have received —
/// `frameCount / 10 == 0`, `drawCount == 0` — and never invoked the rule. It passed while the
/// rule was still wrong (Codex round 2, finding 1). A guard that cannot be called cannot be
/// tested, and a test that recomputes the guard's inputs is not a test of the guard.
@Suite("US-309 frame-capture verdict")
struct FrameCaptureVerdictTests {
    private func stats(_ durations: [Double]) -> FrameTimeStatistics? {
        FrameTimeStatistics(millisecondsPerFrame: durations)
    }

    /// **The case the whole draw-counting exercise exists for.** A settled 50 000-stitch stage
    /// invalidates nothing, so the display link keeps firing and every interval is a perfect
    /// 16.7 ms — while the renderer is asked for nothing. Measured on the running app as
    /// `n=988 draws=0 … NO DRAWS`.
    @Test("a capture in which nothing was drawn is not a pass, however perfect its frames")
    func aCaptureInWhichNothingWasDrawnIsNotAPass() {
        let perfect = stats(Array(repeating: 16.0, count: 700))
        let verdict = FrameCaptureVerdict.of(all: perfect, drawn: nil, totalDraws: 0, wasInterrupted: false)

        #expect(verdict == .noDraws)
        #expect(!verdict.isAboutTheRenderer)
        // The frames themselves would have sailed through the bar.
        #expect(perfect?.meetsSixtyFps == true)
    }

    /// **The short-capture case, which the ratio spelling could not catch.** Five frames and no
    /// draws: `draws < frameCount / 10` was `0 < 0`, false, so the capture was scored `PASS`.
    /// The rule no longer has a threshold to truncate.
    @Test("a five-frame capture with no draws is still not a pass")
    func aFiveFrameCaptureWithNoDrawsIsStillNotAPass() {
        let verdict = FrameCaptureVerdict.of(
            all: stats(Array(repeating: 16.0, count: 5)),
            drawn: nil,
            totalDraws: 0,
            wasInterrupted: false
        )
        #expect(verdict == .noDraws)
    }

    /// **The bar is read off the drawn frames, not off every frame** — the correction that
    /// makes the measurement mean anything. Here the whole capture looks flawless because 90 %
    /// of its frames are idle, while every frame the renderer actually drew in blew the budget.
    /// A p99 over all frames is a p99 of mostly-nothing.
    @Test("the bar is decided by the drawn frames, not by the idle ones")
    func theBarIsDecidedByTheDrawnFramesNotByTheIdleOnes() {
        let drawnFrames = Array(repeating: 50.0, count: 150)
        let idleFrames = Array(repeating: 16.0, count: 630)
        let all = stats(idleFrames + drawnFrames)
        let drawn = stats(drawnFrames)

        // The whole capture's p99 is inside the budget only because the idle frames dominate.
        #expect(all?.median == 16.0)
        let verdict = FrameCaptureVerdict.of(all: all, drawn: drawn, totalDraws: 150, wasInterrupted: false)
        #expect(verdict == .measured(passed: false, quotableWindow: true))
        #expect(verdict.isAboutTheRenderer)
    }

    /// A capture whose drawn frames are inside the budget passes, and says so.
    @Test("drawn frames inside the budget pass")
    func drawnFramesInsideTheBudgetPass() {
        let verdict = FrameCaptureVerdict.of(
            all: stats(Array(repeating: 16.0, count: 700)),
            drawn: stats(Array(repeating: 16.0, count: 200)),
            totalDraws: 200,
            wasInterrupted: false
        )
        #expect(verdict == .measured(passed: true, quotableWindow: true))
    }

    /// **A tail over one observation is not a tail** (Codex round 3). With a single drawn
    /// interval the median, p95 and p99 are the same sample, so `PASS` would be a claim about
    /// the renderer made from one frame — and `NO DRAWS` would be false, since it did draw.
    @Test("one drawn frame is neither a pass nor no-draws")
    func oneDrawnFrameIsNeitherAPassNorNoDraws() {
        let verdict = FrameCaptureVerdict.of(
            all: stats(Array(repeating: 16.0, count: 625)),
            drawn: stats([16.0]),
            totalDraws: 1,
            wasInterrupted: false
        )
        #expect(verdict == .tooFewDraws(count: 1))
        #expect(!verdict.isAboutTheRenderer, "one sample cannot be evidence about the renderer")
    }

    /// The threshold is where p99 stops being the maximum, and it is checked at its own edge.
    ///
    /// **Against the literal 100, not against `minimumDrawnFrames`** (Codex round 4). The
    /// first version built its inputs from `minimumDrawnFrames - 1` and `minimumDrawnFrames`,
    /// so changing the production constant to 2 left it green — a restatement, and the third
    /// on this branch. The literal is justified rather than arbitrary: nearest-rank p99 is
    /// `ceil(0.99n)`, which equals `n` (the maximum) for every n below 100 and first becomes
    /// `n - 1` at exactly 100, so 100 is where p99 stops being a second name for `worst`.
    @Test("the drawn-frame threshold is exact at its boundary")
    func theDrawnFrameThresholdIsExactAtItsBoundary() {
        #expect(FrameCaptureVerdict.minimumDrawnFrames == 100, "the literals below assume it")
        let all = stats(Array(repeating: 16.0, count: 700))
        let justUnder = 99
        #expect(
            FrameCaptureVerdict.of(
                all: all,
                drawn: stats(Array(repeating: 16.0, count: justUnder)),
                totalDraws: justUnder,
                wasInterrupted: false
            ) == .tooFewDraws(count: justUnder)
        )
        #expect(
            FrameCaptureVerdict.of(
                all: all,
                drawn: stats(Array(repeating: 16.0, count: 100)),
                totalDraws: 100,
                wasInterrupted: false
            ) == .measured(passed: true, quotableWindow: true)
        )
    }

    /// **The window is the capture's, the bar is the drawn frames'** — two different questions,
    /// and conflating them would let a two-second capture of busy frames be quoted as AC3's
    /// ten-second window.
    @Test("the window is the whole capture's even when the bar is the drawn frames'")
    func theWindowIsTheWholeCapturesEvenWhenTheBarIsTheDrawnFrames() {
        let verdict = FrameCaptureVerdict.of(
            all: stats(Array(repeating: 16.0, count: 100)), // 1.6 s — short
            drawn: stats(Array(repeating: 16.0, count: 100)),
            totalDraws: 100,
            wasInterrupted: false
        )
        #expect(verdict == .measured(passed: true, quotableWindow: false))
    }

    /// Interruption outranks everything, including a set of frames that would have passed:
    /// the window is no longer the one that was timed.
    @Test("interruption outranks a passing set of frames")
    func interruptionOutranksAPassingSetOfFrames() {
        let verdict = FrameCaptureVerdict.of(
            all: stats(Array(repeating: 16.0, count: 700)),
            drawn: stats(Array(repeating: 16.0, count: 700)),
            totalDraws: 700,
            wasInterrupted: true
        )
        #expect(verdict == .interrupted)
        #expect(!verdict.isAboutTheRenderer)
    }

    /// A capture that caught no frames at all is distinguished from one that caught frames but
    /// drew nothing — different problems with different fixes.
    @Test("no frames is distinguished from no draws")
    func noFramesIsDistinguishedFromNoDraws() {
        #expect(FrameCaptureVerdict.of(all: nil, drawn: nil, totalDraws: 0, wasInterrupted: false) == .nothingCaptured)
    }

    /// Every case reads differently, so a screenshot of the row is unambiguous about what was
    /// measured — which is the point of the labels going into the thesis.
    @Test("every verdict reads differently")
    func everyVerdictReadsDifferently() {
        let labels = [
            FrameCaptureVerdict.interrupted,
            .nothingCaptured,
            .noDraws,
            .drawsNotMeasured(count: 2),
            .tooFewDraws(count: 3),
            .measured(passed: true, quotableWindow: true),
            .measured(passed: false, quotableWindow: true),
            .measured(passed: true, quotableWindow: false)
        ].map(\.label)

        #expect(Set(labels).count == labels.count)
        #expect(labels.allSatisfy { !$0.isEmpty })
    }

    /// **Insufficient evidence must withhold a PASS, not mask a FAIL** (Codex round 4).
    ///
    /// Fifty drawn frames every one of which took 50 ms violate the 33.3 ms dropped-frame
    /// limit outright — that is not an inconclusive result, it is the one result the criterion
    /// exists to surface. The earlier ordering checked the sample count first and reported
    /// `tooFewDraws`, hiding a conclusive failure behind a caveat about statistics.
    @Test("a conclusive failure is reported even from few drawn frames")
    func aConclusiveFailureIsReportedEvenFromFewDrawnFrames() {
        let verdict = FrameCaptureVerdict.of(
            all: stats(Array(repeating: 16.0, count: 700)),
            drawn: stats(Array(repeating: 50.0, count: 50)),
            totalDraws: 50,
            wasInterrupted: false
        )
        #expect(verdict == .measured(passed: false, quotableWindow: true))
        #expect(verdict.isAboutTheRenderer, "50 frames over the limit is evidence, not noise")
    }

    /// The same few frames *passing* stay inconclusive: the asymmetry is the point.
    @Test("few drawn frames cannot produce a pass")
    func fewDrawnFramesCannotProduceAPass() {
        let verdict = FrameCaptureVerdict.of(
            all: stats(Array(repeating: 16.0, count: 700)),
            drawn: stats(Array(repeating: 16.0, count: 50)),
            totalDraws: 50,
            wasInterrupted: false
        )
        #expect(verdict == .tooFewDraws(count: 50))
    }

    /// **A draw with no measurable interval is not "no draws"** (Codex round 4). A render
    /// finishing between `start()` and the first callback, or after the last one, has no
    /// interval to belong to — but saying nothing was drawn would be false, and attributing it
    /// forward would put a 50 ms cost on a 16 ms interval.
    @Test("draws outside any timed interval are reported as unmeasured, not absent")
    func drawsOutsideAnyTimedIntervalAreReportedAsUnmeasuredNotAbsent() {
        let verdict = FrameCaptureVerdict.of(
            all: stats(Array(repeating: 16.0, count: 700)),
            drawn: nil,
            totalDraws: 2,
            wasInterrupted: false
        )
        #expect(verdict == .drawsNotMeasured(count: 2))
        #expect(!verdict.isAboutTheRenderer)
    }
}
