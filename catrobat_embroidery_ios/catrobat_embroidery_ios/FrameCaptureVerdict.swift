#if DEBUG
    /// What a frame-time capture is allowed to conclude.
    ///
    /// **A separate, non-private type because the first version of this logic lived in a
    /// `private` method on `FrameTimeReadout` and therefore could not be tested** — the test
    /// written to pin it asserted the *inputs* it would have been given and never called it, so
    /// it passed while the guard it claimed to cover was still wrong (Codex round 2, finding 1).
    /// That is the same restatement pattern this story's mutation pass was about, and the fix is
    /// the same one: make the rule a pure function that a test can read rather than re-derive.
    enum FrameCaptureVerdict: Equatable {
        /// The app lost the foreground mid-capture: the window is not the one that was timed.
        case interrupted
        /// The capture caught no frames at all.
        case nothingCaptured
        /// Frames arrived but the renderer never drew: this measures the display, not us.
        case noDraws
        /// The renderer drew, but no draw fell inside a measurable interval.
        ///
        /// **Distinct from `noDraws`, which would be a false statement.** A draw between
        /// `start()` and the first callback — or between the last callback and `stop()` — has
        /// no interval to belong to: the first callback only establishes the baseline, and
        /// after the last one nothing more is timed. Attributing such a draw *forward* to the
        /// next interval was the previous behaviour and it was worse than losing it, because
        /// a 50 ms render then wore the following 16 ms interval's duration and a capture
        /// reported a cheap frame for expensive work (Codex round 4). So the draw is not
        /// attributed, and this case says so rather than claiming nothing was drawn.
        case drawsNotMeasured(count: Int)
        /// The renderer drew, but in too few frames for order statistics to mean anything.
        ///
        /// **A distinct verdict, because `PASS` and `NO DRAWS` are both wrong here.** With one
        /// drawn interval the median, p95 and p99 are the *same single sample*, and AC3's
        /// whole point is that the tail is what matters — a tail over one observation is not a
        /// tail (Codex round 3). It is also not "no draws": the renderer did run, and saying
        /// otherwise sends the tester to check the wrong thing. The remedy is a longer capture,
        /// or one that actually exercises the renderer, so the label says which.
        case tooFewDraws(count: Int)
        /// The bar, evaluated over the frames in which the renderer actually drew.
        case measured(passed: Bool, quotableWindow: Bool)

        /// The verdict for a capture.
        ///
        /// **`drawn` rather than `all` decides the bar, and that is the whole point of this
        /// type.** A `CADisplayLink` callback fires on every display refresh whether or not
        /// SwiftUI drew anything, and the measured captures show the renderer drawing on a small
        /// *minority* of refreshes even while a run is animating: **251 draws in 2 123 frames.**
        /// So a p99 over all frames is mostly a p99 of frames in which nothing happened, and it
        /// flatters the renderer by exactly the fraction of idle frames — which is how a settled
        /// stage reported a flawless 60 fps while drawing nothing at all.
        ///
        /// An earlier attempt at this used a *ratio* — `draws * 10 < frameCount` — to reject a
        /// capture as too idle. Two things were wrong with it. It has no defensible threshold: at
        /// exactly 10 % it passes and at 9.9 % it fails, and neither answers the question. And the
        /// draw *count* is an aggregate with no timestamps, so no ratio over it can say which
        /// intervals contained work. Tagging each interval as it is recorded can, and does.
        ///
        /// - Parameters:
        ///   - all: every interval in the capture, for the window length.
        ///   - drawn: the intervals during which the canvas drew at least once.
        ///   - wasInterrupted: whether the app lost the foreground mid-capture.
        static func of(
            all: FrameTimeStatistics?,
            drawn: FrameTimeStatistics?,
            totalDraws: Int,
            wasInterrupted: Bool
        ) -> FrameCaptureVerdict {
            if wasInterrupted {
                return .interrupted
            }
            guard let all else {
                return .nothingCaptured
            }
            guard totalDraws > 0 else {
                return .noDraws
            }
            guard let drawn else {
                return .drawsNotMeasured(count: totalDraws)
            }
            // **A conclusive failure is conclusive at any sample size, and this order is the
            // point** (Codex round 4). Insufficient evidence must withhold a *pass*, not mask
            // a failure already observed: fifty drawn frames every one of which took 50 ms
            // violate the 33.3 ms limit outright, and reporting that as "inconclusive" hides
            // the one result the criterion exists to surface. So the bar is evaluated first
            // and only a *passing* capture has to clear the sample-count floor.
            let window = all.isLongEnoughToQuote
            if !drawn.meetsSixtyFps {
                return .measured(passed: false, quotableWindow: window)
            }
            guard drawn.frameCount >= minimumDrawnFrames else {
                return .tooFewDraws(count: drawn.frameCount)
            }
            // The window is a property of the capture; the bar is a property of the drawn frames.
            return .measured(passed: true, quotableWindow: window)
        }

        /// How many drawn frames the quantiles need before they are worth quoting.
        ///
        /// **100, so that p99 is not simply the maximum.** Nearest-rank p99 over `n` samples
        /// is the `ceil(0.99n)`-th; below about a hundred that is the last or second-to-last
        /// sample, so p95 and p99 collapse onto `worst` and the three numbers AC3 asks for
        /// stop being three numbers. Real captures clear it comfortably — the animating
        /// capture drew 251 times, and a mid-gesture capture redraws on most of its refreshes
        /// — so this rejects the degenerate cases without rejecting anything the hand-off
        /// actually asks for.
        static let minimumDrawnFrames = 100

        /// The label the readout shows, and the string that goes into the thesis beside a
        /// screenshot — so each case has to be unambiguous about *what was measured*.
        var label: String {
            switch self {
            case .interrupted:
                "INTERRUPTED — discard and re-capture"
            case .nothingCaptured:
                "no frames"
            case .noDraws:
                "NO DRAWS — measures the display, not the renderer"
            case let .drawsNotMeasured(count):
                "DRAWS NOT MEASURED (\(count)) — outside any timed interval"
            case let .tooFewDraws(count):
                "TOO FEW DRAWS (\(count)) — need \(Self.minimumDrawnFrames) for a tail"
            case let .measured(passed, quotableWindow):
                "\(passed ? "PASS" : "FAIL")\(quotableWindow ? "" : " (short)")"
            }
        }

        /// Whether this verdict may be quoted as evidence about the renderer at all.
        ///
        /// `false` for everything except a measured one: the hand-off's instruction on a missed
        /// bar is to start down ADR-029's fallback ladder, and three of these four cases are the
        /// wrong destination for that.
        var isAboutTheRenderer: Bool {
            if case .measured = self {
                return true
            }
            return false
        }
    }
#endif
