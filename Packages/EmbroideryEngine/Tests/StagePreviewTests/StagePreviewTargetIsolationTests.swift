import EmbroideryEngine
import Interpreter
import StagePreview
import Testing

/// ADR-022: `StagePreview` is **Foundation-only** — no SwiftUI, no
/// CoreGraphics — so the milestone's "zoom/pan transform math is unit-tested"
/// exit criterion is met under `swift test` with no simulator.
///
/// As in `SamplesTargetIsolationTests`, the absence of a dependency is enforced
/// by the manifest, not by this suite: a test cannot observe an edge that does
/// not exist. What it pins is the consequence a reader can check — every type
/// on the boundary is a package or Foundation type, so no CoreGraphics type has
/// quietly become part of the API. Binding the methods to explicit function
/// types is what makes that a compile-time claim rather than a comment: the
/// file stops compiling if a signature starts mentioning `CGPoint`.
@Suite("Stage preview target isolation")
struct StagePreviewTargetIsolationTests {
    @Test("the transform's boundary is Double-based package types, not CoreGraphics")
    func transformBoundaryIsPackageTypes() {
        let forward: (StageTransform) -> (StagePoint) -> ViewPoint = { $0.viewPoint(of:) }
        let inverse: (StageTransform) -> (ViewPoint) -> StagePoint = { $0.stagePoint(of:) }
        let transform = StageTransform(scale: 2)

        #expect(forward(transform)(StagePoint(x: 1, y: 1)) == transform.viewPoint(
            of: StagePoint(x: 1, y: 1)
        ))
        #expect(inverse(transform)(ViewPoint(x: 1, y: 1)) == transform.stagePoint(
            of: ViewPoint(x: 1, y: 1)
        ))
    }

    @Test("a display list is buildable from interpreter events and engine types alone")
    func displayListNeedsNothingBeyondTheEngine() {
        let reduce: ([InterpreterEvent], PreviewNeedle?) -> RunBatch = RunBatch.reducing
        let batch = reduce(
            [.stitch(actor: ActorID(0), position: StagePoint(x: 2, y: 3), layer: 0, color: PreviewColor.red)],
            nil
        )
        var list = StitchDisplayList()
        list.append(contentsOf: batch.stitches)

        #expect(list.stitches == [previewStitch(2, 3, PreviewColor.red)])
    }

    /// US-305's draw plan is the newest thing on this boundary and the most likely
    /// to acquire a `CGFloat`: it exists precisely so the app can stroke it into a
    /// `Canvas`, which makes "just use `CGPoint` here" the obvious shortcut. Bound
    /// to explicit function types in this file's existing style, so taking that
    /// shortcut stops the test target compiling instead of quietly widening ADR-022.
    ///
    /// The plan carries **indices**, not geometry, which is the deeper reason it can
    /// stay Foundation-only — and also why it cannot violate ADR-021's rule against
    /// retaining an `ArraySlice` across an append. There is no slice to retain.
    @Test("the draw plan's boundary is Double-based package types, not CoreGraphics")
    func theDrawPlanBoundaryIsPackageTypes() {
        let plan: (StitchDisplayList) -> StitchDrawPlan = StitchDrawPlan.entire(of:)
        let classify: (PreviewStitch, PreviewStitch) -> StitchSegmentStyle =
            StitchSegmentStyle.classifying(from:to:)
        let width: (Double) -> Double = StitchDrawMetrics.threadWidth(atScale:)
        let fit: (StageBox?) -> StageBox = StageGeometry.fitTarget(including:)

        let list = displayList([previewStitch(0, 0), previewStitch(10, 0)])

        #expect(plan(list) == StitchDrawPlan.entire(of: list))
        #expect(classify(list.stitches[0], list.stitches[1]) == .thread)
        #expect(width(1) == StitchDrawMetrics.threadWidth(atScale: 1))
        #expect(fit(list.bounds) == StageGeometry.box)
    }
}
