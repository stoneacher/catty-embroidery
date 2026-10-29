import EmbroideryEngine
import Interpreter
import ProgramModel
import Samples
import StagePreview
import Testing

/// US-316's overlap-density fixture, guarded against the synthetic it is compared with.
///
/// **What it holds, and what it does not** (brief D1). It keeps the US-309 hatch's stitch count,
/// colour runs and run lengths, and packs the same 250 rows into a fifteenth of the height. It
/// cannot keep the geometry: the running stitch rounds every stitch to whole stage points, so
/// about ten rows land on one `y`, and the row transitions start diagonally from the previous
/// row's anchor. Those differences are therefore **pinned as literals beside the original's**
/// rather than asserted away, so the device comparison reads them off a test instead of
/// assuming them.
@Suite("US-316 overlap-density fixture")
struct CompactSyntheticDesignTests {
    /// The two display lists, built the way a run builds them: interpreter → `RunBatch` →
    /// `StitchDisplayList`.
    private static func displayList(of program: Program) -> StitchDisplayList {
        var subject = interpreter(program)
        var list = StitchDisplayList()
        for events in tickBatches(&subject) {
            list.append(contentsOf: RunBatch.reducing(events).stitches)
        }
        return list
    }

    private static let original = displayList(of: makeUS309SyntheticProgram())
    private static let compact = displayList(of: makeUS316CompactProgram())

    @Test("the compact fixture stitches exactly as often as the original")
    func stitchCountMatches() {
        #expect(stitchEventCount(of: makeUS316CompactProgram()) == us309SyntheticStitchCount)
        #expect(us316CompactStitchCount == us309SyntheticStitchCount)
        #expect(Self.compact.count == Self.original.count)
    }

    /// Run lengths, not only the run count: the per-run walk is part of what a frame plans,
    /// and five runs of different lengths would move work between colours.
    @Test("the colour runs and their lengths match the original's")
    func colourRunsMatch() {
        #expect(Self.compact.colorRuns.count == us309SyntheticColorRunCount)
        #expect(Self.compact.colorRuns.map(\.range) == Self.original.colorRuns.map(\.range))
        #expect(Self.compact.colorRuns.map(\.color) == Self.original.colorRuns.map(\.color))
    }

    /// The variable the fixture exists for. Pinned as literals as well as the ratio, so a
    /// change to either fixture names itself.
    @Test("the compact fixture covers at most a tenth of the original's height")
    func coversATenthOfTheHeight() throws {
        let original = try #require(Self.original.bounds)
        let compact = try #require(Self.compact.bounds)
        #expect(original.maxY - original.minY == 373.5)
        #expect(compact.maxY - compact.minY == 24.5)
        #expect((compact.maxY - compact.minY) * 10 <= original.maxY - original.minY)
        // The width is unchanged: only the spacing moved.
        #expect(compact.maxX - compact.minX == original.maxX - original.minX)
    }

    /// An out-of-hoop design makes the fit depend on the bounds (`SyntheticDesignTests`), and
    /// then the two fixtures would be drawn under different transforms.
    @Test("the compact fixture stays inside ADR-007's stage")
    func staysInsideTheStage() throws {
        let bounds = try #require(Self.compact.bounds)
        let extreme = max(abs(bounds.minX), abs(bounds.maxX), abs(bounds.minY), abs(bounds.maxY))
        #expect(extreme <= StageGeometry.halfExtentInPoints)
    }

    /// The live plan's shape for both fixtures, side by side. The dots depend only on the
    /// count, the stride and the runs, so they must be equal. The thread segments and corners
    /// depend on the geometry, which D1 says is not held; measured, they come out equal too
    /// (the rounding moves rows onto one `y` but keeps every turn a corner), and both are
    /// pinned so a change to either fixture names itself. Equal counts are not equal
    /// geometry: the coincident rows and the transition segments still differ.
    @Test("the live plans are pinned for both fixtures")
    func livePlansArePinned() {
        let original = PlanShape(of: Self.original)
        let compact = PlanShape(of: Self.compact)
        #expect(original == PlanShape(thread: 2000, traversals: 0, dots: 1925, corners: 249))
        #expect(compact == PlanShape(thread: 2000, traversals: 0, dots: 1925, corners: 249))
        #expect(compact.dots == original.dots)
    }

    /// The counts a live frame's work follows: thread segments, travel segments, dots, and the
    /// corners that break coarse spans.
    private struct PlanShape: Equatable {
        var thread: Int
        var traversals: Int
        var dots: Int
        var corners: Int

        init(thread: Int, traversals: Int, dots: Int, corners: Int) {
            self.thread = thread
            self.traversals = traversals
            self.dots = dots
            self.corners = corners
        }

        init(of list: StitchDisplayList) {
            let plan = StitchDrawPlan.coarse(of: list)
            thread = plan.strokes.filter { $0.style == .thread }.flatMap(\.segments).count
            traversals = plan.strokes.filter { $0.style == .traversal }.flatMap(\.segments).count
            dots = plan.dots.reduce(0) { $0 + $1.count }
            corners = (1 ..< max(1, list.count - 1)).count { index in
                StitchDrawPlan.isCorner(
                    list.stitches[index - 1], list.stitches[index], list.stitches[index + 1]
                )
            }
        }
    }
}
