@testable import catrobat_embroidery_ios
import CoreGraphics
import StagePreview
import Testing

/// US-316's renderer controls (brief D1, conditions D and E) and the settled-frame record
/// (US-322's fields, D5).
///
/// Each control suppresses one half of a **live** frame and nothing else: a settled frame —
/// and the bake behind it — is always drawn whole, so the controls cannot change what a
/// capture's pre-roll or settle costs.
@MainActor
struct LiveDrawControlTests {
    @Test("without a control every frame draws thread and dots", arguments: [true, false])
    func noControl(_ isLive: Bool) {
        #expect(LiveDrawControl.none.layers(isLive: isLive) == .all)
    }

    @Test("the dot control drops the dots from live frames only")
    func noDots() {
        #expect(LiveDrawControl.noDots.layers(isLive: true) == .init(thread: true, dots: false))
        #expect(LiveDrawControl.noDots.layers(isLive: false) == .all)
    }

    @Test("the thread control drops the thread from live frames only")
    func noThread() {
        #expect(LiveDrawControl.noThread.layers(isLive: true) == .init(thread: false, dots: true))
        #expect(LiveDrawControl.noThread.layers(isLive: false) == .all)
    }

    /// The order a frame draws its halves in, as the `Canvas` body runs it: **the thread, then
    /// the dots, always** — dots sit on top of every stroke (ADR-043) — and a control removes
    /// its half without reordering the other (Codex slice-4 review, finding 3).
    @Test("a frame draws the thread before the dots, and a control only removes its half")
    func drawOrder() {
        #expect(CanvasStitchStroke.operations(for: .all) == [.thread, .dots])
        #expect(CanvasStitchStroke.operations(for: LiveDrawControl.noDots.layers(isLive: true)) == [.thread])
        #expect(CanvasStitchStroke.operations(for: LiveDrawControl.noThread.layers(isLive: true)) == [.dots])
        #expect(CanvasStitchStroke.operations(for: LiveDrawControl.noThread.layers(isLive: false)) == [.thread, .dots])
    }

    /// The process's control comes from its launch argument, and an ordinary launch has none.
    @Test("the control is read from the launch arguments")
    func fromArguments() {
        #expect(LiveDrawControl.from(arguments: ["app"]) == .none)
        #expect(LiveDrawControl.from(arguments: ["app", "-US316Capture", "D"]) == .noDots)
        #expect(LiveDrawControl.from(arguments: ["app", "-US316Capture", "E"]) == .noThread)
        #expect(LiveDrawControl.from(arguments: ["app", "-US316Capture", "B"]) == .none)
    }

    /// US-322's fields: the `Canvas`'s own size and the viewport are recorded **separately**,
    /// so a fractional viewport shows up as two different numbers rather than one.
    @Test("a settled draw records the canvas size, the viewport and the raster")
    func settledRecord() {
        let record = StageDrawRecord(
            canvasSize: CGSize(width: 370, height: 257),
            viewport: ViewSize(width: 370, height: 256.833),
            rasterComposited: false
        )
        #expect(record.canvasSize == CGSize(width: 370, height: 257))
        #expect(record.viewportSize == CGSize(width: 370, height: 256.833))
        #expect(record.raster == .notComposited)
        #expect(StageDrawRecord(
            canvasSize: .zero, viewport: ViewSize(width: 1, height: 1), rasterComposited: true
        ).raster == .composited)
    }
}
