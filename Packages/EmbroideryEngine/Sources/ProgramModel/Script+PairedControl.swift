// Paired-control model logic (ADR-008): control bricks are begin/end blocks in
// the flat brick list — loops, and since Variables slice 2 Ifs, whose If/Else
// holds one `elseBranch` between its branches. Resolving a pair, validating balance, and moving a pair
// as one unit are model concerns with tests here — never view logic in M4.

/// Which kind of block a control brick belongs to (ADR-008, amended by Variables
/// slice 2). A closer closes only an opener of its own family.
public enum BlockFamily: Sendable, Equatable {
    case loop
    case conditional
}

/// A brick's part in the block structure of the flat list.
public enum BlockRole: Sendable, Equatable {
    /// Not a control marker: a motion, data, wait or embroidery brick.
    case leaf
    /// Opens a block that a later closer of the same family ends.
    case opener(BlockFamily)
    /// An If/Else's `elseBranch`, between its then- and else-branch.
    case divider
    /// Ends the nearest open block of its family.
    case closer(BlockFamily)
}

public extension Brick {
    /// The brick's part in the block structure. Listed, not defaulted: a new
    /// brick must say what it is.
    var blockRole: BlockRole {
        switch self {
        case .repeatLoop, .forever: .opener(.loop)
        case .ifThen, .ifElse: .opener(.conditional)
        case .elseBranch: .divider
        case .loopEnd: .closer(.loop)
        case .ifEnd: .closer(.conditional)
        case .moveNSteps, .turnLeft, .turnRight, .pointInDirection, .placeAt, .setX, .setY,
             .changeXBy, .changeYBy, .arc, .goThrough, .wait, .setVariable, .changeVariableBy, .stitch,
             .setThreadColor, .runningStitch, .zigZagStitch, .tripleStitch, .sewUp,
             .stopRunningStitch, .writeEmbroideryToFile:
            .leaf
        }
    }

    /// Whether this brick opens any block, a loop or an If.
    var opensBlock: Bool {
        if case .opener = blockRole { true } else { false }
    }

    /// Whether this brick closes any block, `loopEnd` or `ifEnd`.
    var closesBlock: Bool {
        if case .closer = blockRole { true } else { false }
    }

    /// Whether this brick is an If/Else's `elseBranch`.
    var isDivider: Bool {
        blockRole == .divider
    }

    /// The family of an opener, closer or divider; `nil` for a leaf.
    var blockFamily: BlockFamily? {
        switch blockRole {
        case .leaf: nil
        case let .opener(family), let .closer(family): family
        case .divider: .conditional
        }
    }

    /// Whether this opener needs exactly one `elseBranch` before its end: only
    /// `ifElse`.
    var expectsElse: Bool {
        if case .ifElse = self { true } else { false }
    }

    /// Whether this brick opens a loop that a later `loopEnd` closes
    /// (Catroid composite bricks: `RepeatBrick`, `ForeverBrick`). `wait` is a
    /// leaf despite sitting in the control category, so it does not open a pair.
    /// Loops only; an If is a block but not a loop (`opensBlock`).
    var opensLoop: Bool {
        blockRole == .opener(.loop)
    }

    /// Whether this brick closes a loop (Catroid `LoopEndBrick`).
    var isLoopEnd: Bool {
        blockRole == .closer(.loop)
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
    /// An If opener at `index` has no matching `ifEnd`.
    case unmatchedIfOpener(index: Int)
    /// An `ifEnd` at `index` closes an If that was never opened.
    case unmatchedIfEnd(index: Int)
    /// A closer at `index` whose family is not that of the innermost open block.
    case mismatchedEnd(index: Int)
    /// An `elseBranch` at `index` that is not directly inside an If/Else.
    case misplacedElse(index: Int)
    /// A second `elseBranch` at `index` in one If/Else.
    case duplicateElse(index: Int)
    /// The If/Else opened at `index` closes without an `elseBranch`.
    case missingElse(index: Int)
}

/// A block `validate()` has seen open and not yet closed.
private struct OpenBlock {
    let index: Int
    let family: BlockFamily
    let expectsElse: Bool
    var sawElse = false
}

/// Why a move-a-pair-as-a-unit request was rejected.
public enum ScriptMoveError: Error, Equatable {
    /// The source `index` is outside the brick list.
    case sourceOutOfBounds(index: Int)
    /// The brick at `index` opens no block — loop or If — so there is no block to
    /// move. The name predates the Ifs and is kept, as a public error case.
    case sourceIsNotLoopOpener(index: Int)
    /// The block opened at `index` does not resolve: no end of its family, or a
    /// missing, duplicate or misplaced else (unbalanced script).
    case unbalancedPair(index: Int)
    /// The destination lies outside the valid insertion range.
    case destinationOutOfBounds(index: Int)
}

public extension Script {
    /// The index of the closer that ends the block opened at `index`, resolved
    /// by a depth-tracking forward scan so nested blocks match their correct
    /// partners. The block resolves only if its own rows pass `validate()`: every
    /// closer of its family at every depth, every If/Else with exactly one else
    /// directly inside it. So a malformed block — even one malformed several levels
    /// down — is never deleted or moved as a whole (Codex reviews of PR 2a). `nil` if
    /// the brick does not open a block, or its block does not validate.
    func matchingEnd(ofBrickAt index: Int) -> Int? {
        guard bricks.indices.contains(index), case .opener = bricks[index].blockRole else {
            return nil
        }
        // The closer that brings the depth back to zero ends the block; the block
        // resolves only if its own rows validate — every closer of its family, at every
        // depth, and every If/Else with exactly one else directly inside it. One
        // definition, `validate()`'s, rather than a second set of rules that drifted
        // (Codex handover review of PR 2a, rounds 2 and 3).
        var depth = 0
        for cursor in index ..< bricks.count {
            switch bricks[cursor].blockRole {
            case .opener:
                depth += 1
            case .closer:
                depth -= 1
                if depth == 0 {
                    // In place, without copying the rows: this runs for every row's
                    // move actions on every edit.
                    return (try? validate(in: index ..< cursor + 1)) != nil ? cursor : nil
                }
            case .leaf, .divider:
                break
            }
        }
        return nil // opener never closed
    }

    /// The `elseBranch` directly inside the If/Else opened at `index` — the first
    /// at the block's own depth — or `nil` for any other brick, an If/Else
    /// without one, or a block that does not close.
    func matchingElse(ofBrickAt index: Int) -> Int? {
        guard bricks.indices.contains(index), bricks[index].expectsElse,
              let end = matchingEnd(ofBrickAt: index)
        else { return nil }
        var depth = 0
        for cursor in index + 1 ..< end {
            switch bricks[cursor].blockRole {
            case .opener: depth += 1
            case .closer: depth -= 1
            case .divider where depth == 0: return cursor
            case .divider, .leaf: break
            }
        }
        return nil
    }

    /// The contiguous `[opener … end]` range of the block opened at `index`,
    /// or `nil` if `index` is not a resolvable opener. This is the block that
    /// moves as one unit.
    func range(ofPairAt index: Int) -> ClosedRange<Int>? {
        guard let end = matchingEnd(ofBrickAt: index) else { return nil }
        return index ... end
    }

    /// Throws the first structural error found, scanning once with a stack of
    /// open blocks: a closer with no open block, a closer of the wrong family for
    /// the innermost one, an `elseBranch` not directly inside an If/Else (or a
    /// second one), an If/Else that closes without its else — and, once the list
    /// is scanned, an opener that was never closed, reporting the innermost
    /// (last-opened) when several remain. Typed (US-404) so a caller mapping the
    /// reason needs no unreachable `catch`.
    func validate() throws(ScriptValidationError) {
        try validate(in: bricks.indices)
    }

    /// `validate()` over `range` of the list, as if those rows were the whole script; indices
    /// in errors are absolute. `matchingEnd` uses it on one block's rows.
    private func validate(in range: Range<Int>) throws(ScriptValidationError) {
        var open: [OpenBlock] = []
        for index in range {
            let brick = bricks[index]
            switch brick.blockRole {
            case .leaf:
                break
            case let .opener(family):
                open.append(OpenBlock(index: index, family: family, expectsElse: brick.expectsElse))
            case .divider:
                guard let innermost = open.last, innermost.expectsElse else {
                    throw .misplacedElse(index: index)
                }
                guard !innermost.sawElse else {
                    throw .duplicateElse(index: index)
                }
                open[open.count - 1].sawElse = true
            case let .closer(family):
                guard let innermost = open.last else {
                    throw family == .loop ? .unmatchedLoopEnd(index: index) : .unmatchedIfEnd(index: index)
                }
                guard innermost.family == family else {
                    throw .mismatchedEnd(index: index)
                }
                guard !innermost.expectsElse || innermost.sawElse else {
                    throw .missingElse(index: innermost.index)
                }
                open.removeLast()
            }
        }
        if let unclosed = open.last {
            throw unclosed.family == .loop
                ? .unmatchedLoopOpener(index: unclosed.index)
                : .unmatchedIfOpener(index: unclosed.index)
        }
    }

    /// Returns a copy of the script with the pair opened at `sourceIndex` — its
    /// opener, matched end, and everything between — relocated as one
    /// contiguous block. `destination` is an insertion index into the list with
    /// the block already removed (`0 ... remaining.count`).
    ///
    /// Every in-bounds destination is valid: the block is a complete, balanced
    /// pair, so reinserting it anywhere — including inside another pair — nests
    /// it rather than splitting anything (ADR-008: nesting is a rendering
    /// concern; the moved pair travels as one unit, which this guarantees by
    /// construction). This is what lets the M4 editor drag a loop into another
    /// loop or reorder sibling loops. It **preserves** balance rather than
    /// enforcing it: a balanced script stays balanced, and a script that was
    /// already unbalanced *elsewhere* keeps that pre-existing imbalance — global
    /// balance is the caller's responsibility (`validate()`), not this move's.
    ///
    /// A move is rejected only when it is ill-formed: source out of bounds,
    /// source not a block opener, the *selected* opener's block does not resolve
    /// (`unbalancedPair`), or destination out of bounds.
    func movingPair(at sourceIndex: Int, to destination: Int) throws -> Script {
        guard bricks.indices.contains(sourceIndex) else {
            throw ScriptMoveError.sourceOutOfBounds(index: sourceIndex)
        }
        guard bricks[sourceIndex].opensBlock else {
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

        remaining.insert(contentsOf: block, at: destination)
        var moved = self
        moved.bricks = remaining
        return moved
    }
}
