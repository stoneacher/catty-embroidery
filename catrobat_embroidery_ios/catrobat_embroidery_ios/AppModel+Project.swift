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

    /// The window is going away: it no longer holds its project (brief D7).
    func close() {
        library.unregister(window, from: projectID)
    }
}
