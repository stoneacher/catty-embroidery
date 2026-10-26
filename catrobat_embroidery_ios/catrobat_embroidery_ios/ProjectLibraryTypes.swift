import EditorCore
import Foundation
import ProgramModel

// The values `ProjectLibrary` takes and returns (project management slices 4–5), apart from
// `SaveRevision`, which stays beside the one method allowed to mint it; and the library's
// preview factory.

/// A project found at launch and not opened, until the user has been told. Its file stays
/// where it is (brief D11).
struct ProgramRefusal: Equatable {
    let reason: ProgramLoadError
}

/// A project launch opened.
struct OpenedProject: Equatable {
    let id: ProjectID
    let program: Program
}

/// A launch candidate whose file was refused.
struct ProjectRefusal: Equatable {
    let id: ProjectID
    let reason: ProgramLoadError
}

/// What a window opens on (brief D6): a project, or nothing — the window then starts a draft
/// under a fresh ID — and the candidates refused on the way.
struct LaunchResolution: Equatable {
    let opened: OpenedProject?
    let refusals: [ProjectRefusal]
}

/// What opening a project found.
enum ProjectOpening: Equatable {
    case opened(Program)
    /// No file: never saved, or deleted elsewhere.
    case missing
    case refused(ProgramLoadError)
}

/// Why a project is not being saved.
enum ProjectSaveFailure: Equatable {
    /// The last write threw.
    case saveFailed
    /// The project's file cannot be opened, so nothing may overwrite it (brief D11).
    case refusedDocument
}

/// What became of one save request.
enum ProjectSaveOutcome: Equatable {
    case written
    /// A newer revision of this project was already accepted; this one was dropped.
    case superseded
    /// The project's file was refused, and nothing may overwrite it; for a catalog rename, also
    /// a project with no file.
    case blocked
    /// Another window holds the project, so the catalog may not change it (brief D7).
    case held
    case failed
    /// The project was deleted; a late save must not bring the file back.
    case deleted
}

/// Why the catalog refused to delete a project.
enum ProjectLibraryError: Error, Equatable {
    /// Another window holds the project (brief D7).
    case heldByAnotherWindow
}

/// One window, as the registry knows it. Explicit rather than an object identity, so a late
/// message from a window can be told apart from its successor's.
struct WindowToken: Hashable, Sendable {
    private let rawValue = UUID()
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
