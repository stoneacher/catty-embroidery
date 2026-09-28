import EditorCore
import Foundation
import ProgramModel

/// Why a saved program could not be opened.
///
/// `document` carries US-404's reasons unchanged, so the refusal copy switches over them with no
/// cast (ADR-037). `unreadable` is every read failure other than "there is no file", which is not
/// a failure at all: it is a first launch.
enum ProgramLoadError: Error, Equatable {
    case document(ProgramDocumentError)
    case unreadable
}

/// The app's seam to the saved working program (US-406; ADR-006 pattern 2).
///
/// Structurally the split US-308 made for `DSTFileWriting`: the bytes are `ProgramDocument`'s,
/// computed in the package with no I/O, and this protocol adds only *where* they go. It holds no
/// policy — which write wins is `ProgramAutosave`'s rule, so a test double cannot carry a second
/// copy of it.
protocol ProgramStoring {
    /// The saved program, or `nil` when there is none.
    func load() throws(ProgramLoadError) -> Program?

    /// Replaces the saved program. Encodes before touching the disk, so a program that cannot
    /// be encoded leaves the previous file exactly as it was.
    func save(_ program: Program) throws

    /// Moves the saved file out of the way without altering its bytes, and returns where it
    /// went. Never overwrites a file set aside earlier.
    func setAside() throws -> URL
}

/// The saved working program as one JSON file in the app's Documents directory.
final class DocumentsProgramStore: ProgramStoring {
    private let directory: URL

    /// The directory is injectable so a test can point it somewhere disposable.
    init(directory: URL = .documentsDirectory) {
        self.directory = directory
    }

    /// Where the working program lives.
    var workingURL: URL {
        directory.appending(path: "WorkingProgram.json")
    }

    func load() throws(ProgramLoadError) -> Program? {
        nil
    }

    func save(_: Program) throws {}

    func setAside() throws -> URL {
        workingURL
    }
}
