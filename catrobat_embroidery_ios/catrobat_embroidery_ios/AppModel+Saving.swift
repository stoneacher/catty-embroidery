import ProgramModel
import Projects

/// What this window saves, and when (ADR-037 per project; project management slices 5 and 8).
///
/// Moved out of `AppModel.swift` at SwiftLint's length limit, which is why `AppModel.project`'s
/// setter is internal: `WindowProject`'s own transitions keep its invariants.
extension AppModel {
    /// Stamps the working program with a new revision and saves it to this window's project —
    /// for every user-initiated change and nothing else (ADR-037; not a rejected or unchanging
    /// edit, an opening or a sample pick, brief D3).
    func persistWorkingProgram() {
        let revision = library.mintRevision()
        project.changed(revision)
        recordSave(library.save(editor.program, to: projectID, revision: revision))
    }

    /// What a save means for a draft, through a change or the lifecycle retry (Codex, slice 5):
    /// the first written one gives it a file, whose name now counts, and makes it the last
    /// opened. Until then it reserves its **current** name, which a rename may change.
    @discardableResult
    func recordSave(_ outcome: ProjectSaveOutcome) -> ProjectSaveOutcome {
        guard outcome == .written, project.written() else {
            if !project.hasFile {
                library.register(window, owner: self, holding: projectID, draftName: editor.program.name)
            }
            return outcome
        }
        library.register(window, owner: self, holding: projectID, draftName: nil)
        library.markOpened(projectID)
        return outcome
    }

    /// The window stopped being active: save what it holds, carrying the revision of the change
    /// that produced it, so the save is dropped if another window has changed the program since.
    func sceneDidLeaveActive() {
        guard let heldRevision = project.heldRevision else { return }
        recordSave(library.save(editor.program, to: projectID, revision: heldRevision))
    }

    /// Retries a failed save before the window leaves; only a failed retry keeps it (PR #78 rounds 4–5).
    func canLeaveProject() -> Bool {
        guard let heldRevision = project.heldRevision, saveFailure == .saveFailed else { return true }
        return recordSave(library.save(editor.program, to: projectID, revision: heldRevision)) != .failed
    }
}
