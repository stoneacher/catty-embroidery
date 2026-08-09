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
        #expect(transform.scale is Double)
    }

    @Test("a display list is buildable from interpreter events and engine types alone")
    func displayListNeedsNothingBeyondTheEngine() {
        let reduce: ([InterpreterEvent], PreviewNeedle?) -> RunBatch = RunBatch.reducing
        let batch = reduce(
            [.stitch(actor: ActorID(0), position: StagePoint(x: 2, y: 3), layer: 0, color: red)],
            nil
        )
        var list = StitchDisplayList()
        list.append(contentsOf: batch.stitches)

        #expect(list.stitches == [previewStitch(2, 3, red)])
    }
}
