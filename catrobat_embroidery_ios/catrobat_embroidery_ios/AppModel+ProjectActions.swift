import EditorCore
import EmbroideryEngine
import ProgramModel
import Projects
import StagePreview

/// The list's verbs (project management slice 8; brief D3, D4, D7, D9).
extension AppModel {
    /// Whether a live window other than this one holds `id` (D7). This window's own project is
    /// not "elsewhere": it may rename it by an edit and delete it.
    func isHeldElsewhere(_ id: ProjectID) -> Bool {
        !library.holders(of: id).subtracting([window]).isEmpty
    }

    /// "+": a blank draft, made unique and written only at its first change (D3), on its script.
    /// A project whose last save failed is retried first, and kept if that fails again, as for a
    /// sample. A new design is a new selection, so the previous run goes and the stage refits.
    func newDesign() {
        nameFieldLostFocus()
        guard canLeaveProject() else { return }
        startBlankDraft()
        path = [.script]
        palette.isPresented = false
        runner.reset()
        interaction.followFit()
    }

    /// Writes a copy at once under a new ID and a unique name (D3, D4), and selects nothing new:
    /// the window stays on what it holds. The open project is copied as it is on screen, so an
    /// edit whose save failed is not lost from the copy.
    func duplicate(_ id: ProjectID) {
        let source: Program? = if id == projectID {
            editor.program
        } else if case let .openable(program) = library.files.first(where: { $0.id == id })?.inspection {
            program
        } else {
            nil
        }
        guard let source else { return }
        if library.duplicate(source) == nil {
            listState.notice = .duplicateFailed
        }
    }

    /// Asks before deleting (D9): nothing is touched until `confirmDeletion()`.
    func requestDeletion(of row: ProjectRow) {
        listState.pendingDeletion = PendingDeletion(id: row.id, name: row.name)
    }

    func cancelDeletion() {
        listState.pendingDeletion = nil
    }

    /// Deletes what was asked about, once. The library removes the file first and changes
    /// nothing if that fails, or if another window holds the project (D7, D9); either is told.
    /// Deleting the open project leaves the window on a blank draft, back at the list (on
    /// compact; the split shows the draft beside it).
    func confirmDeletion() {
        guard let pending = listState.pendingDeletion else { return }
        listState.pendingDeletion = nil
        do {
            try library.delete(pending.id, requestedBy: window)
        } catch ProjectLibraryError.heldByAnotherWindow {
            listState.notice = .heldElsewhere(name: pending.name)
            return
        } catch {
            listState.notice = .deleteFailed(name: pending.name)
            return
        }
        guard pending.id == projectID else { return }
        startBlankDraft()
        path = []
        runner.reset()
        interaction.followFit()
    }

    /// Opens the rename sheet on `row`'s name (D8). The open project starts from the name on
    /// screen, which its file already has unless a save failed.
    func beginRename(of row: ProjectRow) {
        let name = row.id == projectID ? editor.program.name : row.name
        listState.rename = RenameSession(id: row.id, originalName: name, text: name)
    }

    func cancelRename() {
        listState.rename = nil
    }

    /// Saves the sheet's name, trimmed. An invalid one keeps the sheet open with what was typed
    /// and returns `false`. Otherwise the sheet closes: the open project is renamed by an edit
    /// (undoable, saved, keeping the run, D8), any other through the catalog, which refuses a
    /// project another window holds; a refusal or failure is told. An unchanged name writes
    /// nothing.
    @discardableResult
    func commitRename() -> Bool {
        guard let session = listState.rename, case let .success(name) = session.validation else { return false }
        listState.rename = nil
        guard name.value != session.originalName else { return true }
        guard session.id != projectID else {
            editor.apply(.renameProgram(name.value))
            return true
        }
        switch library.rename(session.id, to: name) {
        case .written:
            break
        case .held:
            listState.notice = .heldElsewhere(name: session.originalName)
        case .superseded, .blocked, .failed, .deleted:
            listState.notice = .renameFailed(name: session.originalName)
        }
        return true
    }

    /// The user has read the notice.
    func dismissListNotice() {
        listState.notice = nil
    }
}
