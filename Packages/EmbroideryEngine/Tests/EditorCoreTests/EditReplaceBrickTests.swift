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

    /// A same-kind replacement is balance-preserving at **every position**,
    /// including the two openers and `.loopEnd` itself, because the kind decides
    /// `opensLoop`/`isLoopEnd`.
    ///
    /// It asserts the **whole `Program`**, not merely acceptance and balance.
    /// Codex round 1 found the weaker version to be a test that cannot fail in a
    /// specific way: a mutant that skipped the write for one kind
    /// (`if existing != .turnRight { edited.bricks[index] = brick }`) silently
    /// discarded the parameter edit and left the whole suite green — verified by
    /// running it. Balance is preserved by *doing nothing*, so a balance-only
    /// assertion cannot see a replacement that never happened.
    ///
    /// The replacement is each brick's own `template()`, whose defaults differ
    /// from the fixture's deliberately distinct payloads (`moveNSteps` 1 vs 10,
    /// `turnRight` 3 vs 15, `repeatLoop` 2 vs 10, `changeXBy` 4 vs 10) — so for
    /// those four the assertion is discriminating. For the payload-free kinds in
    /// the fixture (`stitch`, `sewUp`, `loopEnd`, `forever`, `stopRunningStitch`)
    /// the replacement equals the original and the case contributes acceptance
    /// and balance only. Said plainly rather than left as an implied claim about
    /// all 23 kinds.
    @Test("a same-kind replacement is applied verbatim and leaves the script balanced")
    func sameKindReplacementIsAppliedVerbatim() throws {
        for (index, brick) in Fixtures.bricks.enumerated() {
            let replacement = BrickKind(of: brick).template()[0]
            var expected = Fixtures.bricks
            expected[index] = replacement

            let result = EditorCore.apply(
                .replaceBrick(at: Fixtures.at(index), with: replacement),
                to: Fixtures.program
            )
            #expect(result == .applied(Fixtures.expecting(expected)))

            guard case let .applied(program) = result else { continue }
            try program.scenes[1].objects[2].scripts[1].validate()
        }
    }

    /// The payload oracle, over **every** `BrickKind` rather than the six the
    /// fixture happens to contain.
    ///
    /// Codex round 2's point: the whole-value assertions above cover only the
    /// fixture's kinds, and the property generator checks balance and *whether
    /// something changed*, never whether the requested payload survived. So a
    /// mutation confined to a kind the fixture lacks is invisible. Its worked
    /// example writes `name.lowercased()` into a `setVariable` replacement —
    /// which silently changes **which variable the brick addresses** — and is
    /// indistinguishable from the correct implementation on every input the
    /// suite previously supplied.
    ///
    /// Swept over `BrickKind.allCases`, so a new kind joins this claim by
    /// construction. `perturbed(_:)` is exhaustive over `Brick` with no
    /// `default:`, so a new kind that forgets a payload is a compile error there
    /// rather than a silent exemption here.
    ///
    /// The five payload-free kinds perturb to themselves and are asserted
    /// separately as no-ops, which is the honest claim for them rather than a
    /// coverage number that overstates itself.
    @Test("a same-kind replacement preserves the payload for every kind",
          arguments: BrickKind.allCases)
    func everyKindKeepsItsReplacementPayload(kind: BrickKind) {
        let original = kind.template()[0]
        let replacement = EditorCoreFixtures.perturbed(original)

        let program = Program(scenes: [Scene(objects: [Object(scripts: [
            Script(bricks: [original])
        ])])])
        var expected = program
        expected.scenes[0].objects[0].scripts[0].bricks = [replacement]

        #expect(
            EditorCore.apply(
                .replaceBrick(at: BrickAddress(brickIndex: 0), with: replacement),
                to: program
            ) == .applied(expected)
        )

        // Non-vacuity: for a kind that carries a payload, the assertion above is
        // only discriminating if the replacement actually differs. Named rather
        // than assumed — `perturbed` returning its input for a payload-bearing
        // kind would quietly turn this row into a tautology.
        let payloadFree: Set<BrickKind> = [.stitch, .sewUp, .stopRunningStitch, .forever, .loopEnd]
        #expect((replacement != original) == !payloadFree.contains(kind))
    }

    /// The named case from Codex round 1, kept as its own test so the payload
    /// claim does not depend on the fixture continuing to hold a `turnRight`
    /// whose value differs from `BrickDefaults.turnDegrees`.
    @Test("a parameter-only edit keeps the new value")
    func aParameterOnlyEditKeepsTheNewValue() {
        let program = Program(scenes: [Scene(objects: [Object(scripts: [
            Script(bricks: [.turnRight(.number(3))])
        ])])])
        var expected = program
        expected.scenes[0].objects[0].scripts[0].bricks = [.turnRight(.number(99))]
        #expect(
            EditorCore.apply(
                .replaceBrick(at: BrickAddress(brickIndex: 0), with: .turnRight(.number(99))),
                to: program
            ) == .applied(expected)
        )
    }
}
