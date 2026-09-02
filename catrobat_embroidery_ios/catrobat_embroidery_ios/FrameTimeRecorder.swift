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
    /// into a buffer reserved up front — and, deliberately, **not one SwiftUI body evaluation**.
    /// `intervals` is `@ObservationIgnored` for that reason: as a plain stored property of an
    /// `@Observable` class it fired `withMutation` on every append, so `FrameTimeReadout`'s
    /// `frameCount`-dependent caption re-ran two `String(format:)` calls and re-rendered a
    /// `.regularMaterial` blur **over the canvas being measured**, sixty times a second, while
    /// the stage was otherwise completely static. The instrument was contributing to the
    /// distribution it reports. The observable properties are `isRecording`, `statistics`,
    /// `wasInterrupted`, `drawCount` and `nominalFrameMilliseconds`, and all of them change
    /// only in `start()` and `stop()` — a handful of body evaluations per capture rather than
    /// one per displayed frame. (An earlier version of this sentence said "at most once per
    /// capture", which is wrong: `isRecording` changes at both ends, and a second capture
    /// clears what the first published before republishing it.)
    ///
    /// The reservation is the other load-bearing half — a recorder that reallocates mid-capture
    /// perturbs the frames it is measuring at geometrically spaced moments, injecting outliers
    /// into the tail, which is the only part of the distribution the criterion reads.
    ///
    /// `#if DEBUG` in the same sense as `SampleID.us309Synthetic`: absent from any build a user
    /// could install, present in the Release-with-`DEBUG` build the measurement is taken on.
    @MainActor
    @Observable
    final class FrameTimeRecorder {
        private(set) var isRecording = false

        /// The last completed capture. Published on `stop()` rather than kept live, so the
        /// readout — and a screenshot of it — shows a settled result instead of four numbers
        /// moving while they are being read.
        private(set) var statistics: FrameTimeStatistics?

        /// Whether the capture was interrupted by the app losing the foreground.
        ///
        /// **Reported, because the alternative is a bogus `FAIL` with nothing to distinguish it
        /// from a real one.** A `CADisplayLink` stops delivering while the app is inactive but
        /// `previousTimestamp` survives, so without this the whole background gap arrived as one
        /// interval — seconds long, straight into `worst`, failing both halves of the bar. Over
        /// the eleven ≥ 10 s holds the hand-off asks for, that happens at least once, and
        /// it would send the tester down ADR-029's fallback ladder after a measurement of
        /// nothing. `noteSuspended()` now drops the gap and this flag says a capture was touched.
        private(set) var wasInterrupted = false

        /// The bar, evaluated over the frames in which the canvas actually drew.
        ///
        /// **This, not `statistics`, is the number that says anything about the renderer.**
        /// A display-link callback fires on every refresh whether or not SwiftUI drew, and
        /// the measured captures show the canvas drawing on a small *minority* of refreshes
        /// even mid-run — 251 draws in 1 932 frames — so a p99 over all frames is mostly a
        /// p99 of frames in which nothing happened (Codex round 2, finding 1). `nil` when the
        /// capture contained no drawn frame at all, which is the settled-stage case.
        private(set) var drawnStatistics: FrameTimeStatistics?

        /// Canvas draw passes during the last completed capture.
        ///
        /// **The number that says whether the capture measured the renderer or the display.**
        /// A display-link callback fires on every refresh whether or not SwiftUI redrew
        /// anything, so on a settled static stage a capture can report a flawless 60 fps
        /// having asked the renderer for nothing at all (Codex round 1, finding 1). `nil`
        /// before any capture. See `StageDrawCounter`.
        private(set) var drawCount: Int?

        /// The display's **actual** frame interval in milliseconds, sampled in the callback.
        ///
        /// **Reported because the bar is absolute and the refresh rate is not guaranteed.**
        /// iOS may drop a display link to 30, 20 or 15 Hz under Low Power Mode, a critical
        /// thermal state, or the "Limit Frame Rate" accessibility setting. At 30 Hz every
        /// interval is ~33.3 ms, so a renderer doing essentially no work fails **both**
        /// halves of AC3's bar — an unforced FAIL indistinguishable from the real thing
        /// (Codex round 1, finding 3). With this on screen the tester sees 33.3 and knows to
        /// check the device rather than to start down the fallback ladder.
        ///
        /// **From `targetTimestamp - timestamp`, not from `CADisplayLink.duration`.** The
        /// first version read `duration`, which Apple documents as based on the **maximum**
        /// frame rate — so on a link policy-throttled to 30 Hz it can still report ~16.67 ms,
        /// printing `60Hz` beside the very `FAIL` this field exists to explain (Codex round 2,
        /// finding 2). It is also undefined until the selector has fired at least once, so
        /// reading it at `stop()` after a capture that caught nothing could publish a
        /// meaningless positive value. `targetTimestamp - timestamp` is the actual frame
        /// duration and is only ever read inside a callback. `nil` before any capture.
        private(set) var nominalFrameMilliseconds: Double?

        /// Frames recorded in the capture currently running.
        ///
        /// Not observable: see the note on `intervals`. Read by tests and by `stop()`, never by
        /// a view body during a capture.
        var frameCount: Int {
            intervals.count
        }

        /// Exposed for the test that pins the preallocation; there is no other reason to read it.
        var reservedCapacity: Int {
            intervals.capacity
        }

        @ObservationIgnored private var intervals: [Double] = []
        /// The subset of `intervals` during which the canvas drew at least once.
        ///
        /// **Tagged as each interval is recorded, because a draw *count* cannot be
        /// apportioned afterwards.** An aggregate of draws over a whole capture says how many
        /// there were and nothing about which frames contained them, so no ratio over it can
        /// separate the renderer's frames from the display's. One integer comparison per
        /// callback can.
        @ObservationIgnored private var drawnIntervals: [Double] = []
        @ObservationIgnored private var previousDrawCount = 0
        @ObservationIgnored private var previousTimestamp: CFTimeInterval?
        /// True between losing and regaining the foreground. While set, callbacks record nothing
        /// **and do not re-seed `previousTimestamp`**, so the gap cannot be reconstructed from
        /// either side of itself.
        @ObservationIgnored private var isSuspended = false
        @ObservationIgnored private var drawsAtStart = 0

        /// Invalidated in `stop()`, when the view holding the recorder disappears, and — as the
        /// backstop — by the proxy itself on the first callback after the recorder is gone.
        ///
        /// There is deliberately no `deinit`: `link` is main-actor isolated where `deinit` is
        /// not. That used to make a *recording* recorder immortal, because the link retained the
        /// proxy and the proxy retained the recorder, so `stop()` was the only release path and
        /// anything that dropped the view without calling it — tapping Back, picking another
        /// design, `runner.reset()` taking `StageContentState` to `.notRun` — left the link
        /// firing at 60 Hz for the rest of the process, appending past the reservation and
        /// contaminating every subsequent capture. `FrameTimeProxy` now holds the recorder
        /// **weakly** and invalidates the link when it finds it gone, so the cycle no longer
        /// exists and a leaked link retires itself.
        @ObservationIgnored private var link: CADisplayLink?

        /// Sized for a 120 Hz display over AC3's window plus headroom, so neither a ProMotion
        /// device nor an over-long capture reallocates.
        private static let capacity = 4 * FrameTimeStatistics.quotableFrameCount

        init() {}

        /// Begins a capture, discarding whatever the previous one left.
        ///
        /// **`previousTimestamp` is cleared here**, which is not bookkeeping: carrying it across
        /// would make the first interval of every capture after the first the length of the pause
        /// between them — a multi-second frame, landing squarely in the worst-frame statistic.
        ///
        /// **`isActive` is the scene's *state*, and taking it closes a hole in the suspend
        /// logic** (Codex round 1, finding 2). `noteSuspended()`/`noteResumed()` record scene
        /// *transitions*, and both are no-ops outside a capture — so a recorder started while
        /// the app was already inactive believed it was active, ignored the later
        /// `noteResumed()`, and measured the entire background gap as one frame with
        /// `wasInterrupted` still `false`: an ordinary-looking FAIL rather than an
        /// `INTERRUPTED` one. Passing the phase in means the state cannot be mis-inferred
        /// from a transition that was never delivered.
        func start(isActive: Bool = true) {
            stopLink()
            intervals.removeAll(keepingCapacity: true)
            intervals.reserveCapacity(Self.capacity)
            drawnIntervals.removeAll(keepingCapacity: true)
            drawnIntervals.reserveCapacity(Self.capacity)
            previousTimestamp = nil
            previousDrawCount = StageDrawCounter.count
            isSuspended = !isActive
            wasInterrupted = !isActive
            statistics = nil
            drawnStatistics = nil
            drawCount = nil
            nominalFrameMilliseconds = nil
            drawsAtStart = StageDrawCounter.count
            isRecording = true

            let link = CADisplayLink(
                target: FrameTimeProxy(recorder: self),
                selector: #selector(FrameTimeProxy.tick(_:))
            )
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        /// Ends the capture and publishes its statistics, or `nil` if it caught no frames.
        @discardableResult
        func stop() -> FrameTimeStatistics? {
            stopLink()
            isRecording = false
            drawCount = StageDrawCounter.count - drawsAtStart
            statistics = FrameTimeStatistics(millisecondsPerFrame: intervals)
            drawnStatistics = FrameTimeStatistics(millisecondsPerFrame: drawnIntervals)
            return statistics
        }

        /// One display-link callback.
        ///
        /// Takes the **timestamp**, not a duration, so the delta arithmetic — the part that can
        /// be wrong — is inside the type and drivable by a test. A `CADisplayLink` timestamp is
        /// when the previous frame was displayed, so the first callback of a capture has nothing
        /// to subtract from and deliberately records nothing; emitting a sample there would put
        /// the interval since the epoch into the capture.
        func record(timestamp: CFTimeInterval, frameDuration: CFTimeInterval? = nil) {
            guard isRecording, !isSuspended else { return }
            let draws = StageDrawCounter.count
            defer {
                previousTimestamp = timestamp
                previousDrawCount = draws
            }
            // The link reports its actual period only once it has fired, so this arrives from
            // the callback rather than being read off the link at `stop()`.
            if let frameDuration, frameDuration > 0 {
                nominalFrameMilliseconds = frameDuration * 1000
            }
            guard let previous = previousTimestamp else { return }
            let milliseconds = (timestamp - previous) * 1000
            intervals.append(milliseconds)
            // Did the canvas draw during the interval that produced this frame? Tagged here
            // because it cannot be recovered from the totals afterwards.
            if draws > previousDrawCount {
                drawnIntervals.append(milliseconds)
            }
        }

        /// The app lost the foreground: stop recording and mark the capture.
        ///
        /// Driven from the view's `scenePhase` rather than from a notification inside this type,
        /// so the whole of I5's fix is reachable from a test without a scene. Called on the
        /// resign-active edge, which is *ahead* of the link being paused — hence the flag rather
        /// than a one-shot clear of `previousTimestamp`, which a callback arriving between the
        /// two would immediately undo.
        func noteSuspended() {
            guard isRecording, !isSuspended else { return }
            isSuspended = true
            wasInterrupted = true
        }

        /// The app has the foreground again: resume with a fresh baseline.
        ///
        /// **Not guarded on having been suspended.** Clearing the baseline on any return to
        /// active is free — the next callback re-seeds it — and it closes the case where the
        /// resign-active transition never reached a *recording* recorder, which would leave a
        /// stale timestamp from before the gap (Codex round 1, finding 2).
        func noteResumed() {
            isSuspended = false
            previousTimestamp = nil
        }

        private func stopLink() {
            link?.invalidate()
            link = nil
        }
    }

    /// The `NSObject` `CADisplayLink` needs as a target.
    ///
    /// Separate from the recorder so that `FrameTimeRecorder` can stay a plain `@Observable`
    /// value-ish class rather than an `NSObject`, and **weak** so that the link no longer keeps
    /// a recording recorder alive: the link retains this proxy, the run loop retains the link,
    /// and nothing here retains the recorder. A link that outlives its recorder finds `nil` on
    /// its next callback and invalidates itself, so the worst case is one wasted frame rather
    /// than a 60 Hz callback for the rest of the process.
    @MainActor
    private final class FrameTimeProxy: NSObject {
        private weak var recorder: FrameTimeRecorder?

        init(recorder: FrameTimeRecorder) {
            self.recorder = recorder
        }

        @objc func tick(_ link: CADisplayLink) {
            guard let recorder else {
                link.invalidate()
                return
            }
            recorder.record(
                timestamp: link.timestamp,
                frameDuration: link.targetTimestamp - link.timestamp
            )
        }
    }
#endif
