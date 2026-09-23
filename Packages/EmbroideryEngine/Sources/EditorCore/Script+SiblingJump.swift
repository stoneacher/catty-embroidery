import ProgramModel

public extension Script {
    /// The index of the previous **sibling block**, skipping over a whole nested
    /// pair, or `nil` if there is none.
    ///
    /// US-408's "Move Up" accessibility action is the caller. The arithmetic is
    /// here rather than in a view for the reason ADR-008 gave the move: a Move Up
    /// that lands between an opener and its `loopEnd` produces a brick inside a
    /// loop the user never put it in, and deciding where it lands is model logic.
    ///
    /// **Siblings, and only siblings** *(decision, Sebastian 2026-09-23)*. A
    /// brick at the top of a loop body has no previous sibling — the enclosing
    /// opener is its *parent*, not its neighbour — so the answer is `nil` and
    /// US-408 renders the action as absent or disabled. The cost is real and is
    /// named rather than left to be discovered: a VoiceOver user cannot move a
    /// brick **out of** a loop this way, while a sighted user can drag it out.
    /// Closing that gap needs a separate "move out of loop" verb, which is
    /// US-408's to propose.
    ///
    /// A `loopEnd` answers `nil` in both directions: it has no sibling identity of
    /// its own, because the block it belongs to is identified by its opener — and
    /// ADR-035 rejects moving one anyway.
    ///
    /// Total, and **conservative on an unbalanced script**: an unresolvable pair
    /// yields `nil` rather than a plausible-looking index.
    func previousSiblingIndex(ofBrickAt index: Int) -> Int? {
        guard bricks.indices.contains(index), !bricks[index].isLoopEnd, index > 0 else {
            return nil
        }
        let predecessor = bricks[index - 1]
        if predecessor.isLoopEnd {
            // A sibling *pair* sits above: jump over it to its opener. `nil` here
            // means a stray end, which is not a block and cannot be a sibling.
            return matchingOpener(ofLoopEndAt: index - 1)
        }
        if predecessor.opensLoop {
            // `index` is the first brick of that loop's body — the opener is its
            // parent, not its sibling.
            return nil
        }
        return index - 1
    }

    /// The index of the next **sibling block**, skipping over a whole nested
    /// pair, or `nil` if there is none. The mirror of
    /// `previousSiblingIndex(ofBrickAt:)`; see that function for the semantics.
    func nextSiblingIndex(ofBrickAt index: Int) -> Int? {
        guard bricks.indices.contains(index), !bricks[index].isLoopEnd else {
            return nil
        }
        let end: Int
        if bricks[index].opensLoop {
            // An unclosed opener has no determinate extent, so it has no
            // determinate next sibling. Falling back to `index + 1` would move
            // the opener away from its own body, which is worse than refusing.
            guard let matched = matchingEnd(ofBrickAt: index) else { return nil }
            end = matched
        } else {
            end = index
        }

        let candidate = end + 1
        guard bricks.indices.contains(candidate) else { return nil }
        // A `loopEnd` here closes the *enclosing* loop, so `index` is the last
        // brick of a body — the symmetric counterpart of the opener case above.
        return bricks[candidate].isLoopEnd ? nil : candidate
    }
}
