import ProgramModel

public extension Script {
    /// The index of the opener that the closer at `index` ends — a loop's for a
    /// `loopEnd`, an If's for an `ifEnd` — resolved by a depth-tracking
    /// **backward** scan so nested blocks match their correct partners. `nil` if
    /// the brick is not a closer, the index is out of bounds, or the opener found
    /// at its depth is missing or of the other family.
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
    func matchingOpener(ofEndAt index: Int) -> Int? {
        guard bricks.indices.contains(index), case let .closer(family) = bricks[index].blockRole else {
            return nil
        }
        var depth = 0
        for cursor in stride(from: index, through: 0, by: -1) {
            switch bricks[cursor].blockRole {
            case .closer:
                depth += 1
            case let .opener(opening):
                depth -= 1
                if depth == 0 {
                    return opening == family ? cursor : nil
                }
            case .leaf, .divider:
                break
            }
        }
        return nil // stray end: never opened
    }

    /// The If/Else whose `elseBranch` is at `index` — the innermost block
    /// enclosing it, found by the same backward scan — or `nil` when that block
    /// is not an If/Else, or there is none.
    func matchingOpener(ofElseAt index: Int) -> Int? {
        guard bricks.indices.contains(index), bricks[index].isDivider else {
            return nil
        }
        var depth = 0
        for cursor in stride(from: index - 1, through: 0, by: -1) {
            switch bricks[cursor].blockRole {
            case .closer:
                depth += 1
            case .opener where depth == 0:
                return bricks[cursor].expectsElse ? cursor : nil
            case .opener:
                depth -= 1
            case .leaf, .divider:
                break
            }
        }
        return nil
    }

    /// The opener of the innermost block that holds the row at `index` — skipping
    /// any closed block above it, and past an If/Else's else — or `nil` at the top
    /// level. The app names a move out of a block by its family (Variables slice 2).
    func enclosingOpener(ofBrickAt index: Int) -> Int? {
        guard bricks.indices.contains(index) else { return nil }
        var depth = 0
        for cursor in stride(from: index - 1, through: 0, by: -1) {
            switch bricks[cursor].blockRole {
            case .closer:
                depth += 1
            case .opener where depth == 0:
                return cursor
            case .opener:
                depth -= 1
            case .leaf, .divider:
                break
            }
        }
        return nil
    }
}
