import Projects

/// The project a window holds and how far it has got (project management slice 7, extracted
/// from `AppModel`, which had reached SwiftLint's length limit with this state `private`).
///
/// A value with named transitions rather than three loose properties, so a window cannot be on
/// a new project while still holding the old one's revision: switching is replacing the whole
/// value (`.draft`, `.opened`), and only `changed(_:)` and `written()` move it on from there.
struct WindowProject: Equatable {
    /// An existing project, or a draft with no file yet (brief D3).
    let id: ProjectID

    /// Whether `id` has a file this window opened or wrote. A draft has none until its first
    /// change is written.
    private(set) var hasFile: Bool

    /// The revision of exactly the program this window holds; `nil` until it changes one. Not a
    /// "has edited" flag, which would let a window that another window has superseded put an
    /// older program back (ADR-037, D7).
    private(set) var heldRevision: SaveRevision?

    /// A fresh ID with no file, which the first change writes.
    static func draft(_ id: ProjectID) -> WindowProject {
        WindowProject(id: id, hasFile: false, heldRevision: nil)
    }

    /// A project read from its file. It holds no revision, so the window writes nothing until
    /// the user changes something.
    static func opened(_ id: ProjectID) -> WindowProject {
        WindowProject(id: id, hasFile: true, heldRevision: nil)
    }

    /// The user changed the program; `revision` stamps the save that follows.
    mutating func changed(_ revision: SaveRevision) {
        heldRevision = revision
    }

    /// A save was written. Returns whether that gave a draft its file — the moment it becomes
    /// a project whose name counts and that is the last opened.
    mutating func written() -> Bool {
        defer { hasFile = true }
        return !hasFile
    }

    /// The name the registry reserves for this window: a draft's current name, or `nil` once
    /// there is a file, whose name the library already reads (brief D4).
    func draftName(_ programName: String) -> String? {
        hasFile ? nil : programName
    }
}
