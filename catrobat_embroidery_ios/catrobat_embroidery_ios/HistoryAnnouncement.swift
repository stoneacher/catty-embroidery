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
            let diff = BrickListDiff(from: old, to: new)
            switch (diff.removed.isEmpty, diff.inserted.isEmpty) {
            case (true, false): self = .adding(diff.inserted[0])
            case (false, true): self = .deleting(diff.removed[0])
            case (false, false) where diff.removed.count == 1 && diff.inserted.count == 1:
                self = .changing(older: diff.removed[0], newer: diff.inserted[0])
            case (false, false):
                self = diff.movedBlockHead.map(Edit.moving) ?? .other
            case (true, true):
                self = .other // Unreachable: equal arrays returned above.
            }
        }
    }
}
