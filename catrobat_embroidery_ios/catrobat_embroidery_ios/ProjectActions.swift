import EmbroideryEngine
import Foundation
import Projects

/// Why a row's action is disabled now (brief D7). One case today; an enum so the menu can
/// show whichever reason the guard reports rather than a bare disabled item.
enum ProjectActionBlock: Equatable {
    /// Another window holds the project: its rename is that window's edit, and deleting it
    /// would pull the design out from under it.
    case openInAnotherWindow

    var reason: LocalizedStringResource {
        switch self {
        case .openInAnotherWindow: .projectActionHeld
        }
    }
}

/// One of a row's actions, and whether it is allowed now.
struct ProjectActionState: Equatable {
    let action: ProjectRowAction
    let blocked: ProjectActionBlock?

    var isEnabled: Bool {
        blocked == nil
    }
}

/// Which of a row's actions are allowed now (project management slice 8). Pure, so the menu's
/// disabled items and their reasons are testable without a view (`ProjectActionStateTests`).
///
/// The library refuses the same things (`ProjectLibraryError.heldByAnotherWindow`, `.held`);
/// this is the presentation of that guard, not a replacement for it.
enum ProjectActions {
    static func states(for row: ProjectRow, heldElsewhere: Bool) -> [ProjectActionState] {
        row.actions.map { action in
            switch action {
            case .rename, .delete:
                ProjectActionState(action: action, blocked: heldElsewhere ? .openInAnotherWindow : nil)
            case .open, .duplicate:
                ProjectActionState(action: action, blocked: nil)
            }
        }
    }
}

/// A delete the user asked for and has not yet confirmed (brief D9).
struct PendingDeletion: Equatable {
    let id: ProjectID
    /// The name the dialog asks about, as the row showed it.
    let name: String
}

/// What the list tells the user after an action did not happen.
enum ProjectListNotice: Equatable {
    case deleteFailed(name: String)
    case heldElsewhere(name: String)
    case duplicateFailed
    case renameFailed(name: String)

    var title: LocalizedStringResource {
        switch self {
        case let .deleteFailed(name): .projectNoticeDeleteFailedTitle(name)
        case let .heldElsewhere(name): .projectNoticeHeldTitle(name)
        case .duplicateFailed: .projectNoticeDuplicateFailedTitle
        case let .renameFailed(name): .projectNoticeRenameFailedTitle(name)
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .deleteFailed: .projectNoticeDeleteFailedMessage
        case .heldElsewhere: .projectNoticeHeldMessage
        case .duplicateFailed: .projectNoticeDuplicateFailedMessage
        case .renameFailed: .projectNoticeRenameFailedMessage
        }
    }
}

/// The list's transient state, per window: one stored property on `AppModel` (at SwiftLint's
/// length limit), owned there for ADR-023's reason — a dialog held in the list view would be
/// lost when an iPad resize swaps the containers.
struct ProjectListState: Equatable {
    var pendingDeletion: PendingDeletion?
    var notice: ProjectListNotice?
    var rename: RenameSession?
}

/// The rename sheet's transient buffer (brief D8): the raw text, possibly invalid, which reaches
/// the program or the catalog only through `AppModel.commitRename()` as a valid name.
struct RenameSession: Equatable, Identifiable {
    let id: ProjectID
    /// The name the sheet started from, which the notices name and an unchanged save compares.
    let originalName: String
    var text: String

    var validation: Result<DesignName, DesignNameProblem> {
        DesignName.validating(text)
    }

    /// Save is disabled while the name is invalid (D8).
    var canSave: Bool {
        if case .success = validation { true } else { false }
    }
}
