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
    @Test("the buffer is preallocated for a full capture")
    func theBufferIsPreallocatedForAFullCapture() {
        let recorder = FrameTimeRecorder()
        recorder.start()
        #expect(recorder.reservedCapacity >= FrameTimeStatistics.quotableFrameCount)
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
        for index in 0 ... 600 {
            recorder.record(timestamp: Double(index) * 0.016)
        }
        _ = recorder.stop()

        let published = try #require(recorder.statistics)
        #expect(published.frameCount == 600)
        #expect(published.isLongEnoughToQuote)
        #expect(published.meetsSixtyFps)
        #expect(!recorder.isRecording)
    }
}
