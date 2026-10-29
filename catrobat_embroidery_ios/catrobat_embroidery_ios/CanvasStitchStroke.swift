import StagePreview
import SwiftUI

/// The plan-to-pixels half of the stage renderer: everything that turns a `StitchDrawPlan` into
/// strokes and fills, with no state of its own.
///
/// **The extraction was forced rather than chosen**, the same way US-307's was:
/// `CanvasStitchRenderer.swift` crossed SwiftLint's hard 400-line limit (CI runs `--strict`) when
/// US-310 documented why a segment now carries both its endpoints. The seam it exposed is a real
/// one, though — everything here is a pure function of (plan, points, transform), while
/// everything left behind is about *when* to draw and what to cache — so the split is worth
/// keeping rather than reverting once the line budget allows.
///
/// A namespace rather than free functions, so `stroke` and `segmentPath` cannot collide with
/// anything else in the app module, and internal rather than `private` because the type that
/// used to hold them is itself `private` to its file.
enum CanvasStitchStroke {
    /// Which halves of a frame are drawn: the thread (and travel), the dots, or both. Always
    /// both, except under US-316's DEBUG live controls (`LiveDrawControl`).
    struct Layers: Equatable {
        let thread: Bool
        let dots: Bool

        static let all = Layers(thread: true, dots: true)
    }

    /// One half of a frame, in the order it is drawn.
    enum Operation: Equatable {
        case thread
        case dots
    }

    /// What a frame draws, **in order**: the thread, then the dots — so dots sit on top of every
    /// stroke — minus whatever `layers` leaves out. `stroke` and the live `Canvas` both draw
    /// through this, so the order has one definition.
    static func operations(for layers: Layers) -> [Operation] {
        var operations: [Operation] = []
        if layers.thread {
            operations.append(.thread)
        }
        if layers.dots {
            operations.append(.dots)
        }
        return operations
    }

    /// Draws the operations `layers` allows, in `operations(for:)` order.
    static func draw(
        _ plan: StitchDrawPlan,
        of points: [PreviewStitch],
        transform: StageTransform,
        style: (travelOpacity: Double, layers: Layers),
        into context: inout GraphicsContext
    ) {
        // **The shipping path, kept direct** (Codex, PR #83 round 1): every frame of a build
        // without US-316's DEBUG controls, and every bake, draws both halves — the thread, then
        // the dots — with no operation list built per frame. The list below only serves the
        // controls, and `operations(for: .all)` is pinned to this same order.
        if style.layers == .all {
            strokeThread(plan, of: points, transform: transform, travelOpacity: style.travelOpacity, into: &context)
            fillDots(plan, of: points, transform: transform, into: &context)
            return
        }
        for operation in operations(for: style.layers) {
            switch operation {
            case .thread:
                strokeThread(plan, of: points, transform: transform, travelOpacity: style.travelOpacity, into: &context)
            case .dots:
                fillDots(plan, of: points, transform: transform, into: &context)
            }
        }
    }

    /// **One stroking function for both layers, and that is the point.**
    ///
    /// `Image(size:renderer:)` (iOS 16+) and `Canvas` both hand out an
    /// `inout GraphicsContext`, so the settled pixels and the live pixels can be
    /// produced by identical code. If they were not, the seam at the watermark would
    /// differ in cap shape, width rounding or alpha, and no unit test would notice — a
    /// human would, on a screenshot, eventually. The bake calls this; the live `Canvas` calls
    /// `draw` directly so US-316's DEBUG controls can pass their `Layers`, and this is `draw`
    /// with every layer — one code path either way.
    ///
    /// `points` is passed rather than read from the display list because the settled
    /// bake strokes a *copy* of the prefix; the plan's indices are valid against either.
    static func stroke(
        _ plan: StitchDrawPlan,
        of points: [PreviewStitch],
        transform: StageTransform,
        travelOpacity: Double,
        into context: inout GraphicsContext
    ) {
        draw(plan, of: points, transform: transform, style: (travelOpacity, .all), into: &context)
    }

    /// The plan's dots, as one fill per colour run.
    ///
    /// After every stroke, so dots always sit on top — a deviation from Catroid, which
    /// interleaves them in stitch order and lets a later run cover an earlier run's penetration
    /// points. Separate from `strokeThread` so US-316's DEBUG live controls can draw one half
    /// (`Layers`); `stroke` draws both, in this order.
    static func fillDots(
        _ plan: StitchDrawPlan,
        of points: [PreviewStitch],
        transform: StageTransform,
        into context: inout GraphicsContext
    ) {
        // Building the path and submitting it are separate intervals, so a trace can tell CPU
        // path construction (rung 4's question) from the fill call (D9; Codex slice-4 review).
        for run in plan.dots {
            let path = StageSignposts.interval("dotPath") { dotPath(run, of: points, transform: transform) }
            StageSignposts.interval("fill") { context.fill(path, with: .color(Color(run.color))) }
        }
    }

    /// The plan's thread and travel strokes. See `fillDots` for why the halves are separate.
    static func strokeThread(
        _ plan: StitchDrawPlan,
        of points: [PreviewStitch],
        transform: StageTransform,
        travelOpacity: Double,
        into context: inout GraphicsContext
    ) {
        // Path construction and the stroke call are separate intervals (D9; Codex slice-4
        // review): CPU path building is rung 4's question, submission is not.
        for stroke in plan.strokes {
            let path = StageSignposts.interval("segmentPath") {
                segmentPath(stroke.segments, of: points, transform: transform)
            }
            let style: StrokeStyle
            let shading: GraphicsContext.Shading
            switch stroke.style {
            case .thread:
                shading = .color(Color(stroke.color))
                style = StrokeStyle(
                    lineWidth: StitchDrawMetrics.threadWidth(atScale: transform.scale),
                    lineCap: .round,
                    lineJoin: .round
                )
            case .traversal:
                shading = .color(StageChrome.travelLine.opacity(travelOpacity))
                style = StrokeStyle(
                    lineWidth: StitchDrawMetrics.traversalWidthInViewPoints,
                    lineCap: .butt,
                    dash: StageChrome.travelDash
                )
            case .suppressed:
                continue // never planned; the switch is exhaustive so a new style is a compile error
            }
            StageSignposts.interval("stroke") { context.stroke(path, with: shading, style: style) }
        }
    }

    /// Whether this frame may composite the cached raster underneath the plan it draws.
    ///
    /// **Extracted so it can be tested at all** (`/codex-review` round 1, finding 3). It lives in
    /// a `private` view whose `Canvas` closure only runs when hosted *and* drawn, so passing a
    /// constant here — or asking for the wrong window — left every package `forFrame` test green
    /// while a live frame went back to the measured 69.1 ms route. Three of its four clauses are
    /// about *staleness* rather than about liveness, which is exactly why `forFrame` takes this
    /// as an input and asks `canUseRaster` itself.
    ///
    /// `baked == nil` fails on `Optional.none == .some(key)`; a stale key and a `Canvas` sized
    /// differently from the size the raster was baked at each fail on their own clause. In all
    /// three the frame draws the whole design and no raster, which is what the branch this
    /// replaced did.
    ///
    /// **`bakedSize`, not the viewport** (US-322). The comparison stays exact, so the raster is
    /// never stretched; what changed is what it is compared with — the viewport aligned to the
    /// device-pixel grid (`pixelAligned`), which is the size the `Canvas` is laid out at.
    static func compositingRaster(
        canUseRaster: Bool,
        bakedKey: AnyHashable?,
        expectedKey: AnyHashable,
        size: CGSize,
        bakedSize: CGSize
    ) -> Bool {
        canUseRaster
            && bakedKey == expectedKey
            && size == bakedSize
    }

    /// The viewport as the `Canvas` will be laid out: each dimension rounded to the nearest
    /// device pixel, half a pixel rounding up (US-322).
    ///
    /// `GeometryReader` can measure a fractional pixel count — 370 × 256.833 pt is 770.5 px tall
    /// on a 3× screen — while the `Canvas` inside it is handed whole pixels, 257.0 pt. Baking at
    /// this size and comparing with it exactly is what lets the raster composite there without
    /// being stretched. A misprediction costs the cache on that layout, never a stretched frame:
    /// the comparison in `compositingRaster` is still exact.
    ///
    /// The `1e-6` keeps "half rounds up" true when `770.5 / 3 × 3` comes back as `770.4999…`.
    static func pixelAligned(_ viewport: ViewSize, scale: CGFloat) -> CGSize {
        guard scale > 0 else { return CGSize(width: viewport.width, height: viewport.height) }
        func aligned(_ points: Double) -> Double {
            (points * scale + 0.5 + 1e-6).rounded(.down) / scale
        }
        return CGSize(width: aligned(viewport.width), height: aligned(viewport.height))
    }

    /// **One** `Path` holding one colour run's penetration dots.
    ///
    /// A separate function purely so it can be *tested* (`/codex-review` round 1, finding 2):
    /// while this was a loop inside `stroke(_:of:transform:travelOpacity:into:)` its one
    /// load-bearing decision — iterate `dottedIndices`, never `indices` — was unobservable,
    /// because reaching it needs a `GraphicsContext` and therefore a hosted, drawn `Canvas`.
    /// Iterating the raw range would have built all 50 001 ellipses while every plan-level
    /// assertion stayed green, i.e. silently given back the whole dot half of US-310's saving.
    /// A `Path` can be walked in a test; a `GraphicsContext` cannot.
    static func dotPath(
        _ run: StitchDrawPlan.DotRun,
        of points: [PreviewStitch],
        transform: StageTransform
    ) -> Path {
        let radius = StitchDrawMetrics.dotRadius(atScale: transform.scale)
        var path = Path()
        // `dottedIndices`, never `indices`: a coarse run dots every `stride`-th entry.
        for index in run.dottedIndices {
            let centre = transform.viewCGPoint(of: points[index].position)
            // Skip an undrawable dot rather than adding it. See `segmentPath`.
            guard centre.isDrawable else { continue }
            path.addEllipse(
                in: CGRect(
                    x: centre.x - radius,
                    y: centre.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
        }
        return path
    }

    /// **One** `Path` holding every segment in a stroke, as disjoint subpaths.
    ///
    /// The `move`/`addLine` pair per segment is what makes this a batch rather than a
    /// shape per stitch: `Canvas` strokes the whole thing in one call. Catty's
    /// node-per-stitch scene graph is the anti-goal ADR-009 exists to forbid, and it is
    /// worth noting the accessibility consequence too — a `Canvas` has no child views,
    /// so 50 000 stitches produce *zero* accessibility elements.
    static func segmentPath(
        _ segments: [StitchDrawPlan.Segment],
        of points: [PreviewStitch],
        transform: StageTransform
    ) -> Path {
        var path = Path()
        for segment in segments {
            // Both endpoints are read from the plan. **`segment.to` is not `segment.from + 1`
            // in a coarse plan** (US-310): while an interaction is live a segment joins across
            // up to `stride` stitches, which is what turns 50 000 subpaths per frame into a few
            // thousand. In every other window the plan still hands over consecutive pairs.
            let from = transform.viewCGPoint(of: points[segment.from].position)
            let to = transform.viewCGPoint(of: points[segment.to].position)

            // **The renderer's non-finite policy, and it needs to be explicit** (Codex
            // round 2). ADR-021 divergence #5 deliberately lets a coordinate the stream
            // *rejects* into the display trace, so a position can be infinite or NaN — and
            // because this is a **batched** path, one such point does not merely misdraw
            // itself: CoreGraphics can discard the whole path, taking every good segment in
            // the colour run with it. Skipping the offending subpath keeps the rest of the
            // run on screen, which is the same "one bad stitch must not delete the design"
            // rule `StageBox.expand(toInclude:)` applies to bounds.
            guard from.isDrawable, to.isDrawable else { continue }

            path.move(to: from)
            path.addLine(to: to)
        }
        return path
    }
}
