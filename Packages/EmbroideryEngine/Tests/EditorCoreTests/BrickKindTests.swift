import EditorCore
import ProgramModel
import Testing

/// US-401 test-plan items 2–4: `BrickKind` mirrors `Brick` one-for-one, and
/// `template()` is total over it.
///
/// `.loopEnd` **has** a kind, and a later reader should not "fix" that by
/// deleting the case. ADR-035's "`.loopEnd` is never in the palette" is a
/// statement about the palette — a curated subset US-409 owns — not about this
/// enum. A `loopEnd` is an ordinary `Brick` that the list renders (US-407) and
/// that US-402's same-kind guard must be able to take the kind of.
@Suite("Brick kinds and templates")
struct BrickKindTests {
    /// The kinds whose template is a whole block rather than a single brick
    /// (ADR-035; the two Ifs from Variables slice 2). Written out literally rather
    /// than derived from `opensBlock`, or the tests below would define their
    /// expectation in terms of the code under test.
    static let blockOpeners: [BrickKind] = [.repeatLoop, .forever, .ifThen, .ifElse]
    static let nonOpeners: [BrickKind] = BrickKind.allCases.filter { !blockOpeners.contains($0) }

    /// Test plan 2. Iterating `allCases` and round-tripping a template through
    /// the mapping proves three things at once: `template()` is **total** (it is
    /// called for every kind), the `Brick → BrickKind` mapping is **injective**
    /// over the templates (an injective round-trip cannot collapse two kinds),
    /// and each template's *first* element is the kind's own brick.
    @Test("every kind round-trips through its own template", arguments: BrickKind.allCases)
    func everyKindRoundTripsThroughItsTemplate(_ kind: BrickKind) throws {
        let first = try #require(kind.template().first)
        #expect(BrickKind(of: first) == kind)
    }

    /// The `Brick → BrickKind` direction is compile-enforced by the exhaustive
    /// no-`default:` switch, so adding a `Brick` case is already a build error.
    /// The reverse direction is not, which is what this count pins: 29 is
    /// `Brick`'s case count (23 until Arc and GoThrough, Brick backend slices 4–5;
    /// 25 until the four If bricks, Variables slice 2).
    @Test("there is exactly one kind per Brick case")
    func kindCountMatchesBrickCaseCount() {
        #expect(BrickKind.allCases.count == 29)
    }

    /// Test plan 3. Whole-array equality, so the *order* is asserted and not
    /// merely the membership — the opener has to come first or the script is
    /// not balanced by construction (ADR-035).
    @Test("a loop opener's template is the opener followed by its loopEnd")
    func loopOpenerTemplatesArePairs() {
        #expect(
            BrickKind.repeatLoop.template()
                == [.repeatLoop(times: .number(BrickDefaults.repeatTimes)), .loopEnd]
        )
        #expect(BrickKind.forever.template() == [.forever, .loopEnd])
    }

    /// Test plan 4.
    @Test("every non-opener template is exactly one brick", arguments: BrickKindTests.nonOpeners)
    func everyNonOpenerTemplateIsExactlyOneBrick(_ kind: BrickKind) throws {
        let bricks = kind.template()
        #expect(bricks.count == 1)
        // …and no non-opener smuggles in a stray closer or else, which would be
        // the one way `template()` could mint an unbalanced script (ADR-035).
        let only = try #require(bricks.first)
        let markers: [BrickKind] = [.loopEnd, .elseBranch, .ifEnd]
        #expect(markers.contains(kind) || only.blockRole == .leaf)
    }
}
