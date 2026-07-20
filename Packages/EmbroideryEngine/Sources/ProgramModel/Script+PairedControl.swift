// Paired-control model logic (ADR-008): control bricks are begin/end pairs in
// the flat brick list. Resolving a pair, validating balance, and moving a pair
// as one unit are model concerns with tests here — never view logic in M4.

public extension Brick {
    /// Whether this brick opens a loop that a later `loopEnd` closes
    /// (Catroid composite bricks: `RepeatBrick`, `ForeverBrick`). `wait` is a
    /// leaf despite sitting in the control category, so it does not open a pair.
    var opensLoop: Bool {
        switch self {
        case .repeatLoop, .forever: true
        default: false
        }
    }

    /// Whether this brick closes a loop (Catroid `LoopEndBrick`).
    var isLoopEnd: Bool {
        if case .loopEnd = self {
            true
        } else {
            false
        }
    }
}

/// A script whose control bricks do not balance (Catroid never lets this happen
/// via the editor; the model reports it so the M4 editor and `.catrobat` import
/// can reject malformed input).
public enum ScriptValidationError: Error, Equatable {
    /// A loop opener at `index` has no matching `loopEnd`.
    case unmatchedLoopOpener(index: Int)
    /// A `loopEnd` at `index` closes a loop that was never opened.
    case unmatchedLoopEnd(index: Int)
}

/// Why a move-a-pair-as-a-unit request was rejected.
public enum ScriptMoveError: Error, Equatable {
    /// The brick at `index` is not a loop opener, so there is no pair to move.
    case sourceIsNotLoopOpener(index: Int)
    /// The opener at `index` has no matching `loopEnd` (unbalanced script).
    case unbalancedPair(index: Int)
    /// The destination lies outside the valid insertion range.
    case destinationOutOfBounds(index: Int)
    /// Inserting at the destination would split another pair's begin/end block.
    case destinationSplitsPair(index: Int)
}

public extension Script {
    /// The index of the `loopEnd` that closes the loop opener at `index`,
    /// resolved by a depth-tracking forward scan so nested loops match their
    /// correct partners. `nil` if the brick does not open a loop or the script
    /// is unbalanced.
    func matchingEnd(ofBrickAt index: Int) -> Int? {
        guard bricks.indices.contains(index), bricks[index].opensLoop else {
            return nil
        }
        var depth = 0
        for i in index ..< bricks.count {
            if bricks[i].opensLoop {
                depth += 1
            } else if bricks[i].isLoopEnd {
                depth -= 1
                if depth == 0 {
                    return i
                }
            }
        }
        return nil // opener never closed
    }

    /// The contiguous `[opener … loopEnd]` range of the pair opened at `index`,
    /// or `nil` if `index` is not a resolvable opener. This is the block that
    /// moves as one unit.
    func range(ofPairAt index: Int) -> ClosedRange<Int>? {
        guard let end = matchingEnd(ofBrickAt: index) else { return nil }
        return index ... end
    }

    /// Throws the first balance error found: a `loopEnd` with no open loop, or,
    /// once the list is scanned, a loop opener that was never closed.
    func validate() throws {
        var openerStack: [Int] = []
        for (index, brick) in bricks.enumerated() {
            if brick.opensLoop {
                openerStack.append(index)
            } else if brick.isLoopEnd {
                guard !openerStack.isEmpty else {
                    throw ScriptValidationError.unmatchedLoopEnd(index: index)
                }
                openerStack.removeLast()
            }
        }
        if let unclosed = openerStack.last {
            throw ScriptValidationError.unmatchedLoopOpener(index: unclosed)
        }
    }

    /// Returns a copy of the script with the pair opened at `sourceIndex` — its
    /// opener, matched `loopEnd`, and everything between — relocated as one
    /// contiguous block. `destination` is an insertion index into the list with
    /// the block already removed (`0 ... remaining.count`). A move that would
    /// split another pair, or whose source is not a resolvable opener, is
    /// rejected (ADR-008: the invariant the M4 editor's drag builds on).
    func movingPair(at sourceIndex: Int, to destination: Int) throws -> Script {
        guard bricks.indices.contains(sourceIndex), bricks[sourceIndex].opensLoop else {
            throw ScriptMoveError.sourceIsNotLoopOpener(index: sourceIndex)
        }
        guard let pair = range(ofPairAt: sourceIndex) else {
            throw ScriptMoveError.unbalancedPair(index: sourceIndex)
        }

        let block = Array(bricks[pair])
        var remaining = bricks
        remaining.removeSubrange(pair)

        guard destination >= 0, destination <= remaining.count else {
            throw ScriptMoveError.destinationOutOfBounds(index: destination)
        }
        guard !Self.insertion(at: destination, splitsAPairIn: remaining) else {
            throw ScriptMoveError.destinationSplitsPair(index: destination)
        }

        remaining.insert(contentsOf: block, at: destination)
        var moved = self
        moved.bricks = remaining
        return moved
    }

    /// Whether inserting between elements `index - 1` and `index` of `bricks`
    /// would land strictly inside some pair's `[opener … loopEnd]` block. Unpaired
    /// (unbalanced) bricks cannot be split, so they are ignored.
    private static func insertion(at index: Int, splitsAPairIn bricks: [Brick]) -> Bool {
        var openerStack: [Int] = []
        for (i, brick) in bricks.enumerated() {
            if brick.opensLoop {
                openerStack.append(i)
            } else if brick.isLoopEnd, let opener = openerStack.popLast() {
                if opener < index, index <= i {
                    return true
                }
            }
        }
        return false
    }
}
