import EditorCore
import EmbroideryEngine
import Foundation
import Observation
import ProgramModel

/// The order in which programs were produced, across every window and project.
///
/// Minted only by `ProjectLibrary.mintRevision()`, on the main actor, at the moment of the edit
/// or replacement it stamps — so the order of revisions is the order the user acted in.
/// `nonisolated` because a `Comparable` conformance on a main-actor type is itself main-actor
/// isolated, and the comparison should not care where it runs.
nonisolated struct SaveRevision: Comparable, Sendable {
    fileprivate let value: Int

    static func < (lhs: SaveRevision, rhs: SaveRevision) -> Bool {
        lhs.value < rhs.value
    }
}

/// The one guard on every project file, shared by every window (project management slice 4;
/// brief D3, D7, D9, D11). It replaced M4's `ProgramAutosave` in slice 5, and keeps its
/// reasoning: app-scoped
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
/// The summaries in `files` are kept in step with every write, delete and re-probe here, so
/// the list never rescans the disk after launch: this process is the files' only writer.
///
/// `files`, the failures and the registry are observed — windows show the list, their banner
/// and "held by another window" from them; the guard state is bookkeeping and is not.
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
    private let lastOpened: LastOpenedProject
    private let makeID: () -> ProjectID
    private let now: () -> Date

    /// Every project file, refused ones included, in no particular order.
    private(set) var files: [ProjectFile] = []

    private var failures: [ProjectID: ProjectSaveFailure] = [:]

    /// Which project each window holds, and the name of the draft it holds, if any.
    private var registry: [WindowToken: Registration] = [:]

    @ObservationIgnored private var nextRevision = 0
    /// The newest revision a save has been *accepted* for, per project — not necessarily
    /// written: a failed or blocked newer save must still stop an older one landing after it.
    @ObservationIgnored private var highestAccepted: [ProjectID: SaveRevision] = [:]
    /// Projects whose file was refused (D11); nothing is written to them.
    @ObservationIgnored private var blocked: Set<ProjectID> = []
    /// Projects deleted in this process (D9); a late save must not recreate their files.
    @ObservationIgnored private var tombstones: Set<ProjectID> = []

    /// Lists the projects once. A listing that fails leaves the list empty; nothing is written
    /// on that account, and each project is still guarded when it is opened.
    init(
        store: any ProjectStoring,
        lastOpened: LastOpenedProject,
        makeID: @escaping () -> ProjectID = { ProjectID(UUID()) },
        now: @escaping () -> Date = { .now }
    ) {
        self.store = store
        self.lastOpened = lastOpened
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
        defer { nextRevision += 1 }
        return SaveRevision(value: nextRevision)
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
    /// As in M4's `ProgramAutosave`, an **equal** revision is written again (the same edit asking
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
            setFailure(.saveFailed, for: id)
            return .failed
        }
        setFailure(nil, for: id)
        upsert(ProjectFile(id: id, inspection: .openable(program), modified: now()))
        return .written
    }

    // MARK: Opening

    /// Reads `id`, writing nothing to disk. A refusal blocks the project; an openable or
    /// missing file lifts a block, since there is no longer anything to protect. Either way the
    /// summary follows what was found.
    func open(_ id: ProjectID) -> ProjectOpening {
        let loaded: Program?
        do {
            loaded = try store.load(id)
        } catch {
            block(id)
            let reason: ProgramDocumentError = switch error {
            case let .document(reason): reason
            case .unreadable: .corrupt
            }
            let summary = files.first { $0.id == id }
            let name: String? = switch summary?.inspection {
            case let .openable(program): program.name
            case let .refused(_, name): name
            case nil: nil
            }
            upsert(ProjectFile(id: id, inspection: .refused(reason, name: name), modified: summary?.modified ?? now()))
            return .refused(error)
        }
        unblock(id)
        guard let loaded else {
            files.removeAll { $0.id == id }
            return .missing
        }
        let summary = files.first { $0.id == id }
        if summary?.inspection != .openable(loaded) {
            upsert(ProjectFile(id: id, inspection: .openable(loaded), modified: summary?.modified ?? now()))
        }
        return .opened(loaded)
    }

    // MARK: Launch (D6)

    /// The scene's project if it opens, else the last opened one if it opens, else none. An
    /// opened project becomes the last opened; a last-opened ID whose file is gone is cleared.
    /// A refused candidate is reported once and skipped, and stays the last opened, since its
    /// file is still there. A project deleted in this process is gone, whatever a stale scene
    /// says.
    func resolveLaunch(sceneID: ProjectID?) -> LaunchResolution {
        var refusals: [ProjectRefusal] = []
        let remembered = lastOpened.id
        for candidate in [sceneID, remembered].compactMap(\.self) where !tombstones.contains(candidate) {
            guard !refusals.contains(where: { $0.id == candidate }) else {
                continue
            }
            switch open(candidate) {
            case let .opened(program):
                lastOpened.id = candidate
                return LaunchResolution(opened: OpenedProject(id: candidate, program: program), refusals: refusals)
            case let .refused(reason):
                refusals.append(ProjectRefusal(id: candidate, reason: reason))
            case .missing:
                if candidate == remembered {
                    lastOpened.id = nil
                }
            }
        }
        return LaunchResolution(opened: nil, refusals: refusals)
    }

    /// Records `id` as the project to reopen after a relaunch: on opening one, and on a
    /// draft's first write.
    func markOpened(_ id: ProjectID) {
        lastOpened.id = id
    }

    // MARK: Catalog operations

    /// Removes the file first; only once it is gone are the tombstone, the summary and the
    /// project's block and failure changed. A removal that throws changes nothing (brief D9).
    /// A project another window holds is refused before anything is touched (D7); the window
    /// asking may hold it itself. A deleted project stops being the last opened.
    func delete(_ id: ProjectID, requestedBy window: WindowToken? = nil) throws {
        guard holders(of: id).subtracting([window].compactMap(\.self)).isEmpty else {
            throw ProjectLibraryError.heldByAnotherWindow
        }
        try store.delete(id)
        tombstones.insert(id)
        // The tombstone makes launch skip this ID before it could find it missing and clear it
        // (Codex, slice 5), so the delete clears it.
        if lastOpened.id == id {
            lastOpened.id = nil
        }
        files.removeAll { $0.id == id }
        blocked.remove(id)
        setFailure(nil, for: id)
    }

    /// Writes `program` at once as a new project with a generated, unique name (brief D3, D4),
    /// and returns its ID, or `nil` if the write failed and no project was made.
    func duplicate(_ program: Program) -> ProjectID? {
        let base = (try? DesignName.validating(program.name).get()) ?? Self.fallbackName
        var copy = program
        copy.name = uniquedName(base).value
        let id = makeID()
        guard save(copy, to: id, revision: mintRevision()) == .written else {
            // Nothing holds the new ID, so nothing should show its failure.
            setFailure(nil, for: id)
            return nil
        }
        return id
    }

    /// Renames a project no window holds: load, rename, save under a fresh revision, so a
    /// window's save from before the rename cannot bring the old name back (brief D8). A
    /// project a window holds is `.held` — its rename is that window's edit — and a refused or
    /// missing one is `.blocked`; neither is written.
    func rename(_ id: ProjectID, to name: DesignName) -> ProjectSaveOutcome {
        guard holders(of: id).isEmpty else {
            return .held
        }
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

    /// Records that `window` now holds `id`, replacing whatever it held before — the draft
    /// name included, so a window re-registers with `nil` once its draft has a file. `owner` is
    /// held weakly, only so a window torn down without unregistering stops counting; its entry
    /// is pruned at the next registration, which is also when observers hear of it.
    func register(_ window: WindowToken, owner: AnyObject, holding id: ProjectID, draftName: String?) {
        registry = registry.filter { $0.value.owner != nil }
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

    /// The refusal replaces any earlier `.saveFailed`: it is the stronger state, and while it
    /// holds nothing is written anyway.
    private func block(_ id: ProjectID) {
        blocked.insert(id)
        setFailure(.refusedDocument, for: id)
    }

    private func unblock(_ id: ProjectID) {
        guard blocked.remove(id) != nil else {
            return
        }
        setFailure(nil, for: id)
    }

    /// Writes only a change, so an ordinary save does not notify every window's banner.
    private func setFailure(_ failure: ProjectSaveFailure?, for id: ProjectID) {
        if failures[id] != failure {
            failures[id] = failure
        }
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
        ProjectLibrary(
            store: DocumentsProjectStore(directory: .temporaryDirectory.appending(path: "preview-projects")),
            lastOpened: LastOpenedProject(defaults: UserDefaults(suiteName: "preview-projects") ?? .standard)
        )
    }
}
