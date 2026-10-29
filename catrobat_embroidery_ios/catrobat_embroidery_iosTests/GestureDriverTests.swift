@testable import catrobat_embroidery_ios
import CoreGraphics
import StagePreview
import Testing

/// US-316's scripted gesture, driven through the **real** `Coordinator` (brief D4).
///
/// What these pin is the coordinator path, and only that: from the action methods down the
/// driver's gesture is a finger's — live throughout, no commit while it is held, exactly one
/// commit when it ends. What a finger adds above the action methods (touch delivery, the
/// recognisers' own state machines) is not a test claim; it is the calibration's question (D7).
@MainActor
struct GestureDriverTests {
    private static let frame = 1.0 / 60.0

    @Test("a scripted gesture is live while held and commits once, at its end",
          arguments: [GestureScript.Kind.pan, .mixed])
    func liveThenOneCommit(_ kind: GestureScript.Kind) {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let driver = GestureDriver(
            coordinator: wiring.coordinator,
            script: GestureScript(kind: kind),
            viewport: CatcherHarness.viewport
        )

        driver.begin()
        for step in 1 ... 120 {
            driver.advance(to: Double(step) * Self.frame)
            #expect(recording.manipulation.isLive, "not live at step \(step)")
            #expect(recording.manipulation.gesture(in: CatcherHarness.viewport) != nil)
        }
        #expect(recording.commits == 0)

        driver.end()
        #expect(recording.commits == 1)
        #expect(!recording.manipulation.isLive)
    }

    /// The live frame actually moves with the script: the transform it would draw at follows
    /// the pan, so every frame of the capture is a redraw.
    @Test("the live transform follows the script")
    func liveTransformFollows() throws {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let script = GestureScript(kind: .pan)
        let driver = GestureDriver(coordinator: wiring.coordinator, script: script, viewport: CatcherHarness.viewport)

        driver.begin()
        driver.advance(to: 0.5)
        let gesture = try #require(recording.manipulation.gesture(in: CatcherHarness.viewport))
        let moved = recording.interaction.transform(
            with: gesture, fitting: CatcherHarness.fit, in: CatcherHarness.viewport
        )
        let expected = script.translation(at: 0.5)
        #expect(abs(moved.translation.x - CatcherHarness.fit.translation.x - expected.x) < 1e-6)
        #expect(abs(moved.translation.y - CatcherHarness.fit.translation.y - expected.y) < 1e-6)
        #expect(moved.scale == CatcherHarness.fit.scale)
    }

    /// Condition C's pre-step: one pinch to a fraction of the fit, released, so it commits once
    /// and the capture then starts from a settled, zoomed-out stage.
    @Test("the zoom step commits once and lands at the requested fraction of the fit")
    func zoomCommitsOnce() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let driver = GestureDriver(
            coordinator: wiring.coordinator,
            script: GestureScript(kind: .pan),
            viewport: CatcherHarness.viewport
        )

        driver.zoom(to: 0.3)

        #expect(recording.commits == 1)
        #expect(!recording.manipulation.isLive)
        let settled = recording.interaction.transform(
            with: nil, fitting: CatcherHarness.fit, in: CatcherHarness.viewport
        )
        #expect(abs(settled.scale - CatcherHarness.fit.scale * 0.3) < 1e-9)
    }
}
