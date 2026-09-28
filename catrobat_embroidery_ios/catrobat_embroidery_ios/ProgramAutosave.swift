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
///
/// **App-scoped, where `AppModel` deliberately is not** — and that extends `WindowRootView`'s
/// reasoning rather than contradicting it. Per-window state stays per window because nothing
/// one window's user does should move another. But every window writes the *same file*, so
/// the rule deciding which write wins has to see all of them: two per-window guards would each
/// approve their own stale write. The coordinator holds no program and no selection, so
/// sharing it couples nothing a user can see.
///
/// **Last writer wins, by revision.** Every edit or whole-program replacement mints a revision
/// here, synchronously on the main actor, at the moment it happens; each window keeps the
/// revision of the program it holds and hands it back with every save. A save older than the
/// newest one accepted is dropped. So a window that goes to the background carrying an edit
/// another window has since superseded cannot put the older program back — the case a
/// per-window "has edited" flag loses (story, test 3b).
///
/// **Writes are synchronous on the main actor**, declining the story's "off the main actor"
/// premise (decided 2026-09-28). At the ~4 KB a program weighs, an atomic write measured about
/// 0.2 ms (0.19 ms at 132 KB); on the main actor writes are ordered by construction, and a
/// save on leaving the foreground has finished before the handler returns. The revision
/// makes a stale write a no-op on top of that, so the story's "ordered *or* versioned" holds
/// twice over.
///
/// The accepted revision lives in memory only: this process is the file's only writer, and
/// after a relaunch every revision minted is newer than what is on disk by definition.
@MainActor
@Observable
final class ProgramAutosave {
    private let store: any ProgramStoring

    /// Why saving has stopped, or `nil` while it works. Observed by every window; the next
    /// successful write clears it.
    private(set) var failure: ProgramSaveFailure?

    @ObservationIgnored private var nextRevision = 0

    /// The newest revision a save has been *accepted* for — not necessarily written, since the
    /// write may have failed. Accepted is the right line: a failed newer write must still stop
    /// an older one landing after it.
    @ObservationIgnored private var highestAccepted: SaveRevision?

    /// A refused file is still at the working path because setting it aside failed. While it
    /// is, nothing is written there: clobbering a file we failed to parse is the one
    /// unrecoverable thing this story could do.
    @ObservationIgnored private var unpreservedDocument = false

    init(store: any ProgramStoring) {
        self.store = store
    }

    /// A revision newer than every one minted before it.
    func mintRevision() -> SaveRevision {
        defer { nextRevision += 1 }
        return SaveRevision(value: nextRevision)
    }

    /// Saves `program` unless a newer revision has already been accepted.
    ///
    /// Strictly older is dropped; an **equal** revision is written again, because that is the
    /// same edit asking twice — a save on leaving the foreground retrying a write that failed.
    @discardableResult
    func save(_ program: Program, revision: SaveRevision) -> ProgramSaveOutcome {
        if let highestAccepted, revision < highestAccepted {
            return .superseded
        }
        highestAccepted = revision
        guard !unpreservedDocument else {
            failure = .unpreservedDocument
            return .blocked
        }
        do {
            try store.save(program)
        } catch {
            failure = .saveFailed
            return .failed
        }
        failure = nil
        return .written
    }

    /// Reads the saved program, setting a refused file aside.
    ///
    /// Writes nothing: restoring is not an edit, and writing back what was just read would
    /// be a no-op at best. A refused file is moved aside, never overwritten; if that fails,
    /// every later save is blocked until a restore — another window, or the next launch —
    /// manages to move it.
    func restore() -> ProgramRestore {
        let loaded: Program?
        do {
            loaded = try store.load()
        } catch {
            return .refused(ProgramRefusal(reason: error, preserved: setAside()))
        }
        guard let loaded else {
            return .nothingSaved
        }
        return .restored(loaded)
    }

    private func setAside() -> Bool {
        do {
            _ = try store.setAside()
        } catch {
            unpreservedDocument = true
            failure = .unpreservedDocument
            return false
        }
        if unpreservedDocument {
            unpreservedDocument = false
            failure = nil
        }
        return true
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
