import EditorCore
import Foundation
import ProgramModel

// The values `ProjectLibrary` takes and returns (project management slices 4–5), apart from
// `SaveRevision`, which stays beside the one method allowed to mint it.

/// A project launch opened.
public struct OpenedProject: Equatable, Sendable {
    public let id: ProjectID
    public let program: Program

    public init(id: ProjectID, program: Program) {
        self.id = id
        self.program = program
    }
}

/// A launch candidate whose file was refused.
public struct ProjectRefusal: Equatable, Sendable {
    public let id: ProjectID
    public let reason: ProgramLoadError

    public init(id: ProjectID, reason: ProgramLoadError) {
        self.id = id
        self.reason = reason
    }
}

/// What a window opens on (brief D6): a project, or nothing — the window then starts a draft
/// under a fresh ID — and the candidates refused on the way.
public struct LaunchResolution: Equatable, Sendable {
    public let opened: OpenedProject?
    public let refusals: [ProjectRefusal]

    public init(opened: OpenedProject?, refusals: [ProjectRefusal]) {
        self.opened = opened
        self.refusals = refusals
    }
}

/// What opening a project found.
public enum ProjectOpening: Equatable, Sendable {
    case opened(Program)
    /// No file: never saved, or deleted elsewhere.
    case missing
    case refused(ProgramLoadError)
}

/// Why a project is not being saved.
public enum ProjectSaveFailure: Equatable, Sendable {
    /// The last write threw.
    case saveFailed
    /// The project's file cannot be opened, so nothing may overwrite it (brief D11).
    case refusedDocument
}

/// What became of one save request.
public enum ProjectSaveOutcome: Equatable, Sendable {
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
public enum ProjectLibraryError: Error, Equatable {
    /// Another window holds the project (brief D7).
    case heldByAnotherWindow
}

/// One window, as the registry knows it. Explicit rather than an object identity, so a late
/// message from a window can be told apart from its successor's.
public struct WindowToken: Hashable, Sendable {
    private let rawValue = UUID()

    public init() {}
}
