import EmbroideryEngine
import Foundation
import Testing

@Suite("SewUp")
struct SewUpTests {
    private func needle(_ x: Double, _ y: Double) -> NeedleUpdate {
        NeedleUpdate(position: StagePoint(x: x, y: y), heading: 0)
    }

    /// A wrapper mid-stitch: activated and past its first productive update,
    /// so follow-up updates emit interpolants only.
    private func activatedRunningStitch(
        length: Double = 5, at start: StagePoint = StagePoint(x: 0, y: 0)
    ) -> RunningStitch {
        var stitch = RunningStitch()
        stitch.activate(RunningStitchPattern(length: length, start: start))
        return stitch
    }

    /// Approximate comparison per ADR-014 (see ZigzagStitchPatternTests):
    /// the heading's `sin`/`cos` leave transcendental dust, so angled
    /// sequences cannot be compared with exact `==`.
    private func expect(
        _ actual: [StagePoint],
        approximates expected: [StagePoint],
        tolerance: Double = 1e-9,
        _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard actual.count == expected.count else {
            Issue.record(
                "expected \(expected.count) points \(expected), got \(actual)\(comment.map { " — \($0)" } ?? "")",
                sourceLocation: sourceLocation
            )
            return
        }
        for (index, pair) in zip(actual, expected).enumerated() {
            #expect(
                abs(pair.0.x - pair.1.x) <= tolerance && abs(pair.0.y - pair.1.y) <= tolerance,
                "point \(index): \(pair.0) !≈ \(pair.1)\(comment.map { " — \($0)" } ?? "")",
                sourceLocation: sourceLocation
            )
        }
    }

    // MARK: - Catroid golden ports (SewUpTest)

    @Test("Heading 0 sews center/ahead/center/behind/center along +y (port of testVerticalSewUp)")
    func verticalSewUp() {
        var stitch = activatedRunningStitch()
        let points = SewUp.perform(at: StagePoint(x: 0, y: 0), heading: 0, runningStitch: &stitch)
        expect(points, approximates: [
            StagePoint(x: 0, y: 0), StagePoint(x: 0, y: 3), StagePoint(x: 0, y: 0),
            StagePoint(x: 0, y: -3), StagePoint(x: 0, y: 0)
        ])
    }

    @Test("Ahead/behind are offsets from the center, not absolute positions")
    func nonOriginCenter() {
        var stitch = activatedRunningStitch()
        let points = SewUp.perform(at: StagePoint(x: 10, y: 20), heading: 0, runningStitch: &stitch)
        expect(points, approximates: [
            StagePoint(x: 10, y: 20), StagePoint(x: 10, y: 23), StagePoint(x: 10, y: 20),
            StagePoint(x: 10, y: 17), StagePoint(x: 10, y: 20)
        ])
    }

    @Test("Heading 137° offsets ±3·(sin, cos) (port of testAngledSewUp)")
    func angledSewUp() {
        var stitch = activatedRunningStitch()
        let points = SewUp.perform(at: StagePoint(x: 0, y: 0), heading: 137, runningStitch: &stitch)
        // ADR-007 mapping like the reference: x via sin, y via cos, 0° = up.
        let dx = 3 * sin(137 * Double.pi / 180)
        let dy = 3 * cos(137 * Double.pi / 180)
        expect(points, approximates: [
            StagePoint(x: 0, y: 0), StagePoint(x: dx, y: dy), StagePoint(x: 0, y: 0),
            StagePoint(x: -dx, y: -dy), StagePoint(x: 0, y: 0)
        ])
    }

    @Test("STEPS matches Catroid SewUpAction.STEPS")
    func stepsConstant() {
        #expect(SewUp.steps == 3.0)
    }

    // MARK: - Lifecycle interplay (AC 3)

    @Test("A sew-up mid-stitch pauses and resumes without positional drift")
    func interruptedMatchesControl() {
        var control = activatedRunningStitch()
        var interrupted = activatedRunningStitch()
        let first = control.update(needle(10, 0))
        #expect(first == [StagePoint(x: 0, y: 0), StagePoint(x: 5, y: 0), StagePoint(x: 10, y: 0)])
        #expect(interrupted.update(needle(10, 0)) == first)

        let sewUp = SewUp.perform(at: StagePoint(x: 10, y: 0), heading: 0, runningStitch: &interrupted)
        expect(sewUp, approximates: [
            StagePoint(x: 10, y: 0), StagePoint(x: 10, y: 3), StagePoint(x: 10, y: 0),
            StagePoint(x: 10, y: -3), StagePoint(x: 10, y: 0)
        ])
        #expect(interrupted.isRunning)

        // Both wrappers continue identically: the sew-up left no drift.
        let expected = control.update(needle(20, 0))
        #expect(expected == [StagePoint(x: 15, y: 0), StagePoint(x: 20, y: 0)])
        #expect(interrupted.update(needle(20, 0)) == expected)
    }

    @Test("The sew-up re-anchors the pattern — accumulated sub-length travel is discarded")
    func reAnchorAfterSubLengthAccumulation() {
        var stitch = activatedRunningStitch()
        // Sub-length move: nothing emitted, anchor still (0,0), travel pending.
        #expect(stitch.update(needle(3, 0)).isEmpty)

        _ = SewUp.perform(at: StagePoint(x: 3, y: 0), heading: 0, runningStitch: &stitch)

        // Measured from the re-anchored (3,0): anchor + one interpolant.
        // Without the re-anchor the stale (0,0) anchor would give
        // [(0,0),(5,0)] — Catroid resets the start coordinates so the
        // sew-up displacement never counts as travel.
        #expect(stitch.update(needle(8, 0)) == [StagePoint(x: 3, y: 0), StagePoint(x: 8, y: 0)])
    }

    @Test("Re-anchoring lands on the sew-up center, then stitching resumes from it")
    func reAnchorsAndResumes() {
        var stitch = activatedRunningStitch()
        #expect(stitch.update(needle(5, 0)) == [StagePoint(x: 0, y: 0), StagePoint(x: 5, y: 0)])

        _ = SewUp.perform(at: StagePoint(x: 5, y: 7), heading: 0, runningStitch: &stitch)
        #expect(stitch.isRunning)
        #expect(stitch.update(needle(5, 12)) == [StagePoint(x: 5, y: 12)])
    }

    @Test("A sew-up on a never-activated wrapper emits its points but cannot resume")
    func standaloneWithoutPattern() {
        var stitch = RunningStitch()
        let points = SewUp.perform(at: StagePoint(x: 0, y: 0), heading: 0, runningStitch: &stitch)
        #expect(points.count == 5)
        #expect(!stitch.isRunning, "resume() without a pattern stays stopped, like Catroid")
    }

    // MARK: - Dedup interaction (AC 4; US-110's rule, single-actor slice)

    @Test("A sew-up where the needle just stitched dedups the first center — 4 records")
    func sewUpCenterDedups() {
        var stitch = activatedRunningStitch(at: StagePoint(x: 10, y: 20))
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 10, y: 20))
        let before = stream.count

        let points = SewUp.perform(at: StagePoint(x: 10, y: 20), heading: 0, runningStitch: &stitch)
        for point in points {
            stream.addStitch(at: point)
        }

        // Catroid: the leading center is an identical consecutive stitch
        // command and emits nothing; ahead/center/behind/center survive
        // because no two of them are consecutive duplicates.
        #expect(stream.count - before == 4)
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 20, y: 40),
            EmbroideryPoint(x: 20, y: 46), EmbroideryPoint(x: 20, y: 40),
            EmbroideryPoint(x: 20, y: 34), EmbroideryPoint(x: 20, y: 40)
        ])
    }

    @Test("A sew-up away from the last stitch keeps all 5 records")
    func sewUpElsewhereKeepsAllFive() {
        var stitch = activatedRunningStitch()
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        let before = stream.count

        let points = SewUp.perform(at: StagePoint(x: 10, y: 20), heading: 0, runningStitch: &stitch)
        for point in points {
            stream.addStitch(at: point)
        }

        #expect(stream.count - before == 5)
    }

    // MARK: - Degenerate inputs (ADR-014 guard policy)

    @Test("A non-finite heading emits nothing and leaves the running stitch untouched")
    func nonFiniteHeading() {
        var control = activatedRunningStitch()
        var stitch = activatedRunningStitch()
        #expect(SewUp.perform(at: StagePoint(x: 0, y: 0), heading: .nan, runningStitch: &stitch).isEmpty)
        #expect(SewUp.perform(at: StagePoint(x: 0, y: 0), heading: .infinity, runningStitch: &stitch).isEmpty)

        // Still running (the guard fires before pause()) and un-anchored.
        #expect(stitch.isRunning)
        #expect(stitch.update(needle(10, 0)) == control.update(needle(10, 0)))
    }

    @Test("A non-finite center emits nothing and leaves the running stitch untouched")
    func nonFiniteCenter() {
        var control = activatedRunningStitch()
        var stitch = activatedRunningStitch()
        #expect(SewUp.perform(at: StagePoint(x: .nan, y: 0), heading: 0, runningStitch: &stitch).isEmpty)
        #expect(SewUp.perform(at: StagePoint(x: 0, y: .infinity), heading: 0, runningStitch: &stitch).isEmpty)

        #expect(stitch.isRunning)
        #expect(stitch.update(needle(10, 0)) == control.update(needle(10, 0)))
    }

    @Test("A finite but huge heading normalizes instead of emitting NaN points")
    func hugeFiniteHeading() {
        // Un-normalized, heading × π/180 overflows to infinity and the
        // points go NaN — the US-108 Codex find, same class of bug.
        var stitch = activatedRunningStitch()
        let points = SewUp.perform(
            at: StagePoint(x: 0, y: 0), heading: .greatestFiniteMagnitude, runningStitch: &stitch
        )
        #expect(points.count == 5)
        #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test("Negative headings normalize sign-preservingly: −90° ≈ 270°")
    func negativeHeading() {
        // Catroid's motion direction domain is (−180, 180]; the sew-up's
        // truncatingRemainder keeps −90 at −90, which must land where 270°
        // does. Pins the signed branch of the normalization.
        var first = activatedRunningStitch()
        var second = activatedRunningStitch()
        expect(
            SewUp.perform(at: StagePoint(x: 0, y: 0), heading: -90, runningStitch: &first),
            approximates: SewUp.perform(at: StagePoint(x: 0, y: 0), heading: 270, runningStitch: &second)
        )
    }

    @Test("Heading is periodic: 360° ≈ 0°, 497° ≈ 137°")
    func headingPeriodicity() {
        var first = activatedRunningStitch()
        var second = activatedRunningStitch()
        expect(
            SewUp.perform(at: StagePoint(x: 0, y: 0), heading: 360, runningStitch: &first),
            approximates: SewUp.perform(at: StagePoint(x: 0, y: 0), heading: 0, runningStitch: &second)
        )
        expect(
            SewUp.perform(at: StagePoint(x: 0, y: 0), heading: 497, runningStitch: &first),
            approximates: SewUp.perform(at: StagePoint(x: 0, y: 0), heading: 137, runningStitch: &second)
        )
    }
}
