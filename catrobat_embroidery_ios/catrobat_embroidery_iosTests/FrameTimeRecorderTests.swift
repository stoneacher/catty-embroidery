@testable import catrobat_embroidery_ios
import Testing

/// US-309's instrument of record: the thing that turns displayed frames into AC3's four
/// numbers.
///
/// **The display link is not under test here, and cannot be.** What can be tested — and is
/// what would actually go wrong — is the arithmetic around it: that the first callback
/// produces no sample (there is nothing to subtract from), that deltas are inter-frame
/// intervals rather than timestamps, that a stopped capture is immutable, and that the buffer
/// does not grow while it is being written to. `record(timestamp:)` takes the timestamp
/// rather than the duration precisely so this suite can drive it.
@MainActor
struct FrameTimeRecorderTests {
    /// A `CADisplayLink` timestamp is *when the previous frame was displayed*, so the first
    /// callback of a capture has nothing to measure against. Emitting a sample there would
    /// put one enormous bogus frame — the interval since the epoch — into every capture, and
    /// it would land in exactly the statistic the criterion cares most about: the worst.
    @Test("the first frame of a capture produces no sample")
    func theFirstFrameOfACaptureProducesNoSample() {
        let recorder = FrameTimeRecorder()
        recorder.start()
        recorder.record(timestamp: 1_000)

        #expect(recorder.frameCount == 0)
    }

    @Test("samples are inter-frame intervals in milliseconds")
    func samplesAreInterFrameIntervalsInMilliseconds() throws {
        let recorder = FrameTimeRecorder()
        recorder.start()
        // 16 ms, then 32 ms — a normal frame and a dropped one.
        for timestamp in [1.000, 1.016, 1.048] {
            recorder.record(timestamp: timestamp)
        }

        let stats = try #require(recorder.stop())
        #expect(stats.frameCount == 2)
        #expect(abs(stats.median - 16) < 0.001)
        #expect(abs(stats.worst - 32) < 0.001)
    }

    /// Nothing is recorded outside a capture window, so a stray callback between captures —
    /// the display link is not torn down instantly — cannot contaminate the next one.
    @Test("frames outside a capture window are ignored")
    func framesOutsideACaptureWindowAreIgnored() {
        let recorder = FrameTimeRecorder()
        recorder.record(timestamp: 1.000)
        recorder.record(timestamp: 1.016)

        #expect(recorder.frameCount == 0)
        #expect(recorder.statistics == nil)
    }

    /// A second capture starts empty, and — the part that matters — does not measure the gap
    /// since the last one. Carrying the previous timestamp across `start()` would make the
    /// first interval of every capture after the first the length of the pause between them.
    @Test("a second capture does not measure the gap since the first")
    func aSecondCaptureDoesNotMeasureTheGapSinceTheFirst() throws {
        let recorder = FrameTimeRecorder()
        recorder.start()
        recorder.record(timestamp: 1.000)
        recorder.record(timestamp: 1.016)
        _ = recorder.stop()

        recorder.start()
        recorder.record(timestamp: 90.000)
        recorder.record(timestamp: 90.016)

        let stats = try #require(recorder.stop())
        #expect(stats.frameCount == 1)
        #expect(abs(stats.worst - 16) < 0.001, "a 89-second first frame would mean the epoch leaked in")
    }

    /// The buffer is sized for the whole window up front.
    ///
    /// A recorder that reallocates mid-capture perturbs the very frames it is measuring, and
    /// it would do so at geometrically spaced moments — which is to say, it would inject
    /// outliers into the tail, the only part of the distribution the criterion reads.
    /// The literal 2 400 rather than `quotableFrameCount`, which is 600: asserting the
    /// smaller number bit only against *no* reservation at all, while the code documents a
    /// buffer sized for a 120 Hz display over the whole window plus headroom. A literal also
    /// cannot restate the formula it is checking.
    @Test("the buffer is preallocated for a full capture")
    func theBufferIsPreallocatedForAFullCapture() {
        let recorder = FrameTimeRecorder()
        recorder.start()
        #expect(recorder.reservedCapacity >= 2_400)
    }

    /// A capture with no frames at all yields no statistics — never a flattering zero.
    @Test("an empty capture yields no statistics")
    func anEmptyCaptureYieldsNoStatistics() {
        let recorder = FrameTimeRecorder()
        recorder.start()
        #expect(recorder.stop() == nil)
    }

    /// `stop()` publishes the result so the readout — and a screenshot of it — can show the
    /// numbers after the capture rather than a live value that moves while it is being read.
    @Test("stopping publishes the capture's statistics")
    func stoppingPublishesTheCapturesStatistics() throws {
        let recorder = FrameTimeRecorder()
        recorder.start()
        // 701 timestamps, so 700 intervals of 16 ms — 11.2 s, a real window. 600 would be
        // 9.6 s and would not be quotable, which is the whole point of measuring the window
        // in seconds rather than in frames.
        for index in 0 ... 700 {
            recorder.record(timestamp: Double(index) * 0.016)
        }
        _ = recorder.stop()

        let published = try #require(recorder.statistics)
        #expect(published.frameCount == 700)
        #expect(published.isLongEnoughToQuote)
        #expect(published.meetsSixtyFps)
        #expect(!recorder.isRecording)
    }

    /// **I5: backgrounding mid-capture must not be reported as a dropped frame.**
    ///
    /// `CADisplayLink` stops delivering while the app is inactive, but timestamps keep
    /// advancing, so without the suspension the gap arrived as one multi-second interval:
    /// straight into `worst`, failing both halves of the bar. Across the eleven ≥ 10 s
    /// holds the hand-off asks for this happens at least once, and the hand-off's answer to a
    /// missed bar is to start tuning constants — the wrong destination for a measurement of
    /// nothing.
    @Test("a capture interrupted by backgrounding does not record the gap")
    func aCaptureInterruptedByBackgroundingDoesNotRecordTheGap() throws {
        let recorder = FrameTimeRecorder()
        recorder.start()
        recorder.record(timestamp: 1.000)
        recorder.record(timestamp: 1.016)

        recorder.noteSuspended()
        // A callback can still arrive between resign-active and the link actually pausing;
        // it must neither record nor re-seed the baseline, or the gap comes back.
        recorder.record(timestamp: 1.032)
        recorder.noteResumed()

        // Forty seconds later, the app is frontmost again.
        recorder.record(timestamp: 41.000)
        recorder.record(timestamp: 41.016)

        let stats = try #require(recorder.stop())
        #expect(stats.frameCount == 2, "the frames on either side of the gap, and not the gap")
        #expect(stats.worst < 20, "a 40-second interval means the gap was measured as a frame")
    }

    /// And the capture says so, because a silently-clean interruption is the other half of
    /// the bug: the tester needs to know to discard it rather than to read it.
    @Test("an interrupted capture is flagged as interrupted")
    func anInterruptedCaptureIsFlaggedAsInterrupted() {
        let recorder = FrameTimeRecorder()
        recorder.start()
        recorder.record(timestamp: 1.000)
        recorder.noteSuspended()
        recorder.noteResumed()
        _ = recorder.stop()

        #expect(recorder.wasInterrupted)
    }

    /// A fresh capture is not still wearing the last one's interruption.
    @Test("starting a capture clears the previous interruption")
    func startingACaptureClearsThePreviousInterruption() {
        let recorder = FrameTimeRecorder()
        recorder.start()
        recorder.noteSuspended()
        _ = recorder.stop()
        #expect(recorder.wasInterrupted)

        recorder.start()
        #expect(!recorder.wasInterrupted)
    }

    /// Scene-phase changes outside a capture are not an interruption of anything.
    @Test("backgrounding between captures flags nothing")
    func backgroundingBetweenCapturesFlagsNothing() {
        let recorder = FrameTimeRecorder()
        recorder.noteSuspended()
        recorder.noteResumed()

        #expect(!recorder.wasInterrupted)
    }

    /// **I2: `stop()` is idempotent and safe on a recorder that never ran.**
    ///
    /// The fix for the immortal display link routes `onDisappear` into `stop()`, which fires
    /// on every teardown of the readout — including ones where no capture was running. It
    /// must not resurrect a published result or trap.
    @Test("stopping a recorder that never recorded is harmless")
    func stoppingARecorderThatNeverRecordedIsHarmless() {
        let recorder = FrameTimeRecorder()
        #expect(recorder.stop() == nil)
        #expect(!recorder.isRecording)
        #expect(recorder.statistics == nil)
    }

    /// **Codex round 1, finding 2: `start()` while the app is already inactive.**
    ///
    /// The suspend logic records scene *transitions*, and both are no-ops outside a capture.
    /// So `noteSuspended()` before `start()` was dropped, `start()` asserted "active", the
    /// later `noteResumed()` was ignored because the recorder believed it had never been
    /// suspended, and the whole 40-second gap was appended as one frame — with
    /// `wasInterrupted` still false, i.e. an ordinary-looking FAIL rather than an
    /// INTERRUPTED one. `start(isActive:)` takes the scene's state so it cannot be
    /// mis-inferred from a transition that was never delivered.
    @Test("a capture begun while the app is inactive does not measure the gap")
    func aCaptureBegunWhileTheAppIsInactiveDoesNotMeasureTheGap() throws {
        let recorder = FrameTimeRecorder()
        recorder.noteSuspended()          // dropped: not recording yet
        recorder.start(isActive: false)   // ...so the state has to come from here
        recorder.record(timestamp: 1.000) // a callback before the link actually pauses
        recorder.noteResumed()
        recorder.record(timestamp: 41.000)
        recorder.record(timestamp: 41.016)

        let stats = try #require(recorder.stop())
        #expect(recorder.wasInterrupted, "a capture begun inactive is an interrupted capture")
        #expect(stats.frameCount == 1, "only the pair after the resume")
        #expect(stats.worst < 20, "a 40-second interval means the gap was measured as a frame")
    }

    /// The ordinary case still reports clean, so `isActive` has not made every capture
    /// interrupted by default.
    @Test("a capture begun while active is not flagged")
    func aCaptureBegunWhileActiveIsNotFlagged() {
        let recorder = FrameTimeRecorder()
        recorder.start(isActive: true)
        recorder.record(timestamp: 1.000)
        recorder.record(timestamp: 1.016)
        _ = recorder.stop()

        #expect(!recorder.wasInterrupted)
    }

    /// **Codex round 1, finding 2, second half**: a resume with no recorded suspend must
    /// still drop the stale baseline, since the resign-active transition can fail to reach a
    /// recording recorder.
    @Test("a resume with no recorded suspend still reseeds the baseline")
    func aResumeWithNoRecordedSuspendStillReseedsTheBaseline() throws {
        let recorder = FrameTimeRecorder()
        recorder.start()
        recorder.record(timestamp: 1.000)
        // No noteSuspended() — the transition never arrived.
        recorder.noteResumed()
        recorder.record(timestamp: 41.000)
        recorder.record(timestamp: 41.016)

        let stats = try #require(recorder.stop())
        #expect(stats.frameCount == 1)
        #expect(stats.worst < 20, "the stale pre-gap timestamp survived the resume")
    }

    /// Before any capture there is no draw count and no refresh rate to report, rather than a
    /// zero that would read as "no draws".
    @Test("a recorder that has never captured reports neither draws nor a rate")
    func aRecorderThatHasNeverCapturedReportsNeitherDrawsNorARate() {
        let recorder = FrameTimeRecorder()
        #expect(recorder.drawCount == nil)
        #expect(recorder.nominalFrameMilliseconds == nil)
    }

    /// The refresh rate comes from the callbacks' own frame durations, not from
    /// `CADisplayLink.duration` — which Apple documents as the *maximum*-rate period and
    /// which is undefined before the first callback (Codex round 2, finding 2).
    @Test("the reported frame duration is the one the callbacks carried")
    func theReportedFrameDurationIsTheOneTheCallbacksCarried() {
        let recorder = FrameTimeRecorder()
        recorder.start()
        #expect(recorder.nominalFrameMilliseconds == nil, "nothing has fired yet")

        // A link throttled to 30 Hz: the callbacks' own durations say so.
        for index in 0 ... 10 {
            recorder.record(timestamp: Double(index) * 0.033, frameDuration: 1.0 / 30)
        }
        #expect(recorder.nominalFrameMilliseconds == nil, "published at stop(), not per frame")
        _ = recorder.stop()

        let reported = recorder.nominalFrameMilliseconds
        #expect(reported != nil)
        #expect(abs((reported ?? 0) - 33.333) < 0.01, "a 30 Hz link must not report 60 Hz")
    }

    /// **The rate describes the whole capture, not its last frame** (Codex round 3).
    ///
    /// Publishing on every callback left the final value standing, so a capture that ran at
    /// 30 Hz throughout and happened to end on a 60 Hz frame was labelled `60Hz` — and the
    /// hand-off's rule is to discard anything that does not say 60. The median of the reported
    /// durations cannot be swung by one frame. (Assigning per callback was also an observable
    /// write per frame, which is the cost I3 removed; `nil` until `stop()` is what proves it.)
    @Test("one fast frame at the end does not relabel a slow capture")
    func oneFastFrameAtTheEndDoesNotRelabelASlowCapture() {
        let recorder = FrameTimeRecorder()
        recorder.start()
        for index in 0 ..< 300 {
            recorder.record(timestamp: Double(index) * 0.033, frameDuration: 1.0 / 30)
        }
        recorder.record(timestamp: 300 * 0.033, frameDuration: 1.0 / 60)
        _ = recorder.stop()

        let reported = recorder.nominalFrameMilliseconds ?? 0
        #expect(abs(reported - 33.333) < 0.01, "reported \(reported) ms — the last frame won")
    }

    /// **The even-count case, which is where the hand-rolled median was wrong** (Codex round
    /// 4). `sorted[count / 2]` picks the *upper* middle on an even count: 400 samples at
    /// 8.33 ms and 400 at 16.67 ms reported 16.67 ms — 60 Hz — where this file's own
    /// nearest-rank rule gives the lower middle, 8.33 ms. Both existing tests used odd counts,
    /// so the path was untested. The rate now comes from `FrameTimeStatistics`, so there is
    /// one median implementation rather than two that disagree.
    @Test("the reported rate uses nearest-rank on an even number of samples")
    func theReportedRateUsesNearestRankOnAnEvenNumberOfSamples() {
        let recorder = FrameTimeRecorder()
        recorder.start()
        for index in 0 ..< 400 {
            recorder.record(timestamp: Double(index) * 0.0083, frameDuration: 1.0 / 120)
        }
        for index in 400 ..< 800 {
            recorder.record(timestamp: Double(index) * 0.0083, frameDuration: 1.0 / 60)
        }
        _ = recorder.stop()

        let reported = recorder.nominalFrameMilliseconds ?? 0
        #expect(abs(reported - 8.333) < 0.01, "reported \(reported) ms — the upper middle won")
    }
}
