import ProgramModel

/// What a list gesture or an accessibility action means as an `EditAction` (US-408).
///
/// Pure arithmetic over a script, here rather than in a view for the reason ADR-008 put the
/// move itself in the model: a reorder that lands one index wrong produces a brick inside a
/// loop the user never put it in, and the conversion is the named off-by-one of ADR-035.
///
/// Every function **builds** an action and never applies one. `EditorCore.apply` stays the
/// only authority on what is refused (ADR-033), so a source these functions do not screen —
/// a `loopEnd` handed to `moveAction(fromOffsets:toOffset:in:)` — is still turned into a
/// `.move` and rejected there, with its reason, rather than refused twice in two vocabularies.
/// `nil` means "there is no edit to make", not "this edit is refused".
///
/// The offsets are `some Collection<Int>` rather than `IndexSet` so that `EditorCore` stays
/// free of Foundation; `IndexSet` conforms, and a test can pass an array literal.
public extension Script {
    /// The `.move` a SwiftUI `.onMove(fromOffsets:toOffset:)` callback means, or `nil` when
    /// there is none to make.
    ///
    /// **The conversion ADR-035 names.** `toOffset` counts the list *before* the dragged block
    /// is removed; `EditAction.move` counts it *after* (`movingPair`'s convention). The two
    /// differ by the number of removed rows that sit above the drop, which is `0` for an
    /// upward move and the **whole block's length** for a downward one — five, not one, for a
    /// five-brick loop:
    ///
    /// ```
    /// destination = toOffset − count(removed indices < toOffset)
    /// ```
    ///
    /// A drop anywhere from the block's own top edge to its bottom edge puts it back where it
    /// was, so it is no edit (`nil`). Checking that range first is also what keeps a drop
    /// *inside* a moving loop from computing a negative destination.
    ///
    /// Several offsets, or none, are `nil` too: a single-finger drag gives one, and moving the
    /// first while dropping the rest would misreport what happened.
    func moveAction(
        fromOffsets source: some Collection<Int>,
        toOffset: Int,
        in script: ScriptAddress
    ) -> EditAction? {
        guard source.count == 1, let from = source.first else { return nil }
        let address = BrickAddress(brickIndex: from, script: script)
        // A row SwiftUI could not have produced is still `apply`'s to refuse, with its reason.
        guard bricks.indices.contains(from) else { return .move(from: address, to: toOffset) }

        // An unclosed opener counts as one row: `apply` rejects it as `.unbalancedPair`
        // whatever the destination, so the only thing its span could change is which
        // destination that rejection names.
        let span = bricks[from].opensBlock ? (range(ofPairAt: from)?.count ?? 1) : 1
        if (from ... from + span).contains(toOffset) {
            return nil
        }
        let destination = toOffset > from ? toOffset - span : toOffset
        return .move(from: address, to: destination)
    }

    /// The `.delete` a SwiftUI `.onDelete(perform:)` callback means, or `nil`.
    ///
    /// One offset only. A swipe gives one; several would be stale after the first, since
    /// deleting a loop removes more rows than were named.
    func deleteAction(atOffsets offsets: some Collection<Int>, in script: ScriptAddress) -> EditAction? {
        guard offsets.count == 1, let index = offsets.first else { return nil }
        return .delete(at: BrickAddress(brickIndex: index, script: script))
    }

    /// VoiceOver's "Move Up": the block at `index` jumps over its whole previous sibling
    /// block, or `nil` where there is none (`previousSiblingIndex(ofBrickAt:)`).
    ///
    /// The sibling sits above, so removing the block does not shift it: its index is already
    /// the post-removal destination.
    func moveUpAction(ofBrickAt index: Int, in script: ScriptAddress) -> EditAction? {
        guard let sibling = previousSiblingIndex(ofBrickAt: index) else { return nil }
        return .move(from: BrickAddress(brickIndex: index, script: script), to: sibling)
    }

    /// VoiceOver's "Move Down": the block at `index` jumps over its whole next sibling block,
    /// or `nil` where there is none (`nextSiblingIndex(ofBrickAt:)`).
    ///
    /// It lands just below the sibling's last row, which — once the block itself is removed
    /// from above it — is `siblingEnd + 1 − span`.
    func moveDownAction(ofBrickAt index: Int, in script: ScriptAddress) -> EditAction? {
        guard let sibling = nextSiblingIndex(ofBrickAt: index),
              let span = blockSpan(at: index),
              let siblingEnd = blockEnd(at: sibling)
        else { return nil }
        return .move(from: BrickAddress(brickIndex: index, script: script), to: siblingEnd + 1 - span)
    }

    /// VoiceOver's "Move Above Loop" or "Move Above If" (named after the block left): the
    /// **first** block of a body or then-branch leaves it upward, to just above the opener.
    /// `nil` anywhere else, including the first block of an else-branch (Move Above Else).
    ///
    /// *Decided 2026-09-29 (Sebastian), closing the gap ADR-035's 2026-09-23 amendment named*:
    /// the sibling jump cannot move a brick out of a loop, because the opener is its parent,
    /// while a drag can. This is offered exactly where Move Up is absent for that reason. A
    /// separate verb rather than a wider Move Up: "up" out of a loop is a change of nesting, and
    /// the name says so. Its mirror, into a loop, is `moveIntoBlockAboveAction(ofBrickAt:in:)`.
    ///
    /// Conservative on a malformed script, as the sibling jump is: a block or a loop whose
    /// extent cannot be resolved is offered nothing.
    func moveOutAboveAction(ofBrickAt index: Int, in script: ScriptAddress) -> EditAction? {
        guard index > 0, blockSpan(at: index) != nil else { return nil }
        let parent = index - 1
        guard bricks[parent].opensBlock, matchingEnd(ofBrickAt: parent) != nil else { return nil }
        return .move(from: BrickAddress(brickIndex: index, script: script), to: parent)
    }

    /// VoiceOver's "Move Below Loop" or "Move Below If": the **last** block of a body or
    /// else-branch leaves it downward, to just below the end. `nil` anywhere else, including
    /// the last block of a then-branch (Move Below Else). The mirror of
    /// `moveOutAboveAction(ofBrickAt:in:)`; see it for the decision.
    func moveOutBelowAction(ofBrickAt index: Int, in script: ScriptAddress) -> EditAction? {
        guard let span = blockSpan(at: index) else { return nil }
        // The row just past the block must close the block it sits in. One call answers
        // both halves: `matchingOpener` is `nil` for anything that is not an end, out of
        // bounds included, and for an end whose block does not resolve.
        let parentEnd = index + span
        guard matchingOpener(ofEndAt: parentEnd) != nil else { return nil }
        return .move(from: BrickAddress(brickIndex: index, script: script), to: parentEnd + 1 - span)
    }

    /// VoiceOver's "Move Into Loop Above" or "Move Into If Above": when the previous sibling
    /// block is a loop or an If, the block enters it as the **last** block of its last body or
    /// branch — just before its end. `nil` otherwise.
    ///
    /// *Decided 2026-09-29 (Sebastian), at `swift-code-reviewer`'s finding*: the move-out pair
    /// alone left the mirror gap, since the sibling jump steps over a whole loop and nothing put
    /// a brick *into* one. With this pair, the actions reach exactly the arrangements a drag
    /// reaches — `AccessibilityMoveTests` and `IfBlockAccessibilityMoveTests` assert that as a
    /// reachability property.
    ///
    /// The loop's end sits above the block, so removing the block does not shift it: its index
    /// is already the post-removal destination.
    func moveIntoBlockAboveAction(ofBrickAt index: Int, in script: ScriptAddress) -> EditAction? {
        // `matchingEnd` is `nil` unless the sibling opens a block that resolves.
        guard let sibling = previousSiblingIndex(ofBrickAt: index),
              let end = matchingEnd(ofBrickAt: sibling)
        else { return nil }
        return .move(from: BrickAddress(brickIndex: index, script: script), to: end)
    }

    /// VoiceOver's "Move Into Loop Below" or "Move Into If Below": when the next sibling block
    /// is a loop or an If, the block enters it as the **first** block of its body or then-branch
    /// — just after its opener, which with the
    /// block removed from above it is `opener + 1 − span`. `nil` otherwise. See
    /// `moveIntoBlockAboveAction(ofBrickAt:in:)` for the decision.
    func moveIntoBlockBelowAction(ofBrickAt index: Int, in script: ScriptAddress) -> EditAction? {
        // `nextSiblingIndex` already refuses an opener whose extent is unknown, and so does
        // `blockSpan` for the block itself.
        guard let sibling = nextSiblingIndex(ofBrickAt: index),
              bricks[sibling].opensBlock,
              let span = blockSpan(at: index)
        else { return nil }
        return .move(from: BrickAddress(brickIndex: index, script: script), to: sibling + 1 - span)
    }

    /// VoiceOver's "Move Below Else": the then-branch's **last** block crosses the else,
    /// to the top of the else-branch. `nil` anywhere else.
    ///
    /// The else sits below the block, so once the block is removed from above it the else is
    /// at `index` and the top of the else-branch is `else + 1 − span`. Offered only where the
    /// If/Else resolves end to end, as the move-out pair is.
    func moveBelowElseAction(ofBrickAt index: Int, in script: ScriptAddress) -> EditAction? {
        guard let span = blockSpan(at: index) else { return nil }
        let divider = index + span
        guard resolvedElse(at: divider) else { return nil }
        return .move(from: BrickAddress(brickIndex: index, script: script), to: divider + 1 - span)
    }

    /// VoiceOver's "Move Above Else": the else-branch's **first** block crosses the else,
    /// to the bottom of the then-branch. `nil` anywhere else.
    ///
    /// The else sits above the block, so removing the block does not shift it: its index is
    /// the post-removal destination, the bottom of the then-branch.
    func moveAboveElseAction(ofBrickAt index: Int, in script: ScriptAddress) -> EditAction? {
        guard index > 0, blockSpan(at: index) != nil, resolvedElse(at: index - 1) else { return nil }
        return .move(from: BrickAddress(brickIndex: index, script: script), to: index - 1)
    }

    /// The `.insert` a palette tap means, with `selected` the row the list has selected (US-409).
    ///
    /// **Directly after the selected row**, or at the end when nothing is selected. That
    /// one rule covers the three cases ADR-035 and the story name:
    /// - **after a leaf**: the next position, at the leaf's depth;
    /// - **after a loop opener**: the first position of its body, so the brick lands *inside*
    ///   the loop. That is what makes a loop fillable by tap-to-add. It needs no special case,
    ///   because nesting is positional (ADR-008). Skipping over the whole block would put the
    ///   brick after the loop instead;
    /// - **after a `loopEnd`**: after the loop, at the loop's own depth (decided 2026-10-01).
    ///   This is the only tap that appends after a loop that is not last.
    ///
    /// A selection outside the script counts as none. Rows are identified by index (ADR-034),
    /// so a stale selection must never become a rejected insert.
    ///
    /// The index the action names is where the new brick's head lands, whether a leaf or a
    /// loop's opener, so it is also the list's scroll target.
    func insertAction(of kind: BrickKind, after selected: Int?, in script: ScriptAddress) -> EditAction {
        let index = selected.flatMap { bricks.indices.contains($0) ? $0 + 1 : nil } ?? bricks.count
        return .insert(kind, at: BrickAddress(brickIndex: index, script: script))
    }
}

private extension Script {
    /// How many rows the block starting at `index` covers: one for a leaf, the whole block for
    /// an opener. `nil` for an end or an else — not blocks of their own — for an opener that
    /// never closes, and out of bounds.
    func blockSpan(at index: Int) -> Int? {
        guard bricks.indices.contains(index) else { return nil }
        switch bricks[index].blockRole {
        case .closer, .divider: return nil
        case .leaf: return 1
        case .opener: return range(ofPairAt: index)?.count
        }
    }

    /// Whether `index` is an If/Else's else whose block resolves end to end.
    func resolvedElse(at index: Int) -> Bool {
        guard let opener = matchingOpener(ofElseAt: index) else { return false }
        return matchingEnd(ofBrickAt: opener) != nil
    }

    /// The last row of the block starting at `index`, or `nil` where `blockSpan` is.
    func blockEnd(at index: Int) -> Int? {
        blockSpan(at: index).map { index + $0 - 1 }
    }
}
