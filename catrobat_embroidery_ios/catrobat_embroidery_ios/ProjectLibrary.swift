import EditorCore
import EmbroideryEngine
import Foundation
import Observation
import ProgramModel

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
    /// The project's file was refused, and nothing may overwrite it.
    case blocked
    case failed
    /// The project was deleted; a late save must not bring the file back.
    case deleted
}

/// One window, as the registry knows it. Explicit rather than an object identity, so a late
/// message from a window can be told apart from its successor's.
struct WindowToken: Hashable, Sendable {
    private let rawValue = UUID()
}

/// The one guard on every project file, shared by every window (project management slice 4;
/// brief D3, D7, D9, D11). It replaces `ProgramAutosave`, and keeps its reasoning: app-scoped
/// because every window may write the same files, so the rule deciding which write wins has
/// to see all of them; synchronous on the main actor, so writes are ordered by construction.
///
/// **ADR-037's last writer wins, per project.** Revisions are minted from one counter, so
/// their order is the order the user acted in, but each project keeps its own newest accepted
/// revision and its own failure: what one project accepted says nothing about another.
///
/// **Refused files are never written** (D11). A refusal, found by the listing or by opening
/// the file, blocks every save to that ID until it is re-probed as openable or missing, or
/// deleted. **A deleted project stays deleted** (D9): its ID is remembered for the life of the
/// process, so a late save from a window that still held it cannot recreate the file.
///
/// The summaries in `files` are kept in step with every write and delete here, so the list
/// never rescans the disk after launch: this process is the files' only writer.
@MainActor
@Observable
final class ProjectLibrary {
    /// The name a generated program gets when it has no valid one of its own.
    static let fallbackName: DesignName = {
        guard case let .success(name) = DesignName.validating("Design") else {
            preconditionFailure("the fallback design name must be valid")
        }
        return name
    }()

    private let store: any ProjectStoring
    private let makeID: () -> ProjectID
    private let now: () -> Date

    /// Every project file, refused ones included, in no particular order.
    private(set) var files: [ProjectFile] = []

    private var failures: [ProjectID: ProjectSaveFailure] = [:]

    /// Which project each window holds, and the name of the draft it holds, if any.
    private var registry: [WindowToken: Registration] = [:]

    @ObservationIgnored private var revisions = RevisionCounter()
    @ObservationIgnored private var highestAccepted: [ProjectID: SaveRevision] = [:]
    @ObservationIgnored private var blocked: Set<ProjectID> = []
    @ObservationIgnored private var tombstones: Set<ProjectID> = []

    /// Lists the projects once. A listing that fails leaves the list empty; nothing is written
    /// on that account, and each project is still guarded when it is opened.
    init(
        store: any ProjectStoring,
        makeID: @escaping () -> ProjectID = { ProjectID(UUID()) },
        now: @escaping () -> Date = { .now }
    ) {
        self.store = store
        self.makeID = makeID
        self.now = now
        files = (try? store.list()) ?? []
        for file in files {
            if case .refused = file.inspection {
                block(file.id)
            }
        }
    }

    // MARK: Revisions and saving

    /// A revision newer than every one minted before it, for any project.
    func mintRevision() -> SaveRevision {
        revisions.mint()
    }

    /// A fresh ID for a draft: no file exists for it until its first save (brief D3).
    func makeDraftID() -> ProjectID {
        makeID()
    }

    func failure(for id: ProjectID) -> ProjectSaveFailure? {
        failures[id]
    }

    /// Saves `program` as `id` unless a newer revision of `id` was already accepted, the file
    /// is refused, or the project was deleted.
    ///
    /// As in `ProgramAutosave`, an **equal** revision is written again (the same edit asking
    /// twice), and *accepted* is the line rather than *written*: a failed newer write must
    /// still stop an older one landing after it.
    @discardableResult
    func save(_ program: Program, to id: ProjectID, revision: SaveRevision) -> ProjectSaveOutcome {
        guard !tombstones.contains(id) else {
            return .deleted
        }
        if let accepted = highestAccepted[id], revision < accepted {
            return .superseded
        }
        highestAccepted[id] = revision
        guard !blocked.contains(id) else {
            return .blocked
        }
        do {
            try store.save(program, as: id)
        } catch {
            failures[id] = .saveFailed
            return .failed
        }
        failures[id] = nil
        upsert(ProjectFile(id: id, inspection: .openable(program), modified: now()))
        return .written
    }

    // MARK: Opening

    /// Reads `id`, writing nothing. A refusal blocks the project; an openable or missing file
    /// lifts a block, since there is no longer anything to protect.
    func open(_ id: ProjectID) -> ProjectOpening {
        let loaded: Program?
        do {
            loaded = try store.load(id)
        } catch {
            block(id)
            return .refused(error)
        }
        unblock(id)
        guard let loaded else {
            return .missing
        }
        return .opened(loaded)
    }

    // MARK: Catalog operations

    /// Removes the file first; only once it is gone are the tombstone, the summary and the
    /// project's block and failure changed. A removal that throws changes nothing (brief D9).
    func delete(_ id: ProjectID) throws {
        try store.delete(id)
        tombstones.insert(id)
        files.removeAll { $0.id == id }
        blocked.remove(id)
        failures[id] = nil
    }

    /// Writes `program` at once as a new project with a generated, unique name (brief D3, D4),
    /// and returns its ID, or `nil` if the write failed and no project was made.
    func duplicate(_ program: Program) -> ProjectID? {
        let base = (try? DesignName.validating(program.name).get()) ?? Self.fallbackName
        var copy = program
        copy.name = uniquedName(base).value
        let id = makeID()
        guard save(copy, to: id, revision: mintRevision()) == .written else {
            return nil
        }
        return id
    }

    /// Renames a project no window holds: load, rename, save under a fresh revision, so a
    /// window's save from before the rename cannot bring the old name back (brief D8). A
    /// refused or missing project is `.blocked`, and nothing is written.
    func rename(_ id: ProjectID, to name: DesignName) -> ProjectSaveOutcome {
        guard case let .opened(program) = open(id) else {
            return .blocked
        }
        var renamed = program
        renamed.name = name.value
        return save(renamed, to: id, revision: mintRevision())
    }

    /// `name` made unique among every name the user can see: persisted projects', refused
    /// files' readable names, and the drafts windows hold (brief D4).
    func uniquedName(_ name: DesignName) -> DesignName {
        let persisted = files.compactMap { file -> String? in
            switch file.inspection {
            case let .openable(program): program.name
            case let .refused(_, name): name
            }
        }
        let drafts = liveRegistrations.compactMap(\.draftName)
        return name.uniqued(avoiding: persisted + drafts)
    }

    // MARK: Registry (D7)

    /// Records that `window` now holds `id`, replacing whatever it held before. `owner` is
    /// held weakly, only so a window torn down without unregistering stops counting.
    func register(_ window: WindowToken, owner: AnyObject, holding id: ProjectID, draftName: String?) {
        registry[window] = Registration(owner: owner, projectID: id, draftName: draftName)
    }

    /// Records that `window` no longer holds `id`. A late message about a project the window
    /// has since left does nothing, so it cannot remove its successor.
    func unregister(_ window: WindowToken, from id: ProjectID) {
        guard registry[window]?.projectID == id else {
            return
        }
        registry[window] = nil
    }

    /// The live windows holding `id`.
    func holders(of id: ProjectID) -> Set<WindowToken> {
        Set(registry.compactMap { window, registration in
            registration.owner != nil && registration.projectID == id ? window : nil
        })
    }

    private var liveRegistrations: [Registration] {
        registry.values.filter { $0.owner != nil }
    }

    // MARK: Private

    private func block(_ id: ProjectID) {
        blocked.insert(id)
        failures[id] = .refusedDocument
    }

    private func unblock(_ id: ProjectID) {
        guard blocked.remove(id) != nil else {
            return
        }
        failures[id] = nil
    }

    private func upsert(_ file: ProjectFile) {
        if let index = files.firstIndex(where: { $0.id == file.id }) {
            files[index] = file
        } else {
            files.append(file)
        }
    }
}

private struct Registration {
    weak var owner: AnyObject?
    let projectID: ProjectID
    let draftName: String?
}

extension ProjectLibrary {
    /// For previews: saves into a scratch directory, never the user's Documents.
    static var preview: ProjectLibrary {
        ProjectLibrary(store: DocumentsProjectStore(directory: .temporaryDirectory.appending(path: "preview-projects")))
    }
}
