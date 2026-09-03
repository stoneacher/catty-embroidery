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
    /// **One stroking function for both layers, and that is the point.**
    ///
    /// `Image(size:renderer:)` (iOS 16+) and `Canvas` both hand out an
    /// `inout GraphicsContext`, so the settled pixels and the live pixels can be
    /// produced by identical code. If they were not, the seam at the watermark would
    /// differ in cap shape, width rounding or alpha, and no unit test would notice — a
    /// human would, on a screenshot, eventually.
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
        for stroke in plan.strokes {
            let path = segmentPath(stroke.segments, of: points, transform: transform)
            switch stroke.style {
            case .thread:
                context.stroke(
                    path,
                    with: .color(Color(stroke.color)),
                    style: StrokeStyle(
                        lineWidth: StitchDrawMetrics.threadWidth(atScale: transform.scale),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            case .traversal:
                context.stroke(
                    path,
                    with: .color(StageChrome.travelLine.opacity(travelOpacity)),
                    style: StrokeStyle(
                        lineWidth: StitchDrawMetrics.traversalWidthInViewPoints,
                        lineCap: .butt,
                        dash: StageChrome.travelDash
                    )
                )
            case .suppressed:
                continue // never planned; the switch is exhaustive so a new style is a compile error
            }
        }

        // After every stroke, so dots always sit on top — a deviation from Catroid,
        // which interleaves them in stitch order and lets a later run cover an earlier
        // run's penetration points.
        let radius = StitchDrawMetrics.dotRadius(atScale: transform.scale)
        for run in plan.dots {
            var path = Path()
            // `dottedIndices`, never `indices`: a coarse run dots every `stride`-th entry, and
            // iterating the raw range would silently draw all of them — the one place this
            // story's saving on the dot half could be lost without any test noticing, since
            // every plan-level assertion would still pass.
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
            context.fill(path, with: .color(Color(run.color)))
        }
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
