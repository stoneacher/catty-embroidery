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

    // MARK: - Empty and unbalanced scripts

    @Test("an empty script is balanced and resolves no pairs")
    func emptyScript() throws {
        let script = Script()
        #expect(script.matchingEnd(ofBrickAt: 0) == nil)
        #expect(script.range(ofPairAt: 0) == nil)
        try script.validate() // an empty list is balanced
    }

    @Test("matchingEnd is nil for an opener that is never closed")
    func matchingEndUnbalancedOpener() {
        let script = Script(bricks: [.repeatLoop(times: .number(3)), .stitch])
        #expect(script.matchingEnd(ofBrickAt: 0) == nil)
    }

    @Test("matchingEnd is nil for out-of-range indices", arguments: [-1, 3])
    func matchingEndOutOfRange(index: Int) {
        let script = Script(bricks: [.forever, .stitch, .loopEnd]) // indices 0…2
        #expect(script.matchingEnd(ofBrickAt: index) == nil)
    }

    @Test("validate flags a forever without a loopEnd")
    func validateUnmatchedForever() {
        // forever shares the opensLoop path with repeatLoop; assert it directly.
        let script = Script(bricks: [.forever, .stitch])
        #expect(throws: ScriptValidationError.unmatchedLoopOpener(index: 0)) {
            try script.validate()
        }
    }

    @Test("validate reports the stray loopEnd first, ahead of a later opener")
    func validateStrayEndBeforeOpener() {
        // A locally resolvable pair (forever…loopEnd) sits after a leading stray
        // loopEnd; the scan must report the stray end (index 0), not scan past it.
        let script = Script(bricks: [.loopEnd, .forever, .loopEnd])
        #expect(throws: ScriptValidationError.unmatchedLoopEnd(index: 0)) {
            try script.validate()
        }
    }

    @Test("validate flags the unclosed opener in a globally invalid nested script")
    func validateUnclosedOuterOpener() {
        // forever(0) never closes; the inner repeat(1)…loopEnd(2) is locally
        // balanced, so the outer opener is the reported failure.
        let script = Script(bricks: [.forever, .repeatLoop(times: .number(2)), .loopEnd])
        #expect(throws: ScriptValidationError.unmatchedLoopOpener(index: 0)) {
            try script.validate()
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
