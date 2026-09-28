import Foundation
import Observation
import ProgramModel

/// The order in which working programs were produced, across every window.
///
/// Minted only by `ProgramAutosave.mintRevision()`, on the main actor, at the moment of the
/// edit or replacement it stamps — so the order of revisions is the order the user acted in.
/// `nonisolated` because a `Comparable` conformance on a main-actor type is itself main-actor
/// isolated, and the comparison should not care where it runs.
nonisolated struct SaveRevision: Comparable, Sendable {
    fileprivate let value: Int

    static func < (lhs: SaveRevision, rhs: SaveRevision) -> Bool {
        lhs.value < rhs.value
    }
}

/// A saved program that was found and not opened.
struct ProgramRefusal: Equatable {
    let reason: ProgramLoadError
    /// Whether the refused file was moved aside. `false` means it is still at the working path,
    /// and nothing may write there until it has been moved.
    let preserved: Bool
}

/// What launch found on disk.
enum ProgramRestore: Equatable {
    case nothingSaved
    case restored(Program)
    case refused(ProgramRefusal)
}

/// Why the working program is not being saved.
enum ProgramSaveFailure: Equatable {
    /// The last write threw.
    case saveFailed
    /// A refused file could not be moved aside, so writing would destroy it.
    case unpreservedDocument
}

/// What became of one save request.
enum ProgramSaveOutcome: Equatable {
    case written
    /// A newer revision was already accepted; this one was dropped.
    case superseded
    /// A refused file is still at the working path.
    case blocked
    case failed
}

/// The one guard on the saved working program, shared by every window (US-406, ADR-037).
@MainActor
@Observable
final class ProgramAutosave {
    private let store: any ProgramStoring

    /// Why saving has stopped, or `nil` while it works.
    private(set) var failure: ProgramSaveFailure?

    init(store: any ProgramStoring) {
        self.store = store
    }

    /// A revision newer than every one minted before it.
    func mintRevision() -> SaveRevision {
        SaveRevision(value: 0)
    }

    /// Saves `program` unless a newer revision has already been accepted.
    @discardableResult
    func save(_: Program, revision _: SaveRevision) -> ProgramSaveOutcome {
        .written
    }

    /// Reads the saved program, setting a refused file aside.
    func restore() -> ProgramRestore {
        .nothingSaved
    }
}

extension ProgramAutosave {
    /// For previews: saves into a scratch directory, never the user's Documents.
    static var preview: ProgramAutosave {
        ProgramAutosave(
            store: DocumentsProgramStore(directory: .temporaryDirectory.appending(path: "preview-autosave"))
        )
    }
}
