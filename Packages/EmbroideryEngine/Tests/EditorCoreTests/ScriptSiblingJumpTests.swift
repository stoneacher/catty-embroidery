import EditorCore
import ProgramModel
import Testing

/// US-402 test-plan item 11: the pair-aware sibling jump US-408's accessibility
/// actions need — "the index of the previous/next sibling block, skipping over a
/// whole nested pair".
///
/// It is a pure function beside `range(ofPairAt:)`, not view logic, for the same
/// reason ADR-008 put the move there: a "Move Up" that lands between an opener
/// and its `loopEnd` is a broken script, and deciding where it lands is model
/// arithmetic.
///
/// **Siblings, and only siblings.** A brick at the top of a loop body has no
/// previous sibling and the answer is `nil` — the enclosing opener is its
/// *parent*, not its neighbour. *(Decision, Sebastian 2026-09-23.)* The cost is
/// named rather than discovered later: a VoiceOver user driving Move Up/Move
/// Down cannot move a brick **out of** a loop, while a sighted user can drag it
/// out. **US-408 inherits that gap explicitly** and owns whether to close it with
/// a separate "move out of loop" action.
@Suite("Script sibling jump")
struct ScriptSiblingJumpTests {
    typealias Fixtures = EditorCoreFixtures

    /// ```
    /// 0  moveNSteps      depth 0
    /// 1  repeatLoop      depth 0   ─┐
    /// 2    stitch        depth 1    │
    /// 3    turnRight     depth 1    │
    /// 4    sewUp         depth 1    │
    /// 5  loopEnd         depth 0   ─┘
    /// 6  forever         depth 0   ─┐
    /// 7    changeXBy     depth 1    │
    /// 8  loopEnd         depth 0   ─┘
    /// 9  stopRunning…    depth 0
    /// ```
    static let script = Script(bricks: EditorCoreFixtures.bricks)

    /// **Item 11, exactly as the plan words it**: from the brick *after* the
    /// loop, "previous sibling" is the loop's **opener**, not its `loopEnd`.
    /// Returning 5 here is the mistake the whole helper exists to prevent — a
    /// Move Up that swapped with index 5 would drop a brick between `sewUp` and
    /// the `loopEnd`, i.e. inside the loop.
    @Test("previous sibling from after a loop is the loop's opener")
    func previousSiblingSkipsAWholePair() {
        #expect(Self.script.previousSiblingIndex(ofBrickAt: 6) == 1)
        #expect(Self.script.previousSiblingIndex(ofBrickAt: 9) == 6)
    }

    @Test("next sibling from before a loop is the brick after its end")
    func nextSiblingSkipsAWholePair() {
        #expect(Self.script.nextSiblingIndex(ofBrickAt: 0) == 1)
        #expect(Self.script.nextSiblingIndex(ofBrickAt: 1) == 6)
        #expect(Self.script.nextSiblingIndex(ofBrickAt: 6) == 9)
    }

    /// The two ends of the top level.
    @Test("the ends of the list have no sibling in that direction")
    func theEndsOfTheListAreNil() {
        #expect(Self.script.previousSiblingIndex(ofBrickAt: 0) == nil)
        #expect(Self.script.nextSiblingIndex(ofBrickAt: 9) == nil)
    }

    /// Inside a loop body, siblings are the body's own bricks — and the body's
    /// first and last have none in the outward direction.
    @Test("a loop body's bricks are siblings of each other and of nothing outside")
    func aBodyIsItsOwnLevel() {
        #expect(Self.script.nextSiblingIndex(ofBrickAt: 2) == 3)
        #expect(Self.script.previousSiblingIndex(ofBrickAt: 4) == 3)
        // Top of the body: the enclosing opener is its parent, not a sibling.
        #expect(Self.script.previousSiblingIndex(ofBrickAt: 2) == nil)
        // Bottom of the body: the enclosing `loopEnd` likewise.
        #expect(Self.script.nextSiblingIndex(ofBrickAt: 4) == nil)
    }

    /// A `loopEnd` has no sibling identity of its own — the block it belongs to
    /// is identified by its opener. Pinned in both directions because the story
    /// is silent on it and US-408 must be able to rely on it.
    @Test("a loopEnd has no siblings")
    func aLoopEndHasNoSiblings() {
        for index in [5, 8] {
            #expect(Self.script.previousSiblingIndex(ofBrickAt: index) == nil)
            #expect(Self.script.nextSiblingIndex(ofBrickAt: index) == nil)
        }
    }

    /// Total on any index, like `indentDepths` before it.
    @Test("out-of-bounds indices answer nil rather than trapping",
          arguments: [-1, 10, Int.min, Int.max])
    func outOfBoundsIsNil(index: Int) {
        #expect(Self.script.previousSiblingIndex(ofBrickAt: index) == nil)
        #expect(Self.script.nextSiblingIndex(ofBrickAt: index) == nil)
    }

    @Test("an empty script has no siblings anywhere")
    func emptyScript() {
        #expect(Script().previousSiblingIndex(ofBrickAt: 0) == nil)
        #expect(Script().nextSiblingIndex(ofBrickAt: 0) == nil)
    }

    // MARK: Unbalanced scripts — conservative, never a guess

    /// An unresolvable pair yields `nil` rather than a plausible-looking index.
    /// The alternative for an unclosed opener — falling back to `index + 1` —
    /// would move the opener away from its body, which is worse than refusing.
    @Test("an unclosed opener has no next sibling")
    func unclosedOpenerHasNoNextSibling() {
        let script = Script(bricks: [.repeatLoop(times: .number(2)), .moveNSteps(.number(10))])
        #expect(script.nextSiblingIndex(ofBrickAt: 0) == nil)
    }

    /// The previous-direction counterpart, and the one place the two functions
    /// had stopped being mirrors. `nextSiblingIndex` already refused for an
    /// unclosed opener; `previousSiblingIndex` answered `0` — "a plausible-looking
    /// index", which is exactly what its own doc promises not to return.
    ///
    /// The consequence was concrete rather than theoretical: US-408 renders Move
    /// Up/Move Down from these, so VoiceOver would have offered an enabled Move Up
    /// for this opener, and `apply(.move(from: 1, to: 0))` then rejects it with
    /// `.unbalancedPair` every time — an action always offered and never able to
    /// succeed. Found by `swift-code-reviewer`, 2026-09-23.
    @Test("an unclosed opener has no previous sibling either")
    func unclosedOpenerHasNoPreviousSibling() {
        let script = Script(bricks: [
            .stitch, .repeatLoop(times: .number(2)), .moveNSteps(.number(10))
        ])
        #expect(script.previousSiblingIndex(ofBrickAt: 1) == nil)
        #expect(script.nextSiblingIndex(ofBrickAt: 1) == nil)
        // …and **nothing points at it either**. The first version of this test
        // asserted `next(0) == 1`, pinning an asymmetry rather than catching it:
        // `previousSiblingIndex` already refuses when its *answer* is an
        // unresolvable block (a stray `loopEnd` above it), so a `next` that
        // happily returns an unresolvable opener made the two one-way. Codex
        // round 2 found it, and the expectation was wrong, not the code.
        #expect(script.nextSiblingIndex(ofBrickAt: 0) == nil)
    }

    /// The mirror property stated directly, over both balanced and malformed
    /// scripts: if one direction names a neighbour, the other must name it back.
    /// An asymmetry here is what US-408 would render as an action offered in one
    /// direction and missing in the other for the same pair of blocks.
    @Test("the two directions agree on every script, balanced or not")
    func theTwoDirectionsAgree() {
        let scripts = [
            Self.script,
            Script(bricks: [.stitch, .forever]),
            Script(bricks: [.loopEnd, .stitch]),
            Script(bricks: [.repeatLoop(times: .number(2)), .moveNSteps(.number(10))]),
            Script(bricks: [.forever, .repeatLoop(times: .number(2)), .stitch, .loopEnd, .loopEnd]),
            Script(bricks: [.loopEnd, .forever, .loopEnd, .stitch]),
            Script(bricks: [])
        ]
        for script in scripts {
            for index in script.bricks.indices {
                if let next = script.nextSiblingIndex(ofBrickAt: index) {
                    #expect(
                        script.previousSiblingIndex(ofBrickAt: next) == index,
                        "next(\(index)) == \(next) but previous(\(next)) disagrees in \(script.bricks)"
                    )
                }
                if let previous = script.previousSiblingIndex(ofBrickAt: index) {
                    #expect(
                        script.nextSiblingIndex(ofBrickAt: previous) == index,
                        "previous(\(index)) == \(previous) but next(\(previous)) disagrees in \(script.bricks)"
                    )
                }
            }
        }
    }

    /// A stray `loopEnd` cannot be resolved to an opener, so the brick after it
    /// has no previous sibling either.
    @Test("a stray loopEnd yields no previous sibling for the brick after it")
    func strayLoopEndHasNoPreviousSibling() {
        let script = Script(bricks: [.loopEnd, .stitch])
        #expect(script.previousSiblingIndex(ofBrickAt: 1) == nil)
    }

    // MARK: The backward pair primitive

    /// `matchingOpener(ofLoopEndAt:)` is the mirror of `ProgramModel`'s
    /// `matchingEnd(ofBrickAt:)` and this story needs it twice — here, and for
    /// ADR-035's "delete at a `loopEnd` redirects to its opener". Pinned as a
    /// **round trip** against the existing forward scan rather than against
    /// hand-written indices, so the two scans cannot drift apart.
    @Test("matchingOpener round-trips with matchingEnd on a balanced script")
    func matchingOpenerRoundTrips() throws {
        for (index, brick) in Self.script.bricks.enumerated() where brick.isLoopEnd {
            let opener = try #require(Self.script.matchingOpener(ofLoopEndAt: index))
            #expect(Self.script.matchingEnd(ofBrickAt: opener) == index)
        }
        // Nested, so the depth tracking is exercised rather than the trivial case.
        let nested = Script(bricks: [
            .forever, .repeatLoop(times: .number(2)), .stitch, .loopEnd, .sewUp, .loopEnd
        ])
        #expect(nested.matchingOpener(ofLoopEndAt: 3) == 1)
        #expect(nested.matchingOpener(ofLoopEndAt: 5) == 0)
    }

    @Test("matchingOpener is nil where there is nothing to match",
          arguments: [-1, 0, 1, 10, Int.min, Int.max])
    func matchingOpenerIsNilWhereUnresolvable(index: Int) {
        #expect(Script(bricks: [.loopEnd, .stitch]).matchingOpener(ofLoopEndAt: index) == nil)
    }
}
