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
        let verdict = FrameCaptureVerdict.of(all: perfect, drawn: nil, wasInterrupted: false)

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
        let verdict = FrameCaptureVerdict.of(all: all, drawn: drawn, wasInterrupted: false)
        #expect(verdict == .measured(passed: false, quotableWindow: true))
        #expect(verdict.isAboutTheRenderer)
    }

    /// A capture whose drawn frames are inside the budget passes, and says so.
    @Test("drawn frames inside the budget pass")
    func drawnFramesInsideTheBudgetPass() {
        let verdict = FrameCaptureVerdict.of(
            all: stats(Array(repeating: 16.0, count: 700)),
            drawn: stats(Array(repeating: 16.0, count: 200)),
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
            wasInterrupted: false
        )
        #expect(verdict == .tooFewDraws(count: 1))
        #expect(!verdict.isAboutTheRenderer, "one sample cannot be evidence about the renderer")
    }

    /// The threshold is where p99 stops being the maximum, and it is checked at its own edge.
    @Test("the drawn-frame threshold is exact at its boundary")
    func theDrawnFrameThresholdIsExactAtItsBoundary() {
        let all = stats(Array(repeating: 16.0, count: 700))
        let justUnder = FrameCaptureVerdict.minimumDrawnFrames - 1
        #expect(
            FrameCaptureVerdict.of(
                all: all,
                drawn: stats(Array(repeating: 16.0, count: justUnder)),
                wasInterrupted: false
            ) == .tooFewDraws(count: justUnder)
        )
        #expect(
            FrameCaptureVerdict.of(
                all: all,
                drawn: stats(Array(repeating: 16.0, count: FrameCaptureVerdict.minimumDrawnFrames)),
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
            wasInterrupted: true
        )
        #expect(verdict == .interrupted)
        #expect(!verdict.isAboutTheRenderer)
    }

    /// A capture that caught no frames at all is distinguished from one that caught frames but
    /// drew nothing — different problems with different fixes.
    @Test("no frames is distinguished from no draws")
    func noFramesIsDistinguishedFromNoDraws() {
        #expect(FrameCaptureVerdict.of(all: nil, drawn: nil, wasInterrupted: false) == .nothingCaptured)
    }

    /// Every case reads differently, so a screenshot of the row is unambiguous about what was
    /// measured — which is the point of the labels going into the thesis.
    @Test("every verdict reads differently")
    func everyVerdictReadsDifferently() {
        let labels = [
            FrameCaptureVerdict.interrupted,
            .nothingCaptured,
            .noDraws,
            .tooFewDraws(count: 3),
            .measured(passed: true, quotableWindow: true),
            .measured(passed: false, quotableWindow: true),
            .measured(passed: true, quotableWindow: false)
        ].map(\.label)

        #expect(Set(labels).count == labels.count)
        #expect(labels.allSatisfy { !$0.isEmpty })
    }
}
