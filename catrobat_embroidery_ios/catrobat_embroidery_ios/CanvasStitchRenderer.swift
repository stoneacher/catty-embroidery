import EmbroideryEngine
import StagePreview
import SwiftUI

/// ADR-009 in code: a SwiftUI `Canvas`, batched paths, and a cached raster for the
/// settled prefix.
///
/// It holds **no batching logic of its own** — `StitchDrawPlan` decides what to stroke
/// and this only strokes it. That split is what makes the grouping, the per-path styles
/// and the dot rule provable under `swift test` with no simulator, and it is why a
/// future `MetalStitchRenderer` inherits the batching for free instead of
/// reimplementing it.
struct CanvasStitchRenderer: StagePreviewRenderer {
    func makeBody(
        display: StitchDisplayList,
        transform: StageRenderTransform,
        needle: PreviewNeedle?,
        viewport: ViewSize
    ) -> some View {
        // **The needle is a sibling layer, not a branch inside `CanvasStitchLayers`, and
        // that is what protects ADR-009's cache structurally rather than by comment.**
        // The pose changes every frame; if it could reach `BakeKey` the settled raster
        // would re-bake per frame and the cache would be worse than no cache at all.
        // `CanvasStitchLayers` has no `needle` property, so no bake key field *can*
        // depend on one — the requirement is unrepresentable instead of merely avoided.
        //
        // ADR-024's own review is the cautionary precedent: its Increase Contrast claim
        // was documented in `StageChrome` and in the ADR while the code did the opposite,
        // precisely because it rested on a comment.
        //
        // Cost, stated rather than hidden: one extra full-viewport compositing layer per
        // frame, for US-309 to measure. `PreviewNeedle` is `Hashable`, so a tick that
        // only stitches leaves this layer's inputs equal and SwiftUI can skip it.
        ZStack {
            CanvasStitchLayers(display: display, transform: transform, viewport: viewport)
            NeedleLayer(needle: needle, transform: transform.current)
        }
    }
}

/// The needle: drawn every frame, never baked.
///
/// Two inks rather than one, and the halo is load-bearing rather than decorative. The
/// needle sits *on top of the design*, so the binding constraint is not the two stage
/// fields — it is every possible thread colour. Measured: `needleCore` alone clears the
/// paper at 6.97:1 and the mat at 5.18:1, but it is only 2.10:1 against black, which is
/// `ColorState`'s default and therefore the app's commonest thread. With the white halo
/// the pair spans the whole luminance range and the **worst background anywhere in it**
/// still clears 3.17:1 against one of the two inks. That is a proved bound over the
/// colour space, not a spot check, and it is what makes the halo non-optional.
private struct NeedleLayer: View {
    let needle: PreviewNeedle?
    let transform: StageTransform

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, _ in
            guard let needle,
                  let outline = NeedleGlyph.outline(
                      at: transform.viewPoint(of: needle.update.position),
                      heading: needle.update.heading
                  )
            else { return }

            var path = Path()
            path.addLines(outline.map { CGPoint(x: $0.x, y: $0.y) })
            path.closeSubpath()

            // Halo first, stroked *centred* on the outline, so the fill covers its inner
            // half and exactly `haloWidth / 2` survives outside the silhouette. One path,
            // two draws — no second geometry that could drift from the first.
            context.stroke(
                path,
                with: .color(StageChrome.needleHalo),
                style: StrokeStyle(
                    lineWidth: contrast == .increased
                        ? NeedleGlyph.increasedContrastHaloWidth
                        : NeedleGlyph.haloWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            context.fill(path, with: .color(StageChrome.needleCore))
        }
        // **This is how "must not be announced continuously by VoiceOver" is satisfied:
        // by there being nothing to announce.** A `Canvas` has no child views, and the
        // stage already exposes itself as a single element with a *static* label.
        //
        // US-307 owns the real summary and must not undo this: an `accessibilityValue`
        // keyed on the pose would be re-read on every frame, which is exactly the
        // continuous announcement the criterion forbids.
        .accessibilityHidden(true)
        // Without this the sibling layer sits above the stitch canvas and swallows
        // US-307's pinch and pan.
        .allowsHitTesting(false)
    }
}

/// The two-layer draw: a cached raster for everything below the watermark, the live tail
/// on top, per frame.
private struct CanvasStitchLayers: View {
    let display: StitchDisplayList
    let transform: StageRenderTransform
    let viewport: ViewSize

    /// Below this many settled stitches, baking costs more than it saves — one bake plus
    /// one blit per frame against simply stroking the whole plan, which at these counts
    /// is already well under a frame.
    ///
    /// **A starting value, not a measured one.** US-309 tunes it by measurement against
    /// the 50 000-stitch exit criterion; naming it here is what gives that story
    /// something to turn.
    private static let bakingThreshold = 2000

    /// Read here rather than in `StageChrome`, because it is a *drawing input*: it changes
    /// what the travel stroke looks like, so it has to reach the stroking function and it
    /// has to be part of the bake key.
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var baked: Baked?

    /// Travel at full opacity under Increase Contrast, per ADR-024.
    ///
    /// This was **documented in `StageChrome` and recorded in ADR-024 before any code
    /// asked for it** — the renderer strokes travel unconditionally at 0.6
    /// (`swift-code-reviewer`, US-305). An ADR asserting behaviour with nothing behind it
    /// is worse than a missing feature in a repo whose house style is to retract
    /// overclaiming comments explicitly, so the code now matches the claim.
    private var travelOpacity: Double {
        contrast == .increased ? 1 : StageChrome.travelOpacity
    }

    /// What a cached raster is only valid for.
    ///
    /// **The colour scheme is deliberately absent**, and that is a real payoff of the
    /// dark-mode criterion rather than an oversight: because thread colours are design
    /// data and the stage field is fixed, nothing inside the canvas changes when the
    /// user switches appearance, so the raster survives it.
    private struct BakeKey: Hashable {
        let settledCount: Int

        /// **Not redundant with `settledCount`.** `reset()` breaks the append-only premise
        /// the count relies on: afterwards the same count describes different pixels, so a
        /// US-306 driver switching designs and re-settling to the same watermark would hit
        /// a matching key and composite the *previous* design's raster under the new
        /// design's live tail. The fitted transform cannot break that tie, because ADR-024
        /// records as a benefit that it is identical for every in-hoop design.
        let resetCount: Int

        let transform: StageTransform
        let width: Double
        let height: Double

        /// The colour **scheme** is deliberately absent — nothing inside the canvas adapts
        /// to it, which is a real payoff of the dark-mode rule. Increase Contrast is a
        /// different matter: it *does* change the travel stroke, so it belongs here. The
        /// distinction is the whole reason ADR-024's "the raster survives an appearance
        /// switch" argument had to be re-checked when contrast became a drawing input.
        let increasedContrast: Bool

        /// **Whether an interaction is in flight, and it belongs in the key even though it
        /// changes nothing about the pixels.**
        ///
        /// Without it the deferred bake can be lost outright (Codex round 2). `settledCount`
        /// is part of this key, so a run advancing it during a gesture fires `onChange` while
        /// live; the bake is skipped. If the gesture then *ends at the transform it started
        /// from* — pan out and back, or pinch to 1x — the committed key equals the one already
        /// observed while live, `onChange` does not fire again, and the raster is never built:
        /// the renderer stays on the full-stroke path indefinitely, until some unrelated key
        /// input happens to change. Including liveness makes the live-to-settled edge a key
        /// change in its own right, which is exactly the moment the bake should happen.
        let isLive: Bool
    }

    private struct Baked {
        let key: BakeKey
        let image: Image
    }

    private var bakeKey: BakeKey {
        BakeKey(
            settledCount: display.settledCount,
            resetCount: display.resetCount,
            // **`bake`, never `current`.** This is the whole of "the settled raster is
            // re-rasterised on gesture end rather than per frame": while a gesture or the fit
            // animation is live, `bake` holds still, so this key does too and `onChange` does
            // not fire. Keying on `current` would rebuild the raster every frame — strictly
            // worse than having no cache at all.
            transform: transform.bake,
            width: viewport.width,
            height: viewport.height,
            increasedContrast: contrast == .increased,
            isLive: !transform.canUseRaster
        )
    }

    var body: some View {
        Canvas { context, size in
            #if DEBUG
                // US-309's answer to "did the renderer actually run during that capture?".
                // A `CADisplayLink` callback fires on every display refresh whether or not this
                // closure ran, so on a settled, static stage a capture can report a flawless
                // 60 fps while SwiftUI redraws nothing at all — the frame times would describe
                // the display, not the renderer (Codex round 1, finding 1). Counting draws here
                // makes that visible instead of invisible: a capture whose draw count is ~0 is
                // measuring nothing about ADR-009. One integer increment, no observation, so it
                // cannot perturb the frame it is counting.
                StageDrawCounter.record()
            #endif
            // The raster was rendered at `viewport` and is blitted into `size`, so a
            // mismatch would *stretch* the settled layer while the live tail stays
            // unstretched — a visibly misplaced seam. Today they are equal because this
            // view fills the `GeometryReader` that measured the viewport, but nothing in
            // the type system says so, and a future caller framing the renderer smaller
            // would get the seam with no test able to see it. Falling back to `.entire`
            // makes the assumption self-enforcing (`swift-code-reviewer`, US-305).
            // `canUseRaster` is false while a gesture or the fit animation is in flight: the
            // raster's pixels were baked at `bake`, so compositing them under a tail stroked
            // at `current` would misplace them. Stroking everything is correct at any
            // transform and is what makes the frame able to *reveal* content the previous
            // frame had off-screen — the thing moving an already-rendered layer cannot do.
            //
            // **Which window is a package decision, not a decision here** (US-310). This used to
            // be an `if/else` choosing `.live` or `.entire`, which conflated two different
            // questions: "may the raster be composited?" and "is an interaction in flight?".
            // They come apart exactly where it matters — a settled stage with no usable raster
            // (too short to bake, stale key, wrong size) took the same branch as a live gesture
            // and would have paid the same fidelity cost for nothing. `forFrame` asks
            // `canUseRaster` for the second question and takes this conjunction only as the
            // answer to the first, and it does so where `swift test` can see it (ADR-023).
            let compositingRaster = transform.canUseRaster
                && baked?.key == bakeKey
                && Self.matches(size, viewport)
            if compositingRaster, let baked {
                context.draw(baked.image, in: CGRect(origin: .zero, size: size))
            }
            CanvasStitchStroke.stroke(
                .forFrame(of: display, at: transform, compositingRaster: compositingRaster),
                of: display.stitches,
                transform: transform.current,
                travelOpacity: travelOpacity,
                into: &context
            )
        }
        .onChange(of: bakeKey, initial: true) { rebakeIfWorthwhile() }
    }

    /// Whether the `Canvas`'s own size is the viewport the raster was rendered at.
    private static func matches(_ size: CGSize, _ viewport: ViewSize) -> Bool {
        size.width == viewport.width && size.height == viewport.height
    }

    /// Bakes the settled prefix, or throws the raster away if there is not enough of it
    /// to be worth one.
    private func rebakeIfWorthwhile() {
        // **Deferred while a gesture or the fit animation is in flight**, even though the key
        // changed. `settledCount` is part of the key and a *run* advances it, so a pan held
        // while the design is still stitching would rasterise the settled prefix mid-gesture —
        // work whose result cannot even be composited until the gesture ends, spent at the one
        // moment the frame budget is tightest (Codex round 1). ADR-028's policy is that the
        // raster stays still until commit; this is what makes that true rather than
        // true-of-the-transform-only.
        //
        // Nothing is lost by waiting: the key still differs at commit, so `onChange` fires
        // again and the bake happens then.
        guard transform.canUseRaster else { return }

        let settled = display.settledCount
        guard settled >= Self.bakingThreshold else {
            baked = nil
            return
        }

        // Baked at `bake`, which is where the key says it is. During a gesture this branch
        // is not reached at all, because the key has not changed.
        let bakeTransform = transform.bake
        let plan = StitchDrawPlan.settled(of: display)
        // `Array(prefix)`, an **explicit copy**, and not `display.stitches` or a slice of
        // it. The renderer closure escapes and outlives this call, so capturing the
        // list's own storage would leave it non-uniquely referenced for the raster's
        // whole lifetime and turn every subsequent append into a full buffer copy —
        // ADR-021 measured that and calls the explicit copy the *cheaper* option, not
        // the more expensive one.
        let settledPoints = Array(display.stitches[..<settled])
        let travelOpacity = travelOpacity
        let size = CGSize(width: viewport.width, height: viewport.height)

        baked = Baked(
            key: bakeKey,
            image: Image(size: size) { context in
                CanvasStitchStroke.stroke(
                    plan,
                    of: settledPoints,
                    transform: bakeTransform,
                    travelOpacity: travelOpacity,
                    into: &context
                )
            }
        )
    }
}
