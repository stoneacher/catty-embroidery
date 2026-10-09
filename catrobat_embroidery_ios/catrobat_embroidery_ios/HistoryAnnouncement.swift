import EditorCore
import Foundation
import ProgramModel
import UIKit

/// Which way a history transition went.
nonisolated enum HistoryDirection {
    case undo, redo
}

/// What VoiceOver says after an undo or redo (US-411): **which** edit was undone or redone, and
/// the brick it touched, because the change may be off-screen — a loop deleted eight rows up is
/// invisible, and the announcement is all a VoiceOver user gets.
///
/// `UndoStack` keeps snapshots, not actions, so the edit is **worked out from the two programs**:
/// the one that turned the older program into the newer, wherever the transition went. A
/// parallel stack of labels would have to mirror ADR-036's folds, net-zero drops and evictions —
/// re-implementing the stack in the app to name what it already holds.
///
/// Only the first script is read: it is the only one M4 edits and the one the list shows.
nonisolated enum HistoryAnnouncement {
    static func text(
        _ direction: HistoryDirection, from: Program, to: Program, locale: Locale = .current
    ) -> String {
        let (older, newer) = direction == .undo ? (to, from) : (from, to)
        var resource = resource(direction, for: Edit(from: older, to: newer), locale: locale)
        resource.locale = locale
        return String(localized: resource)
    }

    /// Posts `text` to VoiceOver. The editor's default announcer.
    @MainActor
    static func post(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    /// One whole sentence per edit and direction, so translators never join fragments.
    private static func resource(
        _ direction: HistoryDirection, for edit: Edit, locale: Locale
    ) -> LocalizedStringResource {
        let undo = direction == .undo
        func label(_ brick: Brick) -> String {
            BrickRowPresentation.text(of: brick, locale: locale)
        }
        switch edit {
        case let .adding(brick):
            return undo ? .historyUndidAdding(label(brick)) : .historyRedidAdding(label(brick))
        case let .deleting(brick):
            return undo ? .historyUndidDeleting(label(brick)) : .historyRedidDeleting(label(brick))
        case let .moving(brick):
            return undo ? .historyUndidMoving(label(brick)) : .historyRedidMoving(label(brick))
        case let .changing(older, newer):
            // Named as it reads **now**, after the transition: the row the user will find.
            return undo ? .historyUndidChanging(label(older)) : .historyRedidChanging(label(newer))
        case .renaming:
            return undo ? .historyUndidRenaming : .historyRedidRenaming
        case .other:
            return undo ? .historyUndidEdit : .historyRedidEdit
        }
    }

    /// The edit that turns one program into another, as far as the first script and the name
    /// can tell.
    private enum Edit {
        case adding(Brick)
        case deleting(Brick)
        case moving(Brick)
        case changing(older: Brick, newer: Brick)
        case renaming
        case other

        init(from older: Program, to newer: Program) {
            let old = older.scenes.first?.objects.first?.scripts.first?.bricks ?? []
            let new = newer.scenes.first?.objects.first?.scripts.first?.bricks ?? []
            guard old != new else {
                self = older.name == newer.name ? .other : .renaming
                return
            }
            // The differing window: everything between the common prefix and suffix.
            var prefix = 0
            while prefix < min(old.count, new.count), old[prefix] == new[prefix] {
                prefix += 1
            }
            var suffix = 0
            let shorter = min(old.count, new.count)
            while suffix < shorter - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
                suffix += 1
            }
            let removed = Array(old[prefix ..< old.count - suffix])
            let inserted = Array(new[prefix ..< new.count - suffix])

            switch (removed.isEmpty, inserted.isEmpty) {
            case (true, false): self = .adding(inserted[0])
            case (false, true): self = .deleting(removed[0])
            case (false, false) where removed.count == 1 && inserted.count == 1:
                self = .changing(older: removed[0], newer: inserted[0])
            case (false, false):
                self = Self.moved(from: removed, to: inserted).map(Edit.moving) ?? .other
            case (true, true):
                self = .other // Unreachable: equal arrays returned above.
            }
        }

        /// The head of the block a move carried, if `inserted` is `removed` with one block taken
        /// from one end of the window and put at the other.
        ///
        /// A move carries exactly one **block** — a leaf, or a whole pair (ADR-045) — so only two
        /// splits can be right: the block at the window's front moved down past the rest, or the
        /// block at its back moved up. Checking just those is linear, and it never mistakes a lone
        /// opener or `loopEnd` for a block — the reviewer's leaf-into-a-loop case, where the
        /// other half of the rotation is half a pair (`swift-code-reviewer`, Editor UI feature).
        private static func moved(from removed: [Brick], to inserted: [Brick]) -> Brick? {
            guard removed.count == inserted.count, removed.count > 1 else { return nil }
            if let front = blockLength(atFrontOf: removed), rotated(removed, at: front) == inserted {
                return removed[0]
            }
            if let back = blockLength(atBackOf: removed), rotated(removed, at: removed.count - back) == inserted {
                return removed[removed.count - back]
            }
            return nil
        }

        /// `bricks` with everything before `split` moved to the end.
        private static func rotated(_ bricks: [Brick], at split: Int) -> [Brick] {
            Array(bricks[split...] + bricks[..<split])
        }

        /// A leaf's length is 1; an opener's is its whole pair, if the pair closes in `bricks`.
        private static func blockLength(atFrontOf bricks: [Brick]) -> Int? {
            if bricks[0].isLoopEnd {
                return nil
            }
            guard bricks[0].opensLoop else { return 1 }
            return Script(bricks: bricks).range(ofPairAt: 0)?.count
        }

        /// A leaf's length is 1; a `loopEnd`'s is its whole pair, if the pair opens in `bricks`.
        private static func blockLength(atBackOf bricks: [Brick]) -> Int? {
            let last = bricks.count - 1
            if bricks[last].opensLoop {
                return nil
            }
            guard bricks[last].isLoopEnd else { return 1 }
            return Script(bricks: bricks).matchingOpener(ofLoopEndAt: last).map { last - $0 + 1 }
        }
    }
}
