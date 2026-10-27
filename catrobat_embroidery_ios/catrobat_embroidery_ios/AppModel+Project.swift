import Projects

/// The window's project, as other code reads it (project management slice 5).
///
/// Moved out of `AppModel.swift`, which is at SwiftLint's length limit; neither member writes
/// the class's private state.
extension AppModel {
    /// The launch refusal the alert shows now, until the user has read it.
    var launchRefusal: ProgramRefusal? {
        launchRefusals.first
    }

    /// Why this window's project is not being saved, or `nil` while it is.
    var saveFailure: ProjectSaveFailure? {
        library.failure(for: projectID)
    }

    /// Opens a project from the list (slice 7). Tapping the project already open only shows its
    /// script: reloading it would throw away its undo history. Otherwise a project whose last
    /// save failed is retried first and kept if that fails again, as for a sample; a refused or
    /// missing file leaves the window where it is (the library re-badges or drops its row).
    /// Opening writes nothing; it is a new selection, so the previous run goes. A project
    /// another window holds opens here too (D7).
    func openProject(_ id: ProjectID) {
        guard id != projectID else {
            path = [.script]
            return
        }
        guard canLeaveProject(), case let .opened(program) = library.open(id) else { return }
        adopt(id, program: program)
        library.markOpened(id)
        runner.reset()
    }

    /// The window is going away: it no longer holds its project (brief D7).
    func close() {
        library.unregister(window, from: projectID)
    }
}
