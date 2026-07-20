import Foundation
import ProgramModel
import Testing

@Suite("Script paired-control invariant")
struct ScriptTests {
    // MARK: - Test plan 1: matchingEnd resolves partners, correct under nesting

    @Test("matchingEnd resolves a single loop's loopEnd")
    func matchingEndSingleLoop() {
        let script = Script(bricks: [
            .repeatLoop(times: .number(3)), // 0
            .stitch, // 1
            .loopEnd // 2
        ])
        #expect(script.matchingEnd(ofBrickAt: 0) == 2)
        #expect(script.range(ofPairAt: 0) == 0 ... 2)
    }

    @Test("matchingEnd resolves nested loops to their correct partners")
    func matchingEndNestedLoops() {
        let script = Script(bricks: [
            .repeatLoop(times: .number(2)), // 0 outer opener
            .forever, // 1 inner opener
            .stitch, // 2
            .loopEnd, // 3 inner end
            .loopEnd // 4 outer end
        ])
        #expect(script.matchingEnd(ofBrickAt: 0) == 4) // outer partner
        #expect(script.matchingEnd(ofBrickAt: 1) == 3) // inner partner
        #expect(script.range(ofPairAt: 1) == 1 ... 3)
    }

    @Test("matchingEnd is nil for bricks that do not open a loop")
    func matchingEndNonOpener() {
        let script = Script(bricks: [.stitch, .loopEnd])
        #expect(script.matchingEnd(ofBrickAt: 0) == nil) // a leaf brick
        #expect(script.matchingEnd(ofBrickAt: 1) == nil) // loopEnd closes, never opens
    }

    // MARK: - Test plan 2: validate flags unbalanced scripts

    @Test("validate flags a repeatLoop without a loopEnd")
    func validateUnmatchedOpener() {
        let script = Script(bricks: [.repeatLoop(times: .number(3)), .stitch])
        #expect(throws: ScriptValidationError.unmatchedLoopOpener(index: 0)) {
            try script.validate()
        }
    }

    @Test("validate flags a stray loopEnd without an opener")
    func validateUnmatchedEnd() {
        let script = Script(bricks: [.stitch, .loopEnd])
        #expect(throws: ScriptValidationError.unmatchedLoopEnd(index: 1)) {
            try script.validate()
        }
    }

    @Test("validate accepts a balanced nested script")
    func validateBalanced() throws {
        let script = Script(bricks: [
            .repeatLoop(times: .number(2)),
            .forever, .stitch, .loopEnd,
            .loopEnd
        ])
        try script.validate() // does not throw
    }

    // MARK: - Test plan 3: move a pair as one contiguous unit

    @Test("moving a loop relocates its whole [begin … loopEnd] block, order preserved")
    func movePairAsUnit() throws {
        let script = Script(bricks: [
            .moveNSteps(.number(10)), // 0
            .repeatLoop(times: .number(3)), // 1  P1 opener
            .stitch, // 2  enclosed
            .loopEnd, // 3  P1 end
            .forever, // 4  P2 opener
            .sewUp, // 5
            .loopEnd // 6  P2 end
        ])
        // Removing the block [1...3] leaves [move, forever, sewUp, loopEnd];
        // inserting at index 4 appends the pair after P2.
        let moved = try script.movingPair(at: 1, to: 4)
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

    @Test("a move whose destination falls inside another pair is rejected")
    func moveRejectedWhenSplittingPair() {
        let script = Script(bricks: [
            .moveNSteps(.number(10)), // 0
            .repeatLoop(times: .number(3)), // 1  P1 opener
            .stitch, // 2
            .loopEnd, // 3  P1 end
            .forever, // 4  P2 opener
            .sewUp, // 5
            .loopEnd // 6  P2 end
        ])
        // In the post-removal list [move, forever, sewUp, loopEnd], index 2 lands
        // between forever(1) and its loopEnd(3) — inserting there would split P2.
        #expect(throws: ScriptMoveError.destinationSplitsPair(index: 2)) {
            _ = try script.movingPair(at: 1, to: 2)
        }
    }

    @Test("moving a brick that does not open a loop is rejected")
    func moveNonOpenerRejected() {
        let script = Script(bricks: [.stitch, .loopEnd])
        #expect(throws: ScriptMoveError.sourceIsNotLoopOpener(index: 0)) {
            _ = try script.movingPair(at: 0, to: 1)
        }
    }

    // MARK: - Test plan 4: retained markers and whole-value Codable round-trip

    @Test("loopEnd markers are retained in the model, never dropped")
    func loopEndRetained() {
        // ADR-008: loopEnd is a pure marker that serialization and the M4 editor
        // depend on — the model never synthesizes it away.
        let script = Script(bricks: [.forever, .stitch, .loopEnd])
        #expect(script.bricks.count == 3)
        #expect(script.bricks.last == .loopEnd)
    }

    @Test("ScriptHeader defaults to .whenStarted")
    func scriptHeaderDefault() {
        #expect(Script().header == .whenStarted)
    }

    @Test("a Program whose object carries a nested-loop script round-trips whole")
    func programWithNestedLoopCodableRoundTrip() throws {
        let script = Script(
            header: .whenStarted,
            bricks: [
                .repeatLoop(times: .number(3)),
                .moveNSteps(.binary(.plus, .number(1), .variable("x"))),
                .forever,
                .stitch,
                .loopEnd,
                .loopEnd
            ]
        )
        let program = Program(
            name: "Loops",
            scenes: [Scene(objects: [Object(name: "Needle", scripts: [script])])]
        )
        let data = try JSONEncoder().encode(program)
        let decoded = try JSONDecoder().decode(Program.self, from: data)
        // ADR-006 discipline: assert the entire resulting value.
        #expect(decoded == program)
    }
}
