import Foundation
import ProgramModel
import Testing

/// Test plan 3: moving a control-brick pair as one contiguous unit (ADR-008).
@Suite("Script move-a-pair-as-a-unit")
struct ScriptMoveTests {
    /// A shared fixture: a leaf, pair P1 [1…3], pair P2 [4…6].
    private func twoPairScript() -> Script {
        Script(bricks: [
            .moveNSteps(.number(10)), // 0
            .repeatLoop(times: .number(3)), // 1  P1 opener
            .stitch, // 2  enclosed
            .loopEnd, // 3  P1 end
            .forever, // 4  P2 opener
            .sewUp, // 5
            .loopEnd // 6  P2 end
        ])
    }

    @Test("moving a loop relocates its whole [begin … loopEnd] block, order preserved")
    func movePairAsUnit() throws {
        // Removing the block [1...3] leaves [move, forever, sewUp, loopEnd];
        // inserting at index 4 appends the pair after P2.
        let moved = try twoPairScript().movingPair(at: 1, to: 4)
        #expect(moved.bricks == [
            .moveNSteps(.number(10)),
            .forever,
            .sewUp,
            .loopEnd,
            .repeatLoop(times: .number(3)),
            .stitch,
            .loopEnd
        ])
    }

    @Test("moving a pair into another loop nests it — a valid, balanced result")
    func moveNestsPairInsideAnotherLoop() throws {
        // ADR-008: nesting is a rendering concern; a complete pair-block reinserted
        // inside another pair nests, never splits. Moving P1 (repeat) into P2
        // (forever) must produce a balanced nested script.
        let script = Script(bricks: [
            .repeatLoop(times: .number(2)), // 0  P1 opener
            .stitch, // 1
            .loopEnd, // 2  P1 end
            .forever, // 3  P2 opener
            .sewUp, // 4
            .loopEnd // 5  P2 end
        ])
        // Removing P1 [0…2] leaves [forever, sewUp, loopEnd]; inserting at index 1
        // drops the whole repeat-loop inside forever.
        let moved = try script.movingPair(at: 0, to: 1)
        #expect(moved.bricks == [
            .forever,
            .repeatLoop(times: .number(2)),
            .stitch,
            .loopEnd,
            .sewUp,
            .loopEnd
        ])
        try moved.validate() // still balanced
        #expect(moved.matchingEnd(ofBrickAt: 1) == 3) // nested repeat resolves
        #expect(moved.matchingEnd(ofBrickAt: 0) == 5) // outer forever resolves
    }

    @Test("moving a nested pair back to its own location is the identity")
    func moveNestedPairIdentity() throws {
        // The subtle case: the moved pair is itself nested inside another. Its home
        // slot lies inside the enclosing loop's range, yet returning it there must
        // reconstruct the original exactly.
        let script = Script(bricks: [
            .forever, // 0 outer opener
            .repeatLoop(times: .number(2)), // 1 inner opener
            .stitch, // 2
            .loopEnd, // 3 inner end
            .loopEnd // 4 outer end
        ])
        #expect(try script.movingPair(at: 1, to: 1) == script)
    }

    @Test("sibling loops inside an enclosing loop can be reordered")
    func moveReordersSiblingLoops() throws {
        // Two sibling loops nested in a forever; move the second sibling ahead of
        // the first. Every pair stays contiguous and balanced.
        let script = Script(bricks: [
            .forever, // 0 outer
            .repeatLoop(times: .number(2)), // 1 sibling A opener
            .stitch, // 2
            .loopEnd, // 3 sibling A end
            .repeatLoop(times: .number(3)), // 4 sibling B opener
            .sewUp, // 5
            .loopEnd, // 6 sibling B end
            .loopEnd // 7 outer end
        ])
        // Remove B [4…6] → [forever, repeatA, stitch, loopEnd, loopEnd]; insert at 1.
        let moved = try script.movingPair(at: 4, to: 1)
        #expect(moved.bricks == [
            .forever,
            .repeatLoop(times: .number(3)),
            .sewUp,
            .loopEnd,
            .repeatLoop(times: .number(2)),
            .stitch,
            .loopEnd,
            .loopEnd
        ])
        try moved.validate()
    }

    @Test("moving a pair back to its own location returns the original value")
    func moveToOwnLocationIsIdentity() throws {
        // After removing P1 [1…3], reinserting at index 1 restores the original —
        // exercising the "insert immediately before another opener is allowed" edge.
        let script = twoPairScript()
        #expect(try script.movingPair(at: 1, to: 1) == script)
    }

    @Test("moving a pair to the front prepends the whole block, order preserved")
    func moveToFront() throws {
        let moved = try twoPairScript().movingPair(at: 1, to: 0)
        #expect(moved.bricks == [
            .repeatLoop(times: .number(3)),
            .stitch,
            .loopEnd,
            .moveNSteps(.number(10)),
            .forever,
            .sewUp,
            .loopEnd
        ])
    }

    @Test("moving a brick that does not open a loop is rejected")
    func moveNonOpenerRejected() {
        let script = Script(bricks: [.stitch, .loopEnd])
        #expect(throws: ScriptMoveError.sourceIsNotLoopOpener(index: 0)) {
            _ = try script.movingPair(at: 0, to: 1)
        }
    }

    @Test("a destination outside the post-removal range is rejected", arguments: [-1, 5])
    func moveDestinationOutOfBounds(destination: Int) {
        // Removing P1 [1…3] leaves 4 bricks; valid insertion indices are 0…4.
        #expect(throws: ScriptMoveError.destinationOutOfBounds(index: destination)) {
            _ = try twoPairScript().movingPair(at: 1, to: destination)
        }
    }

    @Test("moving from an out-of-bounds source is rejected")
    func moveSourceOutOfBounds() {
        #expect(throws: ScriptMoveError.sourceOutOfBounds(index: 0)) {
            _ = try Script().movingPair(at: 0, to: 0)
        }
    }

    @Test("moving an opener with no matching loopEnd is rejected as unbalanced")
    func moveUnbalancedOpener() {
        let script = Script(bricks: [.repeatLoop(times: .number(3)), .stitch])
        #expect(throws: ScriptMoveError.unbalancedPair(index: 0)) {
            _ = try script.movingPair(at: 0, to: 0)
        }
    }

    @Test("moving a locally-matched pair preserves a pre-existing imbalance, not fixes it")
    func moveDoesNotFixGlobalImbalance() throws {
        // A stray leading loopEnd makes the script globally unbalanced, but the
        // forever(1)…loopEnd(3) pair is locally resolvable. movingPair relocates
        // that pair intact and leaves the pre-existing stray end untouched — it
        // preserves balance, it does not enforce it (global balance is validate()'s job).
        let script = Script(bricks: [.loopEnd, .forever, .stitch, .loopEnd])
        let moved = try script.movingPair(at: 1, to: 0)
        #expect(moved.bricks == [.forever, .stitch, .loopEnd, .loopEnd])
        // Still unbalanced — the stray end survives, now trailing.
        #expect(throws: ScriptValidationError.unmatchedLoopEnd(index: 3)) {
            try moved.validate()
        }
    }
}
