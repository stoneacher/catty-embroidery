import EmbroideryEngine
import Testing

/// ADR-014 bounds one needle update at a million whole lengths. Arc and
/// GoThrough feed up to 100 updates in one action (ADR-047), each of which can
/// pass that bound, so one tick could materialise ~94 million triple stitches
/// before any run budget looks (Codex, PR 2 handover round 1). The bound is
/// extended to the action: a path whose chords hold more than a million whole
/// lengths feeds the pattern nothing, all or nothing as for one update.
@Suite("RunningStitch path feed")
struct RunningStitchPathTests {
    private func update(_ x: Double, _ y: Double) -> NeedleUpdate {
        NeedleUpdate(position: StagePoint(x: x, y: y))
    }

    private func running(_ length: Double) -> RunningStitch {
        var wrapper = RunningStitch()
        wrapper.activate(RunningStitchPattern(length: length, start: StagePoint(x: 0, y: 0)))
        return wrapper
    }

    @Test("a path within the bound feeds every update as a single feed would")
    func withinTheBoundMatchesSingleFeeds() {
        let path = [update(25, 0), update(25, 30), update(-5, 30)]
        var pathFed = running(10)
        var singleFed = running(10)
        let perUpdate = pathFed.update(path: path, from: StagePoint(x: 0, y: 0))
        #expect(perUpdate == path.map { singleFed.update($0) })
        #expect(perUpdate.joined().count > 5)
    }

    /// Two chords of 500 000 lengths each pass ADR-014 one by one; together
    /// they hold 1 000 001 and the whole path emits nothing.
    @Test("a path over the bound feeds nothing, one empty result per update")
    func overTheBoundFeedsNothing() {
        var wrapper = running(1000)
        let path = [update(5e8, 0), update(1.000001e9, 0)]
        let emitted = wrapper.update(path: path, from: StagePoint(x: 0, y: 0))
        #expect(emitted == [[], []])
    }

    /// As for one rejected update: the anchor stays where it was, so the next
    /// feed measures from it.
    @Test("a rejected path leaves the pattern's anchor untouched")
    func rejectedPathLeavesTheAnchor() {
        var wrapper = running(1000)
        _ = wrapper.update(path: [update(5e8, 0), update(1.000001e9, 0)], from: StagePoint(x: 0, y: 0))
        #expect(wrapper.update(update(2000, 0)) == [
            StagePoint(x: 0, y: 0), StagePoint(x: 1000, y: 0), StagePoint(x: 2000, y: 0)
        ])
    }

    /// The bound counts every chord, including the one from where the needle
    /// stood before the action: 600 000 + 400 001 lengths is over, though the
    /// chords between updates alone (400 001) are not.
    @Test("the first chord, from the needle's start, counts toward the bound")
    func firstChordCounts() {
        var wrapper = running(1000)
        let path = [update(6e8, 0), update(1.000001e9, 0)]
        #expect(wrapper.update(path: path, from: StagePoint(x: 0, y: 0)) == [[], []])
    }

    @Test("an idle wrapper returns one empty result per update")
    func idleWrapper() {
        var wrapper = RunningStitch()
        #expect(wrapper.update(path: [update(10, 0), update(20, 0)], from: StagePoint(x: 0, y: 0)) == [[], []])
    }
}
