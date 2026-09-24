import ProgramModel

public extension Script {
    /// The index of the loop opener that the `loopEnd` at `index` closes,
    /// resolved by a depth-tracking **backward** scan so nested loops match their
    /// correct partners. `nil` if the brick is not a `loopEnd`, the index is out
    /// of bounds, or the script is unbalanced and no opener is found.
    ///
    /// The mirror of `ProgramModel`'s `matchingEnd(ofBrickAt:)`, and US-402 needs
    /// it twice: ADR-035's "delete at a `loopEnd` redirects to its opener", and
    /// the sibling jump, which walks backward past a whole nested pair. Written
    /// once, in its own file, because it belongs to neither of those features.
    ///
    /// Declared in `EditorCore` rather than beside `matchingEnd` for the reason
    /// `Script+IndentDepths.swift` sets out: an extension declared here **moves
    /// nothing**, so `ProgramModel`'s source, its public API and — the
    /// load-bearing part — its serialized format are untouched (ADR-033).
    ///
    /// Total on any script the model permits, including the unbalanced ones no
    /// `EditAction` can create: it never traps and never guesses.
    func matchingOpener(ofLoopEndAt index: Int) -> Int? {
        guard bricks.indices.contains(index), bricks[index].isLoopEnd else {
            return nil
        }
        var depth = 0
        for cursor in stride(from: index, through: 0, by: -1) {
            if bricks[cursor].isLoopEnd {
                depth += 1
            } else if bricks[cursor].opensLoop {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }
        }
        return nil // stray end: never opened
    }
}
