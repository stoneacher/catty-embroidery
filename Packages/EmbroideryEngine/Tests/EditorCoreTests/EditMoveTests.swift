import EditorCore
import ProgramModel
import Testing

/// US-402 test-plan items 6, 7 and 10c, plus the two tests that guard the
/// seam between `EditorCore`'s own vocabulary and the `ScriptMoveError` it
/// wraps.
@Suite("EditorCore.apply — move")
struct EditMoveTests {
    typealias Fixtures = EditorCoreFixtures

    /// Item 6: loop A (indices 1…5, five bricks) moves over its sibling loop B.
    /// After removal the list is five long, so destination `4` is "just before
    /// the trailing leaf" — i.e. A lands after B.
    @Test("moving a loop opener relocates the whole block")
    func movingALoopOpenerMovesTheBlock() throws {
        let result = EditorCore.apply(.move(from: Fixtures.at(1), to: 4), to: Fixtures.program)
        let expected: [Brick] = [
            .moveNSteps(.number(1)),
            .forever,
            .changeXBy(.number(4)),
            .loopEnd,
            .repeatLoop(times: .number(2)),
            .stitch,
            .turnRight(.number(3)),
            .sewUp,
            .loopEnd,
            .stopRunningStitch
        ]
        #expect(result == .applied(Fixtures.expecting(expected)))

        guard case let .applied(program) = result else {
            Issue.record("expected .applied")
            return
        }
        try program.scenes[1].objects[2].scripts[1].validate()
    }

    /// Item 7 — the one move that could split a pair (ADR-035).
    @Test("moving a loopEnd is rejected")
    func movingALoopEndIsRejected() {
        #expect(
            EditorCore.apply(.move(from: Fixtures.at(5), to: 0), to: Fixtures.program)
                == .rejected(.cannotMoveLoopEnd(at: Fixtures.at(5)))
        )
    }

    /// Source-side rules precede destination-side rules, so a `loopEnd` source
    /// with a nonsense destination is deterministically `.cannotMoveLoopEnd`
    /// rather than `.destinationOutOfBounds`.
    @Test("the loopEnd source guard precedes the destination check", arguments: [
        -1, Int.min, Int.max, 9999
    ])
    func loopEndGuardPrecedesDestination(destination: Int) {
        #expect(
            EditorCore.apply(.move(from: Fixtures.at(5), to: destination), to: Fixtures.program)
                == .rejected(.cannotMoveLoopEnd(at: Fixtures.at(5)))
        )
    }

    /// Item 10c. Without this test, item 10b's rule reads as "never reject on an
    /// unbalanced program", which is too strong: `movingPair` throws
    /// `.unbalancedPair` for an opener with no matching end
    /// (`Script+PairedControl.swift:124`) and ADR-008 requires that it keep
    /// doing so.
    ///
    /// This is also the **only** `ScriptMoveError` that `apply` can return —
    /// `.sourceOutOfBounds` and `.sourceIsNotLoopOpener` are unreachable because
    /// `EditorCore` guards both before delegating, and `.destinationOutOfBounds`
    /// is normalised (see below). It is therefore the one case that proves the
    /// wrap ADR-033 asks for actually carries something.
    @Test("moving an opener with no matching end is the wrapped unbalancedPair")
    func movingAnUnclosedOpenerIsRejected() {
        #expect(
            EditorCore.apply(
                .move(from: BrickAddress(brickIndex: 0), to: 0),
                to: Fixtures.withUnclosedOpener
            ) == .rejected(.scriptMove(.unbalancedPair(index: 0)))
        )
    }

    /// ADR-035 states the rule unconditionally — "a source that `isLoopEnd` is
    /// **rejected**" — so it holds for a *stray* end too, where `delete`
    /// deliberately behaves as a leaf instead. That divergence is argued in prose
    /// in two places and was pinned on the `delete` side twice and on the `move`
    /// side not at all.
    ///
    /// The property test cannot reach here: its seed is balanced and `apply`
    /// preserves balance, so a stray `loopEnd` never appears in a generated run.
    /// Found by `swift-code-reviewer` as a surviving mutant — relaxing the guard
    /// to `isLoopEnd && matchingOpener(…) != nil` left the whole suite green.
    @Test("moving a stray loopEnd is rejected too")
    func movingAStrayLoopEndIsRejected() {
        let address = BrickAddress(brickIndex: 0)
        #expect(
            EditorCore.apply(.move(from: address, to: 1), to: Fixtures.withStrayLoopEnd)
                == .rejected(.cannotMoveLoopEnd(at: address))
        )
    }

    /// **The normalisation test.** A pair move gets its destination bound from
    /// `movingPair`; a leaf move gets it from `EditorCore`. The same user-visible
    /// failure must therefore not acquire two spellings selected by what kind of
    /// brick the source happens to be.
    ///
    /// Asserted in both directions, because `#expect(x == a)` alone would pass a
    /// hypothetical third spelling while the naive implementation — delegate
    /// first, wrap whatever comes back — is caught only by the `!=`.
    @Test("an out-of-range destination is one rejection on both paths")
    func destinationRejectionIsNormalised() {
        let pairMove = EditorCore.apply(.move(from: Fixtures.at(1), to: 6), to: Fixtures.program)
        #expect(pairMove == .rejected(.destinationOutOfBounds(index: 6)))
        #expect(pairMove != .rejected(.scriptMove(.destinationOutOfBounds(index: 6))))

        let leafMove = EditorCore.apply(.move(from: Fixtures.at(0), to: 10), to: Fixtures.program)
        #expect(leafMove == .rejected(.destinationOutOfBounds(index: 10)))
    }

    /// **The agreement test.** The destination bound `0 ... (count − span)` now
    /// exists in two places — inside `movingPair` for the pair path, and inside
    /// `EditorCore` for the leaf path — which the design accepted as the residual
    /// cost of normalising above. This pins the two computations to each other,
    /// so drift in either one is red.
    ///
    /// `span` is 1 for the leaf at index 0 and 5 for the pair opened at index 1,
    /// against a ten-brick script: the last legal destination differs (9 vs 5),
    /// which is what makes the test discriminating rather than a coincidence of
    /// equal numbers.
    @Test("the last legal destination and the first illegal one agree on both paths", arguments: [
        (0, 1), (1, 5)
    ])
    func destinationBoundsAgree(source: Int, span: Int) {
        let lastLegal = Fixtures.bricks.count - span
        let move = { (destination: Int) in
            EditorCore.apply(.move(from: Fixtures.at(source), to: destination), to: Fixtures.program)
        }
        if case let .rejected(rejection) = move(lastLegal) {
            Issue.record("destination \(lastLegal) should be legal for span \(span), got \(rejection)")
        }
        #expect(move(lastLegal + 1) == .rejected(.destinationOutOfBounds(index: lastLegal + 1)))
    }

    /// A plain leaf move uses the **same** post-removal convention as
    /// `movingPair`, so `EditAction.move` means one thing regardless of the brick
    /// at `from`. If it did not, US-408's `.onMove` adapter would have to branch
    /// on brick kind to convert SwiftUI's pre-removal `toOffset` — and ADR-035
    /// names that adapter as a deliverable precisely because the conversion is
    /// already the error-prone part.
    ///
    /// Moving index 0 to destination 0 is the identity; destination 1 swaps it
    /// past its neighbour. Under a *pre*-removal reading, destination 1 would be
    /// the identity instead — so these two cases discriminate the conventions.
    @Test("a leaf move uses the post-removal destination convention")
    func leafMoveIsPostRemoval() {
        #expect(
            EditorCore.apply(.move(from: Fixtures.at(0), to: 0), to: Fixtures.program)
                == .applied(Fixtures.program)
        )

        var swapped = Fixtures.bricks
        swapped.swapAt(0, 1)
        #expect(
            EditorCore.apply(.move(from: Fixtures.at(0), to: 1), to: Fixtures.program)
                == .applied(Fixtures.expecting(swapped))
        )
    }

    /// A move that changes nothing is still `.applied`, because `apply` is a pure
    /// function of the action and not of whether the result differs.
    ///
    /// The consequence is downstream and is named here so the next story does not
    /// discover it: US-403 gets an undo entry for a no-op and US-405 voids the
    /// run for one, unless *those* stories compare programs. Putting the
    /// comparison here instead would make `apply` answer a different question —
    /// "did anything change?" — which every other case would then have to answer
    /// too.
    @Test("a no-op move still applies")
    func aNoOpMoveApplies() {
        #expect(
            EditorCore.apply(.move(from: Fixtures.at(9), to: 9), to: Fixtures.program)
                == .applied(Fixtures.program)
        )
    }
}
