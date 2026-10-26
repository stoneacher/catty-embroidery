import EditorCore
import Foundation
import ProgramModel

/// Why a saved program could not be opened.
///
/// `document` carries US-404's reasons unchanged, so the refusal copy switches over them with no
/// cast (ADR-037). `unreadable` is every read failure other than "there is no file", which is not
/// a failure at all: it is a first launch.
public enum ProgramLoadError: Error, Equatable {
    case document(ProgramDocumentError)
    case unreadable
}

/// The app's seam to M4's single saved working program (US-406; ADR-006 pattern 2). Since M5
/// every design is a project (`ProjectStoring`); this seam remains only for reading the legacy
/// file, which slice 6 migrates.
///
/// Structurally the split US-308 made for `DSTFileWriting`: the bytes are `ProgramDocument`'s,
/// computed in the package with no I/O, and this protocol adds only *where* they go.
@MainActor
public protocol ProgramStoring {
    /// The saved program, or `nil` when there is none.
    func load() throws(ProgramLoadError) -> Program?

    /// Replaces the saved program. Encodes before touching the disk, so a program that cannot
    /// be encoded leaves the previous file exactly as it was.
    func save(_ program: Program) throws

    /// Moves the saved file out of the way without altering its bytes, and returns where it
    /// went. Never overwrites a file set aside earlier.
    func setAside() throws -> URL

    /// Deletes the working file once it has been migrated (project management slice 6); a file
    /// already gone is the outcome asked for. Files set aside earlier are left alone.
    func remove() throws
}

/// The saved working program as one JSON file in the app's Documents directory.
@MainActor
public final class DocumentsProgramStore: ProgramStoring {
    private let directory: URL

    /// The directory is injectable so a test can point it somewhere disposable.
    public init(directory: URL = .documentsDirectory) {
        self.directory = directory
    }

    /// Where the working program lives.
    public var workingURL: URL {
        directory.appending(path: "WorkingProgram.json")
    }

    public func load() throws(ProgramLoadError) -> Program? {
        let data: Data
        do {
            data = try Data(contentsOf: workingURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw .unreadable
        }
        do {
            return try ProgramDocument.decode(data)
        } catch {
            throw .document(error)
        }
    }

    /// Encode first: a program the codec refuses throws here, before anything on disk has
    /// been touched. The write is atomic — the new bytes replace the old file in one rename —
    /// so an interrupted save leaves the previous program, never half of the new one.
    public func save(_ program: Program) throws {
        let data = try ProgramDocument.encode(program)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: workingURL, options: .atomic)
    }

    public func remove() throws {
        do {
            try FileManager.default.removeItem(at: workingURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    /// `moveItem` refuses an existing destination (`fileWriteFileExists`) and leaves its source
    /// in place, so trying successive names can never overwrite a file set aside earlier. The
    /// names keep `.json`, so a later version of the app can offer to recover them; M5 owns
    /// that list.
    public func setAside() throws -> URL {
        for attempt in 1 ... Self.maximumSetAsideAttempts {
            let destination = directory.appending(path: "WorkingProgram-refused-\(attempt).json")
            do {
                try FileManager.default.moveItem(at: workingURL, to: destination)
                return destination
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// A bound on the names `setAside()` tries: past this many refused files something other
    /// than a bad file is wrong, and the caller treats the file as unpreserved.
    private static let maximumSetAsideAttempts = 1000
}
