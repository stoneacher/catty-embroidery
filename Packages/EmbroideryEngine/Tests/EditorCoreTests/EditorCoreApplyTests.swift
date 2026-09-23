import EditorCore
import ProgramModel
import Testing

/// US-402 test-plan item 1: each of the five `EditAction` cases, applied to a
/// known program, produces a specific expected **whole `Program`**.
///
/// ADR-006 pattern 3 — the entire value, never field by field. The reason is
/// concrete rather than stylistic: the write-back path resolves four indices and
/// stores through three of them, so an assertion that only inspects the edited
/// brick list cannot see a program whose *other* scripts were also touched.
@Suite("EditorCore.apply — the five cases")
struct EditorCoreApplyTests {
    typealias Fixtures = EditorCoreFixtures

    /// `.wait` rather than a brick already in the fixture, so an insert landing
    /// at the wrong index cannot be mistaken for the brick that was already
    /// there.
    @Test("insert puts a kind's template at the insertion index")
    func insertApplies() {
        let result = EditorCore.apply(.insert(.wait, at: Fixtures.at(0)), to: Fixtures.program)
        #expect(result == .applied(Fixtures.expecting(
            [.wait(seconds: .number(BrickDefaults.waitSeconds))] + Fixtures.bricks
        )))
    }

    @Test("delete of a leaf removes exactly that brick")
    func deleteApplies() {
        let result = EditorCore.apply(.delete(at: Fixtures.at(0)), to: Fixtures.program)
        #expect(result == .applied(Fixtures.expecting(Array(Fixtures.bricks[1...]))))
    }

    /// Destination `9` is the **post-removal** end of a nine-element list, which
    /// is the convention `movingPair` documents and which `EditAction.move`
    /// adopts for every source kind.
    @Test("move of a leaf relocates it to the post-removal destination")
    func moveApplies() {
        let result = EditorCore.apply(.move(from: Fixtures.at(0), to: 9), to: Fixtures.program)
        #expect(result == .applied(Fixtures.expecting(
            Array(Fixtures.bricks[1...]) + [Fixtures.bricks[0]]
        )))
    }

    @Test("replaceBrick swaps exactly one brick for a same-kind replacement")
    func replaceBrickApplies() {
        let replacement = Brick.moveNSteps(.number(42))
        let result = EditorCore.apply(
            .replaceBrick(at: Fixtures.at(0), with: replacement),
            to: Fixtures.program
        )
        var expected = Fixtures.bricks
        expected[0] = replacement
        #expect(result == .applied(Fixtures.expecting(expected)))
    }

    /// The one case with no address, and the one that can never be rejected
    /// (§"renameProgram never rejects" below). `formatVersion`, scenes and
    /// variables must all survive, which is what the whole-value assertion buys.
    @Test("renameProgram changes the name and nothing else")
    func renameApplies() {
        var expected = Fixtures.program
        expected.name = "Renamed"
        #expect(EditorCore.apply(.renameProgram("Renamed"), to: Fixtures.program) == .applied(expected))
    }

    /// `renameProgram` accepts any `String`. ADR-026's `DesignName` is an
    /// **export-boundary** type and the editor deliberately does not borrow it:
    /// a program being edited is allowed a name that could not be written into a
    /// DST header, and US-405/US-211 reject it at the export gate instead.
    ///
    /// Pinned by a test because test 10b's premise is that rename always
    /// applies — add a validation case later and that property silently changes
    /// meaning.
    @Test("renameProgram accepts any string", arguments: [
        "", " ", "\n", String(repeating: "x", count: 500), "Ünïcødé 🧵", "../../etc/passwd"
    ])
    func renameNeverRejects(name: String) {
        var expected = Fixtures.program
        expected.name = name
        #expect(EditorCore.apply(.renameProgram(name), to: Fixtures.program) == .applied(expected))
    }

    /// The "nothing else" half of the acceptance criterion. Value semantics give
    /// it for free; it is asserted rather than assumed because the *implementation*
    /// is free to build a mutable copy, edit it, and then return `.rejected`
    /// having already handed that copy somewhere.
    ///
    /// Two things are checked: the result carries no program at all (a
    /// `.rejected` result has no `.applied` payload to leak one through), and
    /// the input is untouched afterwards.
    @Test("a rejected action returns the rejection and no program")
    func rejectionCarriesNoProgram() {
        let before = Fixtures.program
        let results = [
            EditorCore.apply(.insert(.loopEnd, at: Fixtures.at(0)), to: Fixtures.program),
            EditorCore.apply(.delete(at: Fixtures.at(99)), to: Fixtures.program),
            EditorCore.apply(.move(from: Fixtures.at(5), to: 0), to: Fixtures.program),
            EditorCore.apply(
                .replaceBrick(at: Fixtures.at(0), with: .sewUp),
                to: Fixtures.program
            )
        ]
        for result in results {
            if case let .applied(program) = result {
                Issue.record("expected a rejection, got .applied(\(program.name))")
            }
        }
        #expect(Fixtures.program == before)
    }
}
