@testable import catrobat_embroidery_ios
import EmbroideryEngine
import StagePreview
import SwiftUI
import Testing

/// The plan-to-pixel contract: what the two geometry builders actually put in a `Path`.
///
/// **This suite exists because `/codex-review` round 1 (finding 2) showed the contract had no
/// executable coverage at all.** Two mutations left every one of the 752 package assertions
/// green: reading `points[segment.from + 1]` instead of `points[segment.to]` — which draws
/// 1-stitch stubs where a coarse plan asked for 51-stitch spans, leaving 50-interval gaps at
/// 50 000 stitches — and iterating `DotRun.indices` instead of `dottedIndices`, which rebuilds
/// all 50 001 ellipses and hands back the entire dot half of US-310's saving. Both are in the app
/// layer, which the engine suite cannot see.
///
/// It is testable at all only because US-310's file split made the builders `internal static`
/// functions over plain values. A `Path` can be walked; the `GraphicsContext` these used to be
/// buried in cannot, which is what the story's "test items not written" section had recorded as
/// the price of the design. That price turns out to be avoidable for the geometry, and only the
/// *dispatch* (which window a hosted `Canvas` asks for) is genuinely out of reach.
@Suite("Canvas stitch stroke geometry")
struct CanvasStitchStrokeTests {
    /// Identity, so a stage point maps to the numerically identical view point and the
    /// assertions can be about *which* points were used rather than about the transform.
    private static let identity = StageTransform(scale: 1, translation: .zero)

    private static func points(_ count: Int) -> [PreviewStitch] {
        (0 ..< count).map {
            PreviewStitch(position: StagePoint(x: Double($0) * 10, y: 0), color: .black)
        }
    }

    /// Every `move`/`line` pair in a path, as the coordinates actually submitted.
    ///
    /// The closure is bound to a `let` and passed as a value rather than written as a trailing
    /// closure, because SwiftFormat's `preferForLoop` rule rewrites `path.forEach { … }` into
    /// `for element in path` — and `Path` is not a `Sequence`, so the formatter's own output does
    /// not compile. Found by the PostToolUse hook doing exactly that to the first version of this
    /// file.
    private static func subpaths(_ path: Path) -> [(from: CGPoint, to: CGPoint)] {
        var pairs: [(from: CGPoint, to: CGPoint)] = []
        var pending: CGPoint?
        let collect: (Path.Element) -> Void = { element in
            switch element {
            case let .move(to: point):
                pending = point
            case let .line(to: point):
                if let start = pending {
                    pairs.append((start, point))
                }
                pending = point
            default:
                break
            }
        }
        path.forEach(collect)
        return pairs
    }

    /// `addEllipse` begins a new subpath, so counting `move` elements counts the dots.
    private static func subpathCount(_ path: Path) -> Int {
        var moves = 0
        let count: (Path.Element) -> Void = { element in
            if case .move = element {
                moves += 1
            }
        }
        path.forEach(count)
        return moves
    }

    // MARK: - Segments

    /// **The mutation this pins**: `points[segment.from + 1]` for `points[segment.to]`. A coarse
    /// segment carries both its endpoints precisely because `to` is *not* `from + 1`, so reading
    /// the far end as an offset from the near one silently redraws a stride-1 stub per span.
    @Test("a segment is drawn between the two stitches it names")
    func aSegmentIsDrawnBetweenTheTwoStitchesItNames() throws {
        let path = CanvasStitchStroke.segmentPath(
            [StitchDrawPlan.Segment(from: 0, to: 51), StitchDrawPlan.Segment(from: 51, to: 60)],
            of: Self.points(61),
            transform: Self.identity
        )

        let drawn = Self.subpaths(path)
        try #require(drawn.count == 2)
        #expect(drawn[0].from.x == 0)
        #expect(drawn[0].to.x == 510, "the far endpoint is `to`, not `from + 1`")
        #expect(drawn[1].from.x == 510)
        #expect(drawn[1].to.x == 600)
    }

    @Test("a fine segment is still drawn between consecutive stitches")
    func aFineSegmentIsStillDrawnBetweenConsecutiveStitches() throws {
        let path = CanvasStitchStroke.segmentPath(
            [StitchDrawPlan.Segment(from: 3, to: 4)],
            of: Self.points(10),
            transform: Self.identity
        )

        let drawn = Self.subpaths(path)
        try #require(drawn.count == 1)
        #expect(drawn[0].from.x == 30)
        #expect(drawn[0].to.x == 40)
    }

    /// ADR-021 divergence #5: a rejected coordinate may reach the display list. One bad endpoint
    /// must cost its own subpath and no more — a batched `Path` with a non-finite point in it can
    /// be discarded wholesale by CoreGraphics, taking every good segment in the colour run with
    /// it.
    @Test("one undrawable endpoint costs its own segment and no others")
    func oneUndrawableEndpointCostsOnlyItsOwnSegment() {
        var points = Self.points(4)
        points[2] = PreviewStitch(position: StagePoint(x: .nan, y: 0), color: .black)

        let path = CanvasStitchStroke.segmentPath(
            [
                StitchDrawPlan.Segment(from: 0, to: 1),
                StitchDrawPlan.Segment(from: 1, to: 2),
                StitchDrawPlan.Segment(from: 2, to: 3)
            ],
            of: points,
            transform: Self.identity
        )

        #expect(Self.subpaths(path).count == 1, "only the segment not touching the bad point")
    }

    /// **Both builders must actually use the transform they are handed** (`/codex-review` round
    /// 2, finding 2). Every other test here uses the identity, so a builder that ignored its
    /// `transform` argument entirely — or read a stale one — would have survived all of them.
    ///
    /// Zoom also changes the dot *radius*, since `StitchDrawMetrics.dotRadius` is a function of
    /// the scale (that is the deviation from Catty that matters most in practice: its width is
    /// derived once from the device diagonal and cannot respond to zoom at all).
    @Test("both builders map through the transform they are given")
    func bothBuildersMapThroughTheTransformTheyAreGiven() throws {
        let zoomed = StageTransform(scale: 3, translation: ViewPoint(x: 100, y: -20))
        let points = Self.points(3)

        let segments = CanvasStitchStroke.segmentPath(
            [StitchDrawPlan.Segment(from: 0, to: 2)], of: points, transform: zoomed
        )
        let drawn = Self.subpaths(segments)
        try #require(drawn.count == 1)
        let expectedFrom = zoomed.viewCGPoint(of: points[0].position)
        let expectedTo = zoomed.viewCGPoint(of: points[2].position)
        #expect(drawn[0].from == expectedFrom)
        #expect(drawn[0].to == expectedTo)
        #expect(drawn[0].from != CGPoint(x: points[0].position.x, y: points[0].position.y),
                "otherwise the identity would satisfy this too")

        // The dots move *and* grow with the scale.
        var list = StitchDisplayList()
        list.append(contentsOf: points)
        let run = StitchDrawPlan.entire(of: list).dots[0]
        let atFit = CanvasStitchStroke.dotPath(run, of: points, transform: Self.identity)
        let atZoom = CanvasStitchStroke.dotPath(run, of: points, transform: zoomed)

        #expect(Self.subpathCount(atZoom) == Self.subpathCount(atFit))
        #expect(atZoom.boundingRect != atFit.boundingRect)
    }

    /// **The radius, isolated from the positions.** A mutation fixing the radius at scale 1
    /// *survived* the test above, because several dots still move apart under zoom and their
    /// combined bounding box grows either way. A **single**-dot fixture is the only shape that
    /// can see the radius at all — and the radius answering zoom is exactly the deviation from
    /// Catty that ADR-024 keeps (Catty derives its width once from the device diagonal, so it
    /// cannot).
    ///
    /// Asserted as a **ratio** rather than as two absolute diameters: `Path.boundingRect` is not
    /// the tight box of an ellipse — the bézier control points of the four arcs lie outside the
    /// curve — so `width == radius * 2` is false, as an earlier version of this test discovered
    /// by failing on unmutated code. Whatever the box includes, it is computed identically at
    /// both scales, so the ratio is exactly the radius ratio.
    @Test("a dot's size is a function of the scale, not a constant")
    func aDotsSizeIsAFunctionOfTheScale() {
        // **Off the origin, deliberately** (`/codex-review` round 4): at (0, 0) the scale has no
        // positional effect at all, so a mutant that centred the dot with scale 1 while keeping
        // the real translation — and the real scale for the radius — passed every dot assertion
        // here. Only a non-origin point separates "scaled" from "translated".
        let single = [PreviewStitch(position: StagePoint(x: 12, y: -7), color: .black)]
        var list = StitchDisplayList()
        list.append(contentsOf: single)
        let run = StitchDrawPlan.entire(of: list).dots[0]

        let atFit = CanvasStitchStroke.dotPath(run, of: single, transform: Self.identity)
        let atZoom = CanvasStitchStroke.dotPath(
            run, of: single, transform: StageTransform(scale: 3, translation: .zero)
        )

        // **Where the dot is, not merely how big it is** (`/codex-review` round 3, finding 3). A
        // mutant that ignored the translation for the centre while still scaling the radius
        // passed the earlier "the bounding rects differ" assertion, because the radius alone
        // changes the box. One dot's box is centred on its own centre, so this pins the position.
        let translated = StageTransform(scale: 3, translation: ViewPoint(x: 40, y: -15))
        let placed = CanvasStitchStroke.dotPath(run, of: single, transform: translated)
        let centre = translated.viewCGPoint(of: single[0].position)
        #expect(abs(placed.boundingRect.midX - centre.x) < 1e-9)
        #expect(abs(placed.boundingRect.midY - centre.y) < 1e-9)
        #expect(
            abs(centre.x - single[0].position.x) > 1,
            "the fixture must actually be moved by the transform, or this pins nothing"
        )
        // The scale must be visible in the *position*, not only in the radius: a translation-only
        // mapping of a point 12 units out lands somewhere else entirely.
        let translationOnly = CGPoint(
            x: single[0].position.x + translated.translation.x,
            y: single[0].position.y + translated.translation.y
        )
        #expect(abs(placed.boundingRect.midX - translationOnly.x) > 1)

        let expected = StitchDrawMetrics.dotRadius(atScale: 3) / StitchDrawMetrics.dotRadius(atScale: 1)
        #expect(expected == 3, "the metric itself must scale, or this test pins nothing")
        // **Within a tolerance, and the reason is arithmetic rather than laziness**: the two
        // sides multiply the same three factors in a different order — `(3.15 × 3) × 2` against
        // `(3.15 × 2) × 3` — which differ in the last bits of a `Double`. An exact `==` here
        // failed on *unmutated* code, which is how this comment came to exist.
        #expect(abs(atZoom.boundingRect.width - atFit.boundingRect.width * expected) < 1e-9)
        #expect(abs(atZoom.boundingRect.height - atFit.boundingRect.height * expected) < 1e-9)
    }

    // MARK: - Dots

    /// **The mutation this pins**: iterating `run.indices` instead of `run.dottedIndices`. The
    /// plan is identical either way — this is a renderer-side loss that no plan assertion sees.
    @Test("a strided dot run draws one dot per stride, not one per stitch")
    func aStridedDotRunDrawsOnePerStride() {
        let list = displayListOfShortMoves(count: 5001)
        let plan = StitchDrawPlan.coarse(of: list, threshold: 0, target: 100)
        let run = plan.dots[0]

        let path = CanvasStitchStroke.dotPath(run, of: list.stitches, transform: Self.identity)

        #expect(run.stride == 51)
        #expect(Self.subpathCount(path) == run.count)
        #expect(Self.subpathCount(path) < list.count / 10, "iterating `indices` would draw all of them")
    }

    @Test("a fine dot run draws one dot per stitch")
    func aFineDotRunDrawsOnePerStitch() {
        let list = displayListOfShortMoves(count: 40)
        let plan = StitchDrawPlan.entire(of: list)
        let run = plan.dots[0]

        let path = CanvasStitchStroke.dotPath(run, of: list.stitches, transform: Self.identity)

        #expect(run.stride == 1)
        #expect(Self.subpathCount(path) == 40)
    }

    @Test("an undrawable dot is skipped rather than added")
    func anUndrawableDotIsSkipped() {
        var stitches = Self.points(4)
        stitches[1] = PreviewStitch(position: StagePoint(x: .infinity, y: 0), color: .black)
        var list = StitchDisplayList()
        list.append(contentsOf: stitches)

        let plan = StitchDrawPlan.entire(of: list)
        let path = CanvasStitchStroke.dotPath(plan.dots[0], of: list.stitches, transform: Self.identity)

        #expect(Self.subpathCount(path) == 3)
    }

    // MARK: - Raster eligibility

    /// **The three clauses that are about staleness, not liveness** (`/codex-review` round 1,
    /// finding 3). `forFrame` asks `canUseRaster` itself and takes this as an input precisely
    /// because "no usable raster" and "an interaction is in flight" are different questions; the
    /// branch this replaced conflated them.
    @Test("a raster is composited only when it is live-free, current and the right size")
    func aRasterIsCompositedOnlyWhenCurrentAndTheRightSize() {
        let viewport = ViewSize(width: 390, height: 500)
        let size = CGSize(width: 390, height: 500)

        #expect(CanvasStitchStroke.compositingRaster(
            canUseRaster: true, bakedKey: "key", expectedKey: "key", size: size, viewport: viewport
        ))
        // Nothing baked yet: `Optional.none == .some(key)` is false, and the frame draws it all.
        #expect(!CanvasStitchStroke.compositingRaster(
            canUseRaster: true, bakedKey: nil, expectedKey: "key", size: size, viewport: viewport
        ))
        // A stale raster — the settled count, the transform or the contrast moved.
        #expect(!CanvasStitchStroke.compositingRaster(
            canUseRaster: true, bakedKey: "old", expectedKey: "key", size: size, viewport: viewport
        ))
        // A `Canvas` smaller than the raster's viewport would *stretch* the settled layer under an
        // unstretched tail: a visibly misplaced seam, so fall back rather than composite.
        #expect(!CanvasStitchStroke.compositingRaster(
            canUseRaster: true, bakedKey: "key", expectedKey: "key",
            size: CGSize(width: 380, height: 500), viewport: viewport
        ))
        #expect(!CanvasStitchStroke.compositingRaster(
            canUseRaster: true, bakedKey: "key", expectedKey: "key",
            size: CGSize(width: 390, height: 499), viewport: viewport
        ))
        // Live: the raster's pixels were baked at another transform.
        #expect(!CanvasStitchStroke.compositingRaster(
            canUseRaster: false, bakedKey: "key", expectedKey: "key", size: size, viewport: viewport
        ))
    }

    private func displayListOfShortMoves(count: Int) -> StitchDisplayList {
        var list = StitchDisplayList()
        list.append(contentsOf: (0 ..< count).map {
            PreviewStitch(position: StagePoint(x: Double($0) * 2, y: 0), color: .black)
        })
        return list
    }
}
