import EmbroideryEngine
import Foundation

/// The app's one seam to the filesystem (ADR-006 pattern 2, ADR-026).
///
/// **The app writes no bytes itself.** The only implementation below hands the bytes to
/// `DSTFile.write(to:)`, which is the package's sole piece of I/O; everything this protocol
/// adds is *where* the file goes and *when* it is cleaned up. That is Catty's proven
/// `shareDST(embroideryService:)` + `EmbroideryServiceMock` shape, which is the one thing in
/// that file worth porting — Catty's own temp files are never cleaned up at all.
///
/// **No `Sendable` requirement, and that is a consequence of eager preparation rather than
/// an oversight.** Because `ExportViewModel.prepare(exportModel:)` puts the file on disk
/// before a `DSTDesign` is ever constructed, the writer never crosses into nonisolated code
/// — unlike `DSTDesign` itself, which must be `nonisolated` because `transferRepresentation`
/// is a nonisolated static requirement under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. A
/// writer reached from inside a `FileRepresentation` closure would need the full
/// `Sendable` treatment.
protocol DSTFileWriting {
    /// Writes `file` under `name` in a location the writer owns, and returns where it went.
    func write(_ file: DSTFile, named name: DSTFileName) throws -> URL

    /// Removes everything this writer has written.
    ///
    /// **Deliberately non-throwing.** Cleanup is best-effort: a temp file that cannot be
    /// deleted is untidy, and failing the export over it would turn a cosmetic problem into
    /// a user-visible one. The caller has no recovery to offer either way.
    func removeAll()
}

/// Writes into a per-session directory under the system temporary directory
/// (ADR-026, scope decision 4).
///
/// One directory per app run, named by a `UUID`, holding at most one file: `prepare()`
/// clears it before each write, and `RunViewModel.reset()` clears it when the design is
/// discarded. The directory rather than the file is the unit of cleanup, so a rename that
/// changed the file name cannot orphan the previous one.
///
/// Deleting our copy cannot break a share already in flight: `DSTDesign` hands the system
/// `SentTransferredFile(url, allowAccessingOriginalFile: false)`, so the system takes its
/// own copy.
final class TemporaryDSTFileWriter: DSTFileWriting {
    private let directory: URL

    /// The directory is injectable so a test can point it somewhere disposable; the default
    /// is a fresh per-session one, which is what makes "at most one file" true across
    /// simultaneous iPad windows.
    init(directory: URL = .temporaryDirectory.appending(path: "dst-export-\(UUID().uuidString)")) {
        self.directory = directory
    }

    func write(_ file: DSTFile, named name: DSTFileName) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let url = directory.appending(path: name.value)
        // The package's only I/O, and the only place in the app that reaches it. It writes
        // atomically, so an interrupted export never leaves a truncated file for the share
        // sheet to pick up.
        try file.write(to: url)
        return url
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
