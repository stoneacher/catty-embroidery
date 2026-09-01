@testable import catrobat_embroidery_ios
import Testing

/// US-309 AC3: the four order statistics the criterion names, and the bar it states.
///
/// **The bar is stated before anything is measured**, which is the criterion's own
/// requirement and the reason this suite exists at all: without an explicit pass/fail
/// definition, a capture with periodic dropped frames satisfies every other item in the
/// story. p99 ≤ 16.67 ms **and** no frame over 33.3 ms — a mean would hide exactly the
/// stutter the criterion is for, and so, less obviously, would a median.
///
/// The statistics are a pure function of a duration array so they can be tested without a
/// display, a device or a frame. What cannot be unit-tested — that `CADisplayLink` delivers
/// one callback per displayed frame — is confined to `FrameTimeProbe`, which does nothing
/// but forward.
@Suite("US-309 frame-time statistics")
struct FrameTimeStatisticsTests {
    /// Nearest-rank, and pinned against hand-computed values rather than against a second
    /// implementation of the same formula.
    ///
    /// 100 frames of 1…100 ms make every rank checkable by eye: the median is the 50th value,
    /// p95 the 95th, p99 the 99th, the worst the 100th. A test that recomputed the percentile
    /// would pass against an off-by-one in both places at once.
    @Test("the four order statistics are nearest-rank")
    func theFourOrderStatisticsAreNearestRank() throws {
        let stats = try #require(FrameTimeStatistics(millisecondsPerFrame: (1 ... 100).map(Double.init)))

        #expect(stats.frameCount == 100)
        #expect(stats.median == 50)
        #expect(stats.p95 == 95)
        #expect(stats.p99 == 99)
        #expect(stats.worst == 100)
    }

    /// Order must not matter: frames arrive in time order, and the statistics are about the
    /// distribution.
    @Test("the statistics do not depend on arrival order")
    func theStatisticsDoNotDependOnArrivalOrder() throws {
        let ascending = try #require(FrameTimeStatistics(millisecondsPerFrame: (1 ... 100).map(Double.init)))
        let descending = try #require(
            FrameTimeStatistics(millisecondsPerFrame: (1 ... 100).reversed().map(Double.init))
        )
        #expect(ascending == descending)
    }

    /// **The test that gives the criterion its teeth.** A capture whose average and median are
    /// comfortably inside 60 fps, and which drops a frame every hundred, must fail.
    @Test("a capture that drops one frame in a hundred fails the bar")
    func aCaptureThatDropsOneFrameInAHundredFailsTheBar() throws {
        var frames = Array(repeating: 8.0, count: 99 * 10)
        frames += Array(repeating: 40.0, count: 10)
        let stats = try #require(FrameTimeStatistics(millisecondsPerFrame: frames))

        #expect(stats.median == 8, "the median is untroubled — which is the point")
        #expect(!stats.meetsSixtyFps)
        #expect(stats.worst > FrameTimeStatistics.droppedFrameMilliseconds)
    }

    /// The other half of the bar, in isolation: a capture with no doubled frame at all can
    /// still miss, if the ninety-ninth percentile sits past a frame interval.
    @Test("a capture with no dropped frame can still miss on p99")
    func aCaptureWithNoDroppedFrameCanStillMissOnP99() throws {
        var frames = Array(repeating: 10.0, count: 950)
        frames += Array(repeating: 20.0, count: 50)
        let stats = try #require(FrameTimeStatistics(millisecondsPerFrame: frames))

        #expect(stats.worst <= FrameTimeStatistics.droppedFrameMilliseconds)
        #expect(stats.p99 > FrameTimeStatistics.frameBudgetMilliseconds)
        #expect(!stats.meetsSixtyFps)
    }

    /// **The regression this bar was born from.** A display running at exactly 60 Hz reports
    /// a nominal 16.6667 ms per frame; deriving the budget from the refresh rate rather than
    /// taking AC3's stated 16.67 ms made a flawless capture fail on float noise, which the
    /// simulator rehearsal caught before any device was involved (1 196 frames, all on time,
    /// reported FAIL).
    @Test("a nominal sixty-hertz capture passes the bar")
    func aNominalSixtyHertzCapturePassesTheBar() throws {
        let nominal = 1_000.0 / 60
        let stats = try #require(FrameTimeStatistics(
            millisecondsPerFrame: (0 ..< 1_200).map { nominal + Double($0 % 3) * 1e-9 }
        ))
        #expect(stats.meetsSixtyFps)
    }

    @Test("a capture inside the bar passes it")
    func aCaptureInsideTheBarPassesIt() throws {
        let stats = try #require(FrameTimeStatistics(millisecondsPerFrame: Array(repeating: 16.0, count: 600)))
        #expect(stats.meetsSixtyFps)
    }

    /// No frames is not a passing capture; it is no capture.
    ///
    /// `nil` rather than a zeroed value, because a zeroed `FrameTimeStatistics` would report
    /// `meetsSixtyFps == true` for a run that never rendered — the most flattering possible
    /// answer to the criterion, produced by measuring nothing.
    @Test("an empty capture is not a passing capture")
    func anEmptyCaptureIsNotAPassingCapture() {
        #expect(FrameTimeStatistics(millisecondsPerFrame: []) == nil)
    }

    /// AC3 asks for a ≥ 10 s window; at 60 Hz that is 600 frames. Reported rather than
    /// enforced — the recorder cannot know the display's refresh rate — but reported so a
    /// short capture cannot be quoted as if it satisfied the criterion.
    @Test("a capture reports whether it is long enough to quote")
    func aCaptureReportsWhetherItIsLongEnoughToQuote() throws {
        let short = try #require(FrameTimeStatistics(millisecondsPerFrame: Array(repeating: 16.0, count: 300)))
        let long = try #require(FrameTimeStatistics(millisecondsPerFrame: Array(repeating: 16.0, count: 600)))
        #expect(!short.isLongEnoughToQuote)
        #expect(long.isLongEnoughToQuote)
    }
}
