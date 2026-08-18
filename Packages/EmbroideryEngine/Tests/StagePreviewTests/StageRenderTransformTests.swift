import StagePreview
import Testing

/// The two-transform split that lets a frame be re-stroked at the live transform while the
/// settled raster stays keyed on the committed one.
///
/// **Regression cover for a defect found in the running app, not by a test.** The first
/// version of this story moved the already-rendered canvas with `.scaleEffect`/`.offset`,
/// which keeps the bake key still — but a `Canvas` rasterises only its own bounds, so content
/// that had been panned off-screen was never drawn and sliding the layer back showed blank
/// space until the gesture ended. Redrawing at `current` is what fixes it; keeping the key on
/// `bake` is what stops that costing a rasterisation per frame.
@Suite("Stage render transform")
struct StageRenderTransformTests {
    private static let fit = StageTransform.fitting(
        StageGeometry.box, in: ViewSize(width: 390, height: 500)
    )
    private static let zoomed = StageTransform(scale: 3, translation: ViewPoint(x: 10, y: 20))

    @Test("a settled stage draws and bakes with the same transform")
    func settledUsesOneTransform() {
        let render = StageRenderTransform.settled(Self.fit)

        #expect(render.bake == Self.fit)
        #expect(render.current == Self.fit)
        #expect(render.canUseRaster)
    }

    /// **The property the whole split exists for**: while live, what the frame draws with and
    /// what the raster is keyed on are different, and the key is the *committed* one — so a
    /// gesture cannot invalidate the cache however far it moves.
    @Test("a live stage draws at current while the bake key stays on the committed transform")
    func liveSeparatesDrawingFromBaking() {
        let render = StageRenderTransform.live(bake: Self.fit, current: Self.zoomed)

        #expect(render.current == Self.zoomed)
        #expect(render.bake == Self.fit)
        #expect(render.bake != render.current, "otherwise this pins nothing")
    }

    /// The raster's pixels were baked at `bake`; compositing them under a tail stroked at
    /// `current` would misplace them, so a live frame strokes everything instead. That is also
    /// what makes the frame able to reveal content the previous frame had off-screen.
    @Test("a live stage refuses the cached raster")
    func liveRefusesTheRaster() {
        #expect(!StageRenderTransform.live(bake: Self.fit, current: Self.zoomed).canUseRaster)
        // Even when the two happen to coincide: the caller decides what is live, and a frame
        // that says it is mid-gesture must not silently start reusing pixels.
        #expect(!StageRenderTransform.live(bake: Self.fit, current: Self.fit).canUseRaster)
    }

    /// `Hashable`, because the bake key is compared per frame and the renderer's `onChange`
    /// depends on equality being cheap and exact.
    @Test("two render transforms with the same pair are equal")
    func equalityIsByValue() {
        #expect(
            StageRenderTransform.live(bake: Self.fit, current: Self.zoomed)
                == StageRenderTransform.live(bake: Self.fit, current: Self.zoomed)
        )
        #expect(StageRenderTransform.settled(Self.fit) != .live(bake: Self.fit, current: Self.fit))
    }
}

/// `StageTransform.interpolated(to:progress:)` — what makes the fit animation re-stroke rather
/// than slide a stale layer.
@Suite("Transform interpolation")
struct TransformInterpolationTests {
    private static let from = StageTransform(scale: 4, translation: ViewPoint(x: 100, y: -40))
    private static let to = StageTransform(scale: 1, translation: ViewPoint(x: -20, y: 60))

    /// The endpoints are **exact**, which a `log`/`exp` blend would not guarantee: the
    /// animation ends by swapping to the real transform, and a final frame a hair off it would
    /// show as a one-pixel jump at completion.
    @Test("progress 0 and 1 are the endpoints exactly")
    func endpointsAreExact() {
        #expect(Self.from.interpolated(to: Self.to, progress: 0) == Self.from)
        #expect(Self.from.interpolated(to: Self.to, progress: 1) == Self.to)
    }

    @Test("the midpoint is halfway on every field")
    func theMidpointIsHalfway() {
        let middle = Self.from.interpolated(to: Self.to, progress: 0.5)

        #expect(abs(middle.scale - 2.5) < 1e-12)
        #expect(abs(middle.translation.x - 40) < 1e-12)
        #expect(abs(middle.translation.y - 10) < 1e-12)
    }

    /// A spring may overshoot past 1 or undershoot below 0, and SwiftUI will happily hand
    /// those in. Clamping keeps the stage inside the two transforms the user asked for rather
    /// than briefly showing a scale nobody chose.
    @Test("progress outside zero and one is clamped to the endpoints")
    func progressIsClamped() {
        #expect(Self.from.interpolated(to: Self.to, progress: -0.4) == Self.from)
        #expect(Self.from.interpolated(to: Self.to, progress: 1.8) == Self.to)
    }

    /// Total for a NaN progress, which resolves to the destination — the animation's own end
    /// state, so a poisoned frame settles where it was going rather than where it started.
    @Test("a NaN progress resolves to the destination")
    func nanResolvesToTheDestination() {
        #expect(Self.from.interpolated(to: Self.to, progress: .nan) == Self.to)
    }

    /// Every step is a real, usable transform — the `init` chokepoint sees each one, so the
    /// animation cannot produce a frame the renderer would have to defend against.
    @Test("every step of an interpolation is finite and in range")
    func everyStepIsUsable() {
        for step in 0 ... 20 {
            let transform = Self.from.interpolated(to: Self.to, progress: Double(step) / 20)

            #expect(transform.scale.isFinite)
            #expect(transform.scale >= StageTransform.minimumRepresentableScale)
            #expect(transform.translation.x.isFinite)
            #expect(transform.translation.y.isFinite)
        }
    }
}
