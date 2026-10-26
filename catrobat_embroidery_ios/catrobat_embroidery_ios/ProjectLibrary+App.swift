import Foundation
import Projects

/// A project found at launch and not opened, until the user has been told. Its file stays
/// where it is (brief D11). App-side since US-329: the library never uses it, only `AppModel`
/// and `AutosaveNotice` do.
struct ProgramRefusal: Equatable {
    let reason: ProgramLoadError
}

extension ProjectLibrary {
    /// For previews: saves into a scratch directory, never the user's Documents.
    static var preview: ProjectLibrary {
        ProjectLibrary(
            store: DocumentsProjectStore(directory: .temporaryDirectory.appending(path: "preview-projects")),
            lastOpened: LastOpenedProject(defaults: UserDefaults(suiteName: "preview-projects") ?? .standard)
        )
    }
}
