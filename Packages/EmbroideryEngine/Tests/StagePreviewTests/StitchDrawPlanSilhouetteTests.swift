import EmbroideryEngine
import Samples
import StagePreview
import Testing

/// The **silhouette**: what coarsening may and may not cut away from a design's shape.
///
/// Its own file because it is its own kind of claim, and because it arrived from a different
/// place than everything around it — Sebastian photographed the artifact on an iPhone
/// (2026-09-05) after five review rounds, three test suites and nineteen mutations had all passed
/// over it. Segment counts, interval coverage, the batching bound and the traversal rule say
/// nothing whatever about *which* vertices a span skips, so none of them could see a fill whose
/// row ends were being chopped into comb teeth for as long as a finger was down.
@Suite("Stitch draw plan silhouette")
struct StitchDrawPlanSilhouetteTests {
    private static func threadSegments(_ plan: StitchDrawPlan) -> [StitchDrawPlan.Segment] {
        plan.strokes.filter { $0.style == .thread }.flatMap(\.segments)
    }

    /// **The artifact a device found and no test could see** (Sebastian, 2026-09-05).
    ///
    /// Coarsening a boustrophedon fill without a corner rule cuts each row turn, chopping up to
    /// `stride − 1` stitches off the row end: on screen the design's straight edges fray into comb
    /// teeth with dots beading on the tips, and the silhouette shrinks — all of it while a finger
    /// is down. Every assertion in this file passed throughout, because segment *counts* and
    /// interval *coverage* are both untouched by which vertices a span skips.
    ///
    /// Two assertions, because they fail for different reasons: the first says no span crosses a
    /// corner, and the second says the drawn *silhouette* is the fine plan's — which is the
    /// property a user actually sees, and which holds for this fixture precisely because its
    /// extreme points are its corners.
    @Test("a coarse span never cuts a corner, so the silhouette survives")
    func aCoarseSpanNeverCutsACorner() {
        let list = SyntheticDesign.displayList(count: 50_001, colorRuns: 5)
        let plan = StitchDrawPlan.coarse(of: list)

        var cutCorners = 0
        for segment in Self.threadSegments(plan) where segment.to > segment.from + 1 {
            for index in (segment.from + 1) ..< segment.to
                where StitchDrawPlan.isCorner(
                    list.stitches[index - 1], list.stitches[index], list.stitches[index + 1]
                ) {
                cutCorners += 1
            }
        }
        #expect(cutCorners == 0)

        // **The silhouette, stated without reference to `isCorner`** — otherwise a wrong rule and
        // a wrong plan agree with each other, which is how a strict-reversal mutant first
        // survived. Every row end of this hatch sits at the design's extreme x, and each must
        // survive as a segment endpoint; cutting the turns is exactly what left comb teeth along
        // both edges on the device.
        //
        // The whole-design *bounding box* is too weak to say this, and that was the first
        // attempt: with 250 rows, some row end coincidentally lands on a span boundary, so the
        // extreme x survives by luck even when most rows are chopped. Counting the extreme
        // stitches individually is what makes it discriminate.
        let extremeX = list.stitches.map(\.position.x).max() ?? 0
        let extremes = Set(list.stitches.indices.filter { list.stitches[$0].position.x == extremeX })
        var endpoints: Set<Int> = []
        for segment in Self.threadSegments(plan) {
            endpoints.insert(segment.from)
            endpoints.insert(segment.to)
        }

        #expect(extremes.count > 100, "the fixture must have many row ends, or this pins nothing")
        #expect(extremes.subtracting(endpoints).isEmpty, "row ends were cut off the silhouette")
    }

}
