#if DEBUG
import Observation
import QuartzCore

/// US-309's instrument: displayed frames in, AC3's four numbers out.
///
/// **`CADisplayLink` rather than Instruments, and the reason is the thesis.** The criterion
/// asks for the median, p95, p99 and worst frame over a labelled ≥ 10 s window. Instruments'
/// Animation Hitches gives a timeline and hitch *ratios*; extracting four order statistics
/// over a window you have to identify by eye is neither reproducible nor quotable. This emits
/// the numbers directly, the same way on every run, in a build a device can install — and a
/// separate Instruments trace of the same capture is the independent cross-check that the
/// recorder is not lying (ADR-029).
///
/// **What it costs the frame it measures**: one `CFTimeInterval` subtraction and one append
/// into a buffer reserved up front. The reservation is the load-bearing half — a recorder
/// that reallocates mid-capture perturbs the frames it is measuring at geometrically spaced
/// moments, injecting outliers into the tail, which is the only part of the distribution the
/// criterion reads.
///
/// `#if DEBUG` in the same sense as `SampleID.us309Synthetic`: absent from any build a user
/// could install, present in the Release-with-`DEBUG` build the measurement is taken on. A
/// `CADisplayLink` retained past its window is exactly the sort of thing that shows up later
/// as a battery bug, so it is invalidated in `stop()` and in `deinit`.
@MainActor
@Observable
final class FrameTimeRecorder {
    private(set) var isRecording = false

    /// The last completed capture. Published on `stop()` rather than kept live, so the
    /// readout — and a screenshot of it — shows a settled result instead of four numbers
    /// moving while they are being read.
    private(set) var statistics: FrameTimeStatistics?

    /// Frames recorded in the capture currently running.
    var frameCount: Int { intervals.count }

    /// Exposed for the test that pins the preallocation; there is no other reason to read it.
    var reservedCapacity: Int { intervals.capacity }

    private var intervals: [Double] = []
    private var previousTimestamp: CFTimeInterval?
    /// **Invalidated in `stop()`, and there is deliberately no `deinit` doing it.**
    /// `CADisplayLink` retains its target, so a running recorder is kept alive by its own
    /// link and a `deinit` could not run while one was in flight; and `link` is main-actor
    /// isolated where `deinit` is not, so it could not touch it anyway. `stop()` is the only
    /// place the link can be released, which is why every path out of a capture goes through
    /// it.
    private var link: CADisplayLink?

    /// Sized for a 120 Hz display over AC3's window plus headroom, so neither a ProMotion
    /// device nor an over-long capture reallocates.
    private static let capacity = 4 * FrameTimeStatistics.quotableFrameCount

    init() {}

    /// Begins a capture, discarding whatever the previous one left.
    ///
    /// **`previousTimestamp` is cleared here**, which is not bookkeeping: carrying it across
    /// would make the first interval of every capture after the first the length of the pause
    /// between them — a multi-second frame, landing squarely in the worst-frame statistic.
    func start() {
        stopLink()
        intervals.removeAll(keepingCapacity: true)
        intervals.reserveCapacity(Self.capacity)
        previousTimestamp = nil
        statistics = nil
        isRecording = true

        let link = CADisplayLink(target: FrameTimeProxy(recorder: self), selector: #selector(FrameTimeProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Ends the capture and publishes its statistics, or `nil` if it caught no frames.
    @discardableResult
    func stop() -> FrameTimeStatistics? {
        stopLink()
        isRecording = false
        statistics = FrameTimeStatistics(millisecondsPerFrame: intervals)
        return statistics
    }

    /// One display-link callback.
    ///
    /// Takes the **timestamp**, not a duration, so the delta arithmetic — the part that can
    /// be wrong — is inside the type and drivable by a test. A `CADisplayLink` timestamp is
    /// when the previous frame was displayed, so the first callback of a capture has nothing
    /// to subtract from and deliberately records nothing; emitting a sample there would put
    /// the interval since the epoch into the capture.
    func record(timestamp: CFTimeInterval) {
        guard isRecording else { return }
        defer { previousTimestamp = timestamp }
        guard let previous = previousTimestamp else { return }
        intervals.append((timestamp - previous) * 1_000)
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }
}

/// The `NSObject` `CADisplayLink` needs as a target.
///
/// Separate from the recorder so that `FrameTimeRecorder` can stay a plain `@Observable`
/// value-ish class rather than an `NSObject`, and so the retain cycle is explicit: the link
/// retains this proxy, this proxy retains the recorder, and `stop()` breaks both by
/// invalidating the link.
@MainActor
private final class FrameTimeProxy: NSObject {
    private let recorder: FrameTimeRecorder

    init(recorder: FrameTimeRecorder) {
        self.recorder = recorder
    }

    @objc func tick(_ link: CADisplayLink) {
        recorder.record(timestamp: link.timestamp)
    }
}
#endif
