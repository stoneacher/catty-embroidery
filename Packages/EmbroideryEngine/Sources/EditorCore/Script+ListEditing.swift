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
        let span = bricks[from].opensLoop ? (range(ofPairAt: from)?.count ?? 1) : 1
        if (from ... from + span).contains(toOffset) { return nil }
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

    /// VoiceOver's "Move Above Loop": the **first** block of a loop body leaves it upward, to
    /// just above the loop's opener. `nil` anywhere else.
    ///
    /// *Decided 2026-09-29 (Sebastian), closing the gap ADR-035's 2026-09-23 amendment named*:
    /// the sibling jump cannot move a brick out of a loop, because the opener is its parent,
    /// while a drag can. This is offered exactly where Move Up is absent for that reason. A
    /// separate verb rather than a wider Move Up: "up" out of a loop is a change of nesting, and
    /// the name says so. **It moves out, never in**: the sibling jump steps over a whole loop,
    /// so no accessibility action puts a brick *into* one — the mirror gap, named in ADR-035's
    /// 2026-09-29 amendment rather than inherited silently.
    ///
    /// Conservative on a malformed script, as the sibling jump is: a block or a loop whose
    /// extent cannot be resolved is offered nothing.
    func moveAboveLoopAction(ofBrickAt index: Int, in script: ScriptAddress) -> EditAction? {
        guard index > 0, blockSpan(at: index) != nil else { return nil }
        let parent = index - 1
        guard bricks[parent].opensLoop, matchingEnd(ofBrickAt: parent) != nil else { return nil }
        return .move(from: BrickAddress(brickIndex: index, script: script), to: parent)
    }

    /// VoiceOver's "Move Below Loop": the **last** block of a loop body leaves it downward, to
    /// just below the loop's end. `nil` anywhere else. The mirror of
    /// `moveAboveLoopAction(ofBrickAt:in:)`; see it for the decision.
    func moveBelowLoopAction(ofBrickAt index: Int, in script: ScriptAddress) -> EditAction? {
        guard let span = blockSpan(at: index) else { return nil }
        // The row just past the block must close the loop the block sits in. One call answers
        // both halves: `matchingOpener` is `nil` for anything that is not a `loopEnd`, out of
        // bounds included, and for a stray end.
        let parentEnd = index + span
        guard matchingOpener(ofLoopEndAt: parentEnd) != nil else { return nil }
        return .move(from: BrickAddress(brickIndex: index, script: script), to: parentEnd + 1 - span)
    }

    /// VoiceOver's "Move Into Loop Above": the block enters the loop just above it, as the last
    /// block of its body.
    func moveIntoLoopAboveAction(ofBrickAt index: Int, in script: ScriptAddress) -> EditAction? {
        nil // Stub (US-408 red phase, round 2).
    }

    /// VoiceOver's "Move Into Loop Below": the block enters the loop just below it, as the first
    /// block of its body.
    func moveIntoLoopBelowAction(ofBrickAt index: Int, in script: ScriptAddress) -> EditAction? {
        nil // Stub (US-408 red phase, round 2).
    }
}

private extension Script {
    /// How many rows the block starting at `index` covers: one for a leaf, the whole pair for
    /// a loop opener. `nil` for a `loopEnd` — not a block of its own — for an opener that never
    /// closes, and out of bounds.
    func blockSpan(at index: Int) -> Int? {
        guard bricks.indices.contains(index), !bricks[index].isLoopEnd else { return nil }
        guard bricks[index].opensLoop else { return 1 }
        return range(ofPairAt: index)?.count
    }

    /// The last row of the block starting at `index`, or `nil` where `blockSpan` is.
    func blockEnd(at index: Int) -> Int? {
        blockSpan(at: index).map { index + $0 - 1 }
    }
}
