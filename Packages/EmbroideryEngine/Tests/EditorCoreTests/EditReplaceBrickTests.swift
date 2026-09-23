import EditorCore
import ProgramModel
import Testing

/// US-402 test-plan item 8: the same-kind guard that makes `replaceBrick` a
/// **parameter** edit (ADR-035).
///
/// This is what keeps the pair invariant without re-validating: a replacement
/// cannot turn a `repeatLoop` into a `sewUp` and orphan a `loopEnd`, because
/// `BrickKind` determines `opensLoop`/`isLoopEnd` outright.
@Suite("EditorCore.apply — replaceBrick")
struct EditReplaceBrickTests {
    typealias Fixtures = EditorCoreFixtures

    @Test("replacing with a different kind is rejected and names both kinds")
    func differentKindIsRejected() {
        #expect(
            EditorCore.apply(
                .replaceBrick(at: Fixtures.at(1), with: .forever),
                to: Fixtures.program
            ) == .rejected(.cannotChangeBrickKind(from: .repeatLoop, to: .forever))
        )
    }

    /// `from` and `to` are asserted in the right order. A payload built the other
    /// way round is a plausible slip and would otherwise pass unnoticed, since
    /// both kinds appear in the expectation either way.
    @Test("a rejection reports the existing kind as `from` and the replacement as `to`")
    func rejectionOrientationIsRight() {
        #expect(
            EditorCore.apply(
                .replaceBrick(at: Fixtures.at(0), with: .stitch),
                to: Fixtures.program
            ) == .rejected(.cannotChangeBrickKind(from: .moveNSteps, to: .stitch))
        )
    }

    /// The parameter-edit path US-410 rides on: same kind, different payload.
    @Test("replacing with the same kind replaces exactly that brick")
    func sameKindReplacesOneBrick() {
        var expected = Fixtures.bricks
        expected[1] = .repeatLoop(times: .number(99))
        #expect(
            EditorCore.apply(
                .replaceBrick(at: Fixtures.at(1), with: .repeatLoop(times: .number(99))),
                to: Fixtures.program
            ) == .applied(Fixtures.expecting(expected))
        )
    }

    /// The same-kind guard runs **after** bounds resolution, which is forced
    /// rather than chosen: `from` cannot be computed without a brick to read it
    /// from. Pinned because every other guard in this story runs before its
    /// address check.
    @Test("an out-of-bounds replaceBrick is an address rejection, not a kind rejection")
    func boundsPrecedeTheKindGuard() {
        #expect(
            EditorCore.apply(
                .replaceBrick(at: Fixtures.at(10), with: .sewUp),
                to: Fixtures.program
            ) == .rejected(.addressOutOfBounds(.brick, at: Fixtures.at(10)))
        )
    }

    /// A same-kind replacement is balance-preserving for **every** kind,
    /// including the two openers and `.loopEnd` itself, because the kind decides
    /// `opensLoop`/`isLoopEnd`. Swept over `BrickKind.allCases` so a new kind
    /// joins this claim automatically rather than being quietly exempt.
    @Test("a same-kind replacement of any brick leaves the script balanced")
    func sameKindPreservesBalanceForEveryKind() throws {
        for (index, brick) in Fixtures.bricks.enumerated() {
            let replacement = BrickKind(of: brick).template()[0]
            let result = EditorCore.apply(
                .replaceBrick(at: Fixtures.at(index), with: replacement),
                to: Fixtures.program
            )
            guard case let .applied(program) = result else {
                Issue.record("same-kind replacement at \(index) was rejected: \(result)")
                continue
            }
            try program.scenes[1].objects[2].scripts[1].validate()
        }
    }
}
