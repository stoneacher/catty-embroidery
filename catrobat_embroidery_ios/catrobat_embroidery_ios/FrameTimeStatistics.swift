import Foundation

/// The four order statistics US-309's exit criterion is stated in, and the bar it sets.
///
/// **AC3 requires the pass/fail definition to be fixed before anything is measured**, and
/// this type is that definition in code rather than in prose. Without it "60 fps" is a claim
/// a capture with periodic dropped frames satisfies: the mean of ninety-nine 8 ms frames and
/// one 40 ms frame is 8.3 ms, and so is the median. The stutter that a user actually sees is
/// visible only in the tail, which is why the criterion asks for **median, p95, p99 and
/// worst** and forbids reporting an average.
///
/// A pure function of an array of frame durations, so the whole of it is testable without a
/// device, a display or a frame. What genuinely cannot be unit-tested — that `CADisplayLink`
/// delivers one callback per displayed frame — is confined to `FrameTimeProxy`, which does
/// nothing but forward a timestamp into here.
struct FrameTimeStatistics: Equatable {
    /// The p99 bar: **16.67 ms, the criterion's own figure, deliberately not `1000.0 / 60`.**
    ///
    /// The difference is 3.3 µs and it decides the result. A display link on a 60 Hz display
    /// reports intervals of a nominal 16.6667 ms with sub-microsecond jitter, and that jitter
    /// is not symmetric about the nominal period — so comparing against the exact period is a
    /// knife-edge that a *perfect* capture loses. Measured, on the simulator rehearsal before
    /// any device was involved: a capture of 1 196 frames, every one of them on time, came
    /// back `med 16.7 p95 16.7 p99 16.7 max 16.7 · FAIL`.
    ///
    /// AC3 states the bar as 16.67 ms. Taking the criterion at its word is both the honest
    /// reading and the one with the 3.3 µs of slack that a real display needs — and it is why
    /// the constant is written as the criterion writes it rather than derived from the
    /// refresh rate.
    static let frameBudgetMilliseconds = 16.67

    /// A frame past this is a *dropped* frame — the thing the "no frame exceeds" half of the
    /// bar catches and an average hides. 33.3 ms, again the criterion's figure rather than
    /// twice the nominal period, for the same reason.
    static let droppedFrameMilliseconds = 33.3

    /// AC3's window: **≥ 10 s, measured as time.**
    static let quotableMilliseconds = 10_000.0

    /// The same window expressed in frames, for **sizing the recorder's buffer only** — a
    /// reservation has to be made in elements before any frame has arrived. It is not the
    /// quotability test: see `isLongEnoughToQuote`.
    static let quotableFrameCount = 600

    let frameCount: Int

    /// The capture's wall-clock length. The intervals *are* the elapsed time, so this is a
    /// sum rather than an estimate — which is what lets `isLongEnoughToQuote` drop the
    /// refresh-rate assumption it used to carry.
    let totalMilliseconds: Double

    let median: Double
    let p95: Double
    let p99: Double
    let worst: Double

    /// How far into the capture the worst frame fell, in milliseconds from its start.
    ///
    /// **Kept because the hand-off asks for it and sorting had thrown it away.** Capture 5
    /// runs the animation to 50 000 and says "note where in the run the worst frame falls" —
    /// the bake schedule's last and largest rasterisation lands near the end, so *where*
    /// distinguishes a bake spike from an unrelated stutter. Every other statistic here is
    /// order-independent by design; this one deliberately is not, and it is the only reason
    /// the unsorted array is walked (Codex round 1, finding 4).
    let worstAtMilliseconds: Double

    /// **Optional, and that is a correctness decision rather than fastidiousness.** A zeroed
    /// `FrameTimeStatistics` would report `meetsSixtyFps == true` for a capture that never
    /// rendered a frame — the most flattering possible answer to the criterion, produced by
    /// measuring nothing at all.
    init?(millisecondsPerFrame durations: [Double]) {
        guard !durations.isEmpty else { return nil }
        let sorted = durations.sorted()
        frameCount = sorted.count
        totalMilliseconds = durations.reduce(0, +)
        median = Self.nearestRank(sorted, quantile: 0.50)
        p95 = Self.nearestRank(sorted, quantile: 0.95)
        p99 = Self.nearestRank(sorted, quantile: 0.99)
        // `last`, not `nearestRank(1.0)`: the same value by construction, and saying so
        // directly means the worst frame cannot be lost to a rounding rule.
        worst = sorted[sorted.count - 1]
        // Walked in arrival order, because position is the one thing sorting destroys. On a
        // tie the *first* occurrence wins, which is the conservative reading for a bake
        // spike: it points at the earliest frame that hit the worst cost.
        var elapsed = 0.0
        var worstAt = 0.0
        for duration in durations {
            if duration == worst {
                worstAt = elapsed
                break
            }
            elapsed += duration
        }
        worstAtMilliseconds = worstAt
    }

    /// AC3's bar, in one place: **p99 ≤ one frame, and no frame past two.**
    ///
    /// Both halves are needed and neither implies the other. A capture can hold every frame
    /// under 33.3 ms and still miss, if five per cent of frames sit at 20 ms; and a capture
    /// can have a p99 inside the budget and still drop one frame in five hundred.
    var meetsSixtyFps: Bool {
        p99 <= Self.frameBudgetMilliseconds && worst <= Self.droppedFrameMilliseconds
    }

    /// Whether the capture is long enough to be quoted as satisfying AC3's ≥ 10 s window.
    ///
    /// **A duration, not a frame count, and the earlier comment here was wrong to say it had
    /// to be a count.** It claimed this type "cannot know the display's refresh rate", which
    /// is true and irrelevant: the sum of the intervals is the capture's own wall-clock
    /// length, so ≥ 10 s is checkable with no assumption about the rate at all. The frame
    /// count spelling read 600 frames as ten seconds, which on a 120 Hz device is five —
    /// under-reporting the window in exactly the case the hedge was written for.
    ///
    /// Reported rather than enforced: it exists so a short capture cannot be tabulated as if
    /// it met the criterion. It is also what makes the hand-off's "hold for ten seconds"
    /// self-correcting, now that the readout no longer counts frames on screen while the
    /// capture is running.
    var isLongEnoughToQuote: Bool {
        totalMilliseconds >= Self.quotableMilliseconds
    }

    /// Nearest-rank: the smallest value at or below which at least `quantile` of the samples
    /// fall — `ceil(q · n)`, 1-indexed.
    ///
    /// Chosen over linear interpolation because an interpolated p99 is a value **no frame
    /// took**, and the criterion is about frames that happened. It also cannot be gamed by a
    /// capture length: at any n, this returns a real measurement.
    private static func nearestRank(_ sorted: [Double], quantile: Double) -> Double {
        let rank = Int((quantile * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}
