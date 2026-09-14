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

    /// **The rule must be orientation-blind, and a horizontal hatch cannot say so**
    /// (`/codex-review` round 7, finding 3).
    ///
    /// Checking both x-extremes closed the left/right hole, but a rule asymmetric in *y* —
    /// `dot <= 0 && incoming.y >= 0`, say — passes every other case in this file, because the
    /// shipping fixture's rows all run horizontally and no turn is ever approached downward.
    ///
    /// A **triangle wave** is the fixture that can tell: every apex is a single vertex, every
    /// apex is a genuine reversal, and they alternate between being approached from below and
    /// from above. So "every vertex at an extreme y survives as a segment endpoint" is both true
    /// and strong here — unlike a boustrophedon, where two consecutive vertices share the extreme
    /// and only one of them is the turn.
    ///
    /// *(The fixture this replaced is worth recording, because it failed for the right reason. It
    /// was a diagonal boustrophedon asserting "every 20th index is a turn" — and index 19 is not
    /// one: the path goes diagonally up-right and then straight up, a ~56° turn that the rule
    /// correctly joins through, with the reversal completing one vertex later. Guessing which
    /// index is a corner re-derives the rule and gets it wrong, which is precisely what this suite
    /// exists not to do. Its successor names no index at all; it names the silhouette.)*
    @Test("the corner rule holds whatever direction the turn is approached from")
    func theCornerRuleHoldsWhateverDirectionTheTurnIsApproachedFrom() {
        var stitches: [PreviewStitch] = []
        var position = StagePoint(x: 0, y: 0)
        stitches.append(PreviewStitch(position: position, color: PreviewColor.red))
        for leg in 0 ..< 250 {
            let rise: Double = leg.isMultiple(of: 2) ? 1 : -1
            for _ in 0 ..< 20 {
                position = StagePoint(x: position.x + 0.5, y: position.y + rise)
                stitches.append(PreviewStitch(position: position, color: PreviewColor.red))
            }
        }
        let list = displayList(stitches)
        let plan = StitchDrawPlan.coarse(of: list, threshold: 0, target: 500)

        var endpoints: Set<Int> = []
        for segment in Self.threadSegments(plan) {
            endpoints.insert(segment.from)
            endpoints.insert(segment.to)
        }

        let heights = list.stitches.map(\.position.y)
        for extreme in [heights.max() ?? 0, heights.min() ?? 0] {
            let apexes = Set(list.stitches.indices.filter { list.stitches[$0].position.y == extreme })
            #expect(apexes.count > 50, "the fixture must have many apexes, or this pins nothing")
            #expect(apexes.subtracting(endpoints).isEmpty, "apexes at y=\(extreme) were joined through")
        }
    }

    /// **A duplicate stitch must not hide a reversal** (`/codex-review` round 6, finding 1).
    ///
    /// A three-consecutive-point predicate cannot see the turn in `(0,0) (10,0) (10,0) (0,0)`:
    /// both triples around the duplicate contain a zero-length interval, so both answer "not a
    /// corner", and the span joins straight from x=0 to x=−30 — erasing the whole excursion out
    /// to x=10 and back, which the fine plan draws. Zero-length intervals *are* correctly not
    /// corners on their own; what was wrong is letting one erase the 180° turn between the
    /// nearest **non-zero** directions either side of it.
    @Test("a repeated stitch does not hide the reversal around it")
    func aRepeatedStitchDoesNotHideTheReversalAroundIt() {
        var stitches = [
            previewStitch(0, 0, PreviewColor.red),
            previewStitch(10, 0, PreviewColor.red),
            previewStitch(10, 0, PreviewColor.red)
        ]
        for index in 0 ..< 5_000 {
            stitches.append(previewStitch(-Double(index) * 10, 0, PreviewColor.red))
        }
        let list = displayList(stitches)

        let plan = StitchDrawPlan.coarse(of: list, threshold: 0, target: 1_000)

        // The excursion's far point is x = 10, at index 1 (and its duplicate at 2). A span that
        // joined across the turn would leave neither as an endpoint.
        var endpoints: Set<Int> = []
        for segment in Self.threadSegments(plan) {
            endpoints.insert(segment.from)
            endpoints.insert(segment.to)
        }
        #expect(
            endpoints.contains(1) || endpoints.contains(2),
            "the turn at x=10 was skipped, so the excursion is not drawn"
        )
    }

    /// **Direction, not raw magnitude** (`/codex-review` round 6, finding 2).
    ///
    /// `leastNonzeroMagnitude * leastNonzeroMagnitude` underflows to `+0`, so a dead-straight path
    /// of denormal steps made *every* interior vertex satisfy `dot <= 0` — every vertex a false
    /// corner, 4 999 segments where the bound allows about 101, and coarsening defeated entirely
    /// on a design that has no corners at all.
    @Test("a straight path of vanishingly small steps has no corners")
    func aStraightPathOfVanishinglySmallStepsHasNoCorners() {
        let step = Double.leastNonzeroMagnitude
        let list = displayList((0 ..< 5_000).map {
            previewStitch(Double($0) * step, 0, PreviewColor.red)
        })

        let plan = StitchDrawPlan.coarse(of: list, threshold: 0, target: 100)
        let stride = StitchDrawPlan.coarseningStride(forStitchCount: list.count, target: 100)

        // One colour run, no traversals, no corners: the bound is the stride term plus the run.
        #expect(Self.threadSegments(plan).count <= (list.count + stride - 1) / stride + 1)
    }

    /// **A break must reset the direction, not just the span** (`/codex-review` round 7).
    ///
    /// Round 6 taught the walker to remember the last non-zero direction. It did not teach it to
    /// *forget* that direction when a traversal, a colour change or an unreachable stitch ends the
    /// chain — so the next chain's first turn was judged against a direction belonging to the
    /// previous one. Concretely: travel `(0,0) → (200,0)`, a duplicate at `(200,0)`, then thread
    /// back to `(190,0)`. The duplicate opens a span; the next interval is compared against the
    /// *traversal's* direction, reads as a 180° corner, and closes a **zero-length** segment.
    /// Repeated, that is an O(n) pile of subpaths that draw nothing and break the bound.
    @Test("a chain that starts after a break has no inherited direction")
    func aChainThatStartsAfterABreakHasNoInheritedDirection() {
        var stitches = [
            previewStitch(0, 0, PreviewColor.red),
            previewStitch(200, 0, PreviewColor.red),
            previewStitch(200, 0, PreviewColor.red)
        ]
        for index in 0 ..< 5_000 {
            stitches.append(previewStitch(190 - Double(index) * 10, 0, PreviewColor.red))
        }
        let list = displayList(stitches)

        let plan = StitchDrawPlan.coarse(of: list, threshold: 0, target: 1_000)

        // A segment whose endpoints share a position draws nothing: pure waste, and the signature
        // of a corner break that fired on an inherited direction.
        for segment in Self.threadSegments(plan) {
            #expect(
                list.stitches[segment.from].position != list.stitches[segment.to].position,
                "zero-length segment \(segment.from)→\(segment.to)"
            )
        }
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
        // **Both edges, and that is finding 3 of `/codex-review` round 6.** Checking only `maxX`
        // left a hole an asymmetric rule walks straight through: `dot <= 0 && cross >= 0`
        // preserves this fixture's two right-edge turns and rejects both left-edge ones, so the
        // right edge stayed pristine, this assertion agreed, and the left edge frayed unseen.
        // A boustrophedon fill has a row end at *each* extreme; the silhouette claim is about all
        // of them.
        let columns = list.stitches.map(\.position.x)
        var endpoints: Set<Int> = []
        for segment in Self.threadSegments(plan) {
            endpoints.insert(segment.from)
            endpoints.insert(segment.to)
        }

        for extreme in [columns.max() ?? 0, columns.min() ?? 0] {
            let ends = Set(list.stitches.indices.filter { list.stitches[$0].position.x == extreme })
            #expect(ends.count > 100, "the fixture must have many row ends, or this pins nothing")
            #expect(ends.subtracting(endpoints).isEmpty, "row ends at x=\(extreme) were cut off")
        }
    }

}
