import EditorCore
import Foundation
import ProgramModel

/// A project's identity (project management, brief D2): stable across renames, so a name is
/// never part of a path and two projects may share one.
struct ProjectID: Hashable, Sendable, Codable {
    let rawValue: UUID

    init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// One project file as the list sees it: what it holds, readable or not, and when it last
/// changed (brief D11, D12). The date is the file's own, so no manifest can drift from it.
struct ProjectFile: Equatable, Sendable {
    let id: ProjectID
    let inspection: DocumentInspection
    let modified: Date
}

/// The app's seam to the saved projects (brief D1; ADR-006 pattern 2). Like `ProgramStoring`,
/// it adds only *where* `ProgramDocument`'s bytes go and holds no policy: which write wins,
/// and which projects may be written at all, is the library's rule.
protocol ProjectStoring {
    /// The project's program, or `nil` when it has no file.
    func load(_ id: ProjectID) throws(ProgramLoadError) -> Program?

    /// Replaces the project's file. Encodes before touching the disk, so a program that cannot
    /// be encoded leaves the previous file, or the absence of one, exactly as it was.
    func save(_ program: Program, as id: ProjectID) throws

    /// Removes the project's file. A project with no file is already deleted; a removal the
    /// file system refuses throws and leaves the file in place.
    func delete(_ id: ProjectID) throws

    /// Every project file, in no particular order, including the ones that cannot be opened.
    func list() throws -> [ProjectFile]
}

/// The projects as one JSON file each, `Projects/<UUID>.json` under the app's Documents
/// directory (brief D1).
final class DocumentsProjectStore: ProjectStoring {
    private let directory: URL

    /// The root is injectable so a test can point it somewhere disposable; the projects live
    /// in its `Projects` subdirectory.
    init(directory: URL = .documentsDirectory) {
        self.directory = directory.appending(path: "Projects")
    }

    /// Where `id`'s file lives. The UUID's canonical uppercase spelling is the only one the
    /// store writes, and so the only one `list()` recognises.
    func url(for id: ProjectID) -> URL {
        directory.appending(path: "\(id.rawValue.uuidString).json")
    }

    func load(_ id: ProjectID) throws(ProgramLoadError) -> Program? {
        let data: Data
        do {
            data = try Data(contentsOf: url(for: id))
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

    /// Encode first, then an atomic write: the new bytes replace the old file in one rename, so
    /// an interrupted save leaves the previous program, never half of the new one.
    func save(_ program: Program, as id: ProjectID) throws {
        let data = try ProgramDocument.encode(program)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(for: id), options: .atomic)
    }

    func delete(_ id: ProjectID) throws {
        do {
            try FileManager.default.removeItem(at: url(for: id))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    /// Only a regular file named exactly `url(for:)` of some ID is a project. An atomic
    /// write's temporary file, a foreign name and a directory are not, and are skipped rather
    /// than listed as refused.
    func list() throws -> [ProjectFile] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        return try urls.compactMap { url in
            guard let id = Self.projectID(named: url.lastPathComponent) else {
                return nil
            }
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true, let modified = values.contentModificationDate else {
                return nil
            }
            return try ProjectFile(
                id: id,
                inspection: ProgramDocument.inspect(Data(contentsOf: url)),
                modified: modified
            )
        }
    }

    private static func projectID(named fileName: String) -> ProjectID? {
        guard fileName.hasSuffix(".json"),
              let uuid = UUID(uuidString: String(fileName.dropLast(".json".count))),
              fileName == "\(uuid.uuidString).json"
        else {
            return nil
        }
        return ProjectID(uuid)
    }
}
