import EditorCore
import EmbroideryEngine
import Foundation
import ProgramModel
import Projects

/// The stage's name field, as one name (project management slice 5; brief D4, D8).
///
/// The field edits `nameDraft`, never the program: an invalid value must not reach the
/// program, the history, the export or the disk. A commit turns a valid draft into a
/// `.renameProgram` edit, which goes through the one door like any other — undoable, saved,
/// and judged rename-only by `programChanged(from:to:)`, so it keeps the run.
extension AppModel {
    /// The draft's verdict, for the field's counter and error line.
    var nameDraftValidation: Result<DesignName, DesignNameProblem> {
        DesignName.validating(nameDraft)
    }

    /// Commits the draft: a valid one becomes the program's name (trimmed, as the field
    /// stores it), and the field shows it; an invalid one is abandoned and the field returns to
    /// the committed name. Returns whether the draft was valid.
    ///
    /// Reached through `submitName()` and `nameFieldLostFocus()`, **never per keystroke**: each
    /// rename is an edit and re-prepares the export.
    @discardableResult
    func commitName() -> Bool {
        guard case let .success(name) = nameDraftValidation else {
            syncName()
            return false
        }
        if name.value != editor.program.name {
            editor.apply(.renameProgram(name.value))
        }
        syncName()
        return true
    }

    /// Return in the stage's field (slice 9, D8): a valid draft is committed; an invalid one
    /// stays as typed, so the field can keep focus and show the error. Returns whether it was
    /// committed.
    @discardableResult
    func submitName() -> Bool {
        guard case .success = nameDraftValidation else { return false }
        return commitName()
    }

    /// Focus left the stage's field (D8): a valid draft is committed, an invalid one gives way
    /// to the committed name.
    func nameFieldLostFocus() {
        commitName()
    }

    /// One name (brief D4): the export's name and the stage's title are the program's, and the
    /// field shows it again. Setting `exporter.name` discards a file prepared under the old name.
    func syncName() {
        let name = editor.program.name
        exporter.name = name
        nameDraft = name
        retitle(name.isEmpty ? .programTitleUntitled : .programTitleNamed(name))
    }

    /// A new design's name (brief D4): the catalog's, or ASCII "Design" if a translation is
    /// not a valid `LA` name, so a fresh window never opens on an error the user did not cause
    /// (US-320). Made unique when the draft starts.
    static var defaultName: DesignName {
        (try? DesignName.validating(String(localized: .projectDefaultName)).get()) ?? ProjectLibrary.fallbackName
    }
}
