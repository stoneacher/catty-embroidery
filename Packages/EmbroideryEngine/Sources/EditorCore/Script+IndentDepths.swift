import ProgramModel

public extension Script {
    /// The nesting depth of each brick, one per row, for the script list to
    /// render as indentation (US-407).
    ///
    /// Declared in `EditorCore` rather than beside `Script+PairedControl.swift`,
    /// and that is ADR-033 being followed rather than bent: an extension
    /// declared here **moves nothing**. `ProgramModel`'s source, its public API
    /// and — the load-bearing part — its serialized format are untouched, so
    /// `SampleJSONResourceTests`' `decode(resource) == builder()` and the M2
    /// goldens are unaffected. The symbol belongs to `EditorCore` and is
    /// invisible to anything importing only `ProgramModel`. ADR-008 says nesting
    /// *is a rendering concern*, and this is the editor target.
    ///
    /// **A `loopEnd` sits at its opener's depth, not its body's** — decrementing
    /// *before* appending is the whole trick, and the mistake worth guarding is
    /// doing it the other way round.
    ///
    /// It uses `opensLoop`/`isLoopEnd` — the pair vocabulary ADR-008 owns — but
    /// deliberately **not** `matchingEnd(ofBrickAt:)`/`range(ofPairAt:)`, which
    /// the story's reference note suggests. Two reasons, the first decisive:
    /// `matchingEnd` returns `nil` for an opener that is never closed, so a
    /// pair-resolving implementation needs a fallback for exactly the unbalanced
    /// case this function must survive — and that fallback is this depth counter
    /// anyway. Second, `matchingEnd` is itself an O(n) scan, so resolving per
    /// opener would re-walk the list once per loop. Nothing about pairing is
    /// re-derived that `opensLoop`/`isLoopEnd` do not already express; this is
    /// the same single scan `matchingEnd` performs internally, run once for the
    /// whole list.
    ///
    /// Total on any script the model permits, including the unbalanced ones no
    /// `EditAction` can create (ADR-035): it never subscripts, never traps, never
    /// returns a negative depth, and always returns exactly `bricks.count`
    /// elements.
    var indentDepths: [Int] {
        var depths: [Int] = []
        depths.reserveCapacity(bricks.count)
        var depth = 0

        for brick in bricks {
            if brick.isLoopEnd {
                // Clamped, so a `loopEnd` closing a loop that was never opened
                // leaves the depth at 0 instead of going negative.
                depth = max(0, depth - 1)
                depths.append(depth)
            } else {
                depths.append(depth)
                if brick.opensLoop {
                    depth += 1
                }
            }
        }
        return depths
    }
}
