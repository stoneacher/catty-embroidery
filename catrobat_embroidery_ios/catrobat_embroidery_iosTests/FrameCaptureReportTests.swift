@testable import catrobat_embroidery_ios
import CoreGraphics
import Foundation
import Testing

/// US-316's report: the capsule's caption, moved out of the view so the console prints the
/// **same text** the screen shows, plus what an unattended capture needs (brief D5).
struct FrameCaptureReportTests {
    /// Four intervals, one of them 50 ms; two drawn, the slow one among them.
    private static let all = FrameTimeStatistics(millisecondsPerFrame: [16.667, 16.667, 50.008, 16.667])
    private static let drawn = FrameTimeStatistics(
        millisecondsPerFrame: [50.008, 16.667],
        startOffsetsMilliseconds: [33.334, 83.342]
    )

    private static let failing = FrameCaptureReport(
        all: all, drawn: drawn, totalDraws: 2, unmeasuredDraws: 0,
        wasInterrupted: false, commits: 1, nominalFrameMilliseconds: 16.667
    )

    /// The exact text `FrameTimeReadout` printed before this slice, for the same state: the
    /// capsule must not change, and the console must say the same thing.
    @Test("the caption is the capsule's text, character for character")
    func captionIsUnchanged() {
        #expect(Self.failing.caption
            == "n=4 drawn=2 commits=1 60Hz med 16.667 p95 50.008 p99 50.008 max 50.008@0.0s · 0.1 s · FAIL (short)")
    }

    @Test("no capture, no caption")
    func noCaption() {
        let report = FrameCaptureReport(
            all: nil, drawn: nil, totalDraws: 0, unmeasuredDraws: 0,
            wasInterrupted: false, commits: 0, nominalFrameMilliseconds: nil
        )
        #expect(report.caption == nil)
    }

    /// Without a measured rate the `Hz` field is left out, as the capsule always did; and with
    /// nothing drawn the quantiles fall back to the whole capture.
    @Test("an undrawn capture quotes every frame and no rate")
    func undrawn() {
        let report = FrameCaptureReport(
            all: Self.all, drawn: nil, totalDraws: 0, unmeasuredDraws: 0,
            wasInterrupted: false, commits: 0, nominalFrameMilliseconds: nil
        )
        let expected = "n=4 drawn=0 commits=0 med 16.667 p95 50.008 p99 50.008 max 50.008@0.0s · 0.1 s · "
            + "NO DRAWS — measures the display, not the renderer"
        #expect(report.caption == expected)
    }

    /// The console line: tag, condition, the capsule's caption, every **drawn** frame over the
    /// bar with its offset, then the run's conditions.
    @Test("the console line carries the caption and the run's conditions")
    func consoleLine() {
        let context = FrameCaptureReport.Context(
            condition: .compact,
            thermalAtStart: .nominal,
            thermalAtEnd: .fair,
            scale: 0.74,
            threadWidth: 2.331,
            canvasSize: CGSize(width: 370, height: 257),
            viewport: CGSize(width: 370, height: 256.833),
            raster: .notComposited
        )
        #expect(Self.failing.consoleLine(context)
            == "US316 condition=B n=4 drawn=2 commits=1 60Hz med 16.667 p95 50.008 p99 50.008 "
            + "max 50.008@0.0s · 0.1 s · FAIL (short)"
            + " | over33=[0.033s:50.008] thermal=nominal>fair scale=0.740 width=2.331"
            + " canvas=370.00x257.00 viewport=370.00x256.83 raster=no")
    }

    /// A frame over the bar that the canvas did **not** draw is the display's, not the
    /// renderer's, and does not belong in the list (the same reason the quantiles are the
    /// drawn frames').
    @Test("only drawn frames are listed as over the bar")
    func overBarIsDrawnOnly() {
        let undrawnSlow = FrameCaptureReport(
            all: Self.all,
            drawn: FrameTimeStatistics(millisecondsPerFrame: [16.667], startOffsetsMilliseconds: [0]),
            totalDraws: 1, unmeasuredDraws: 0, wasInterrupted: false, commits: 0,
            nominalFrameMilliseconds: 16.667
        )
        #expect(undrawnSlow.consoleLine(.bare(.baseline)).contains("over33=[]"))
    }

    /// Unknown fields print as `n/a` rather than as a zero that reads like a measurement.
    @Test("fields the run could not observe are marked, not zeroed")
    func unknownFields() {
        let line = Self.failing.consoleLine(.bare(.noDots))
        #expect(line.hasPrefix("US316 condition=D "))
        #expect(line.hasSuffix("canvas=n/a viewport=n/a raster=n/a"))
    }

    @Test("a capture with no frames still prints a line")
    func emptyCapture() {
        let report = FrameCaptureReport(
            all: nil, drawn: nil, totalDraws: 0, unmeasuredDraws: 0,
            wasInterrupted: false, commits: 0, nominalFrameMilliseconds: nil
        )
        #expect(report.consoleLine(.bare(.baseline)).hasPrefix("US316 condition=A0 no frames | over33=[]"))
    }
}

extension FrameCaptureReport.Context {
    /// A context with nothing observed beyond the condition.
    static func bare(_ condition: CaptureCondition) -> Self {
        Self(
            condition: condition, thermalAtStart: .nominal, thermalAtEnd: .nominal,
            scale: 1, threadWidth: 3.15, canvasSize: nil, viewport: nil, raster: .unobserved
        )
    }
}
