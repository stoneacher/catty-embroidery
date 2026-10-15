import EditorCore
import ProgramModel

/// What changed between two brick lists, as the editor's verbs can change one: the common prefix
/// and suffix, the differing window between them, and — when the change is one block moved — where
/// that block went.
///
/// Shared by `HistoryAnnouncement`, which names the edit, and `RowIdentities`, which carries row
/// IDs across it, so "what moved" is decided in one place for both.
nonisolated struct BrickListDiff {
    /// Rows equal at the front of both lists.
    let prefix: Int
    /// Rows equal at the back of both lists, not overlapping the prefix.
    let suffix: Int
    /// The old list's differing window.
    let removed: [Brick]
    /// The new list's differing window.
    let inserted: [Brick]
    /// When the window is one block moved from one end to the other: rotating `removed` left by
    /// `moveSplit` gives `inserted`.
    let moveSplit: Int?
    /// The head of that moved block.
    let movedBlockHead: Brick?

    init(from old: [Brick], to new: [Brick]) {
        let shorter = min(old.count, new.count)
        var prefix = 0
        while prefix < shorter, old[prefix] == new[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < shorter - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }
        self.prefix = prefix
        self.suffix = suffix
        removed = Array(old[prefix ..< old.count - suffix])
        inserted = Array(new[prefix ..< new.count - suffix])
        let move = Self.move(from: removed, to: inserted)
        moveSplit = move?.split
        movedBlockHead = move?.head
    }

    /// A move carries exactly one **block** — a leaf, or a whole pair (ADR-045) — so only two
    /// splits can be right: the block at the window's front moved down past the rest, or the block
    /// at its back moved up. Checking just those is linear, and it never mistakes a lone opener or
    /// `loopEnd` for a block — a leaf dragged into a loop, where the other half of the rotation is
    /// half a pair (`swift-code-reviewer`, Editor UI feature).
    private static func move(from removed: [Brick], to inserted: [Brick]) -> (split: Int, head: Brick)? {
        guard removed.count == inserted.count, removed.count > 1 else { return nil }
        if let front = blockLength(atFrontOf: removed), rotated(removed, at: front) == inserted {
            return (front, removed[0])
        }
        if let back = blockLength(atBackOf: removed), rotated(removed, at: removed.count - back) == inserted {
            return (removed.count - back, removed[removed.count - back])
        }
        return nil
    }

    /// `elements` with everything before `split` moved to the end.
    static func rotated<Element>(_ elements: [Element], at split: Int) -> [Element] {
        Array(elements[split...] + elements[..<split])
    }

    /// A leaf's length is 1; an opener's is its whole pair, if the pair closes in `bricks`.
    private static func blockLength(atFrontOf bricks: [Brick]) -> Int? {
        guard let first = bricks.first, !first.isLoopEnd else { return nil }
        guard first.opensLoop else { return 1 }
        return Script(bricks: bricks).range(ofPairAt: 0)?.count
    }

    /// A leaf's length is 1; a `loopEnd`'s is its whole pair, if the pair opens in `bricks`.
    private static func blockLength(atBackOf bricks: [Brick]) -> Int? {
        guard let last = bricks.indices.last, !bricks[last].opensLoop else { return nil }
        guard bricks[last].isLoopEnd else { return 1 }
        return Script(bricks: bricks).matchingOpener(ofLoopEndAt: last).map { last - $0 + 1 }
    }
}
