import EditorCore
import Foundation
import ProgramModel

/// A project's identity (project management, brief D2): stable across renames, so a name is
/// never part of a path and two projects may share one.
public struct ProjectID: Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// The ID a stored string names, or `nil` for anything else — scene storage and the
    /// last-opened default are read defensively (brief D6).
    public init?(uuidString: String?) {
        guard let uuidString, let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        self.init(uuid)
    }

    /// The stored form: the UUID's canonical string, as in the file name.
    public var uuidString: String {
        rawValue.uuidString
    }

    /// Where M4's single working file is migrated to (brief D5): fixed, so a replay of an
    /// interrupted migration finds its own earlier work rather than making a second project.
    public static let legacyWorkingProgram: ProjectID = {
        guard let uuid = UUID(uuidString: "4D400000-0000-4000-8000-000000000001") else {
            preconditionFailure("the legacy project's fixed ID must be a UUID")
        }
        return ProjectID(uuid)
    }()
}

/// One project file as the list sees it: what it holds, readable or not, and when it last
/// changed (brief D11, D12). The date is the file's own, so no manifest can drift from it.
public struct ProjectFile: Equatable, Sendable {
    public let id: ProjectID
    public let inspection: DocumentInspection
    public let modified: Date

    public init(id: ProjectID, inspection: DocumentInspection, modified: Date) {
        self.id = id
        self.inspection = inspection
        self.modified = modified
    }
}

/// The app's seam to the saved projects (brief D1; ADR-006 pattern 2). Like `ProgramStoring`,
/// it adds only *where* `ProgramDocument`'s bytes go and holds no policy: which write wins,
/// and which projects may be written at all, is the library's rule.
@MainActor
public protocol ProjectStoring {
    /// The project's program, or `nil` when it has no file.
    func load(_ id: ProjectID) throws(ProgramLoadError) -> Program?

    /// Replaces the project's file. Encodes before touching the disk, so a program that cannot
    /// be encoded leaves the previous file, or the absence of one, exactly as it was.
    func save(_ program: Program, as id: ProjectID) throws

    /// Removes the project's file. A project with no file is already deleted; a removal the
    /// file system refuses throws and leaves the file in place.
    func delete(_ id: ProjectID) throws

    /// Every project file, in no particular order, including the ones that cannot be opened
    /// or even read. Throws only when the directory itself cannot be read.
    func list() throws -> [ProjectFile]

    /// The project file's own modification date (brief D1), or `nil` when it cannot be read.
    func modified(_ id: ProjectID) -> Date?
}

/// The projects as one JSON file each, `Projects/<UUID>.json` under the app's Documents
/// directory (brief D1).
@MainActor
public final class DocumentsProjectStore: ProjectStoring {
    private let directory: URL

    /// The projects live in the root's `Projects` subdirectory. No default root (US-329 review):
    /// the app passes `.documentsDirectory`, and on macOS a package test that forgot to pass one
    /// would write to the developer's real Documents.
    public init(directory: URL) {
        self.directory = directory.appending(path: "Projects")
    }

    /// Where `id`'s file lives. The UUID's canonical uppercase spelling is the only one the
    /// store writes, and so the only one `list()` recognises.
    ///
    /// Assumes nothing else writes the directory, which the sandbox guarantees (no file
    /// sharing is declared). A device volume is case-sensitive, so a lowercase lookalike would
    /// be a separate file; the simulator's host volume folds case, so there it would alias
    /// this path. Neither can arise from the app.
    func url(for id: ProjectID) -> URL {
        directory.appending(path: "\(id.rawValue.uuidString).json")
    }

    public func load(_ id: ProjectID) throws(ProgramLoadError) -> Program? {
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
    public func save(_ program: Program, as id: ProjectID) throws {
        let data = try ProgramDocument.encode(program)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(for: id), options: .atomic)
    }

    public func modified(_ id: ProjectID) -> Date? {
        try? url(for: id).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Removes whatever is at `url(for:)`; the store only ever puts a regular file there.
    public func delete(_ id: ProjectID) throws {
        do {
            try FileManager.default.removeItem(at: url(for: id))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    /// Only a regular file named exactly `url(for:)` of some ID is a project. An atomic
    /// write's temporary file, a foreign name, a directory and a symbolic link are not, and are
    /// skipped rather than listed as refused.
    ///
    /// One file must not hide the others (slice 3 review): a project file that cannot be read
    /// is listed as damaged — `.corrupt`, with no name — so the list can offer to delete it,
    /// and one that vanishes between the scan and the read is skipped.
    public func list() throws -> [ProjectFile] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        return urls.compactMap { url in
            guard let id = Self.projectID(named: url.lastPathComponent) else {
                return nil
            }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate
            else {
                return nil
            }
            let inspection: DocumentInspection
            do {
                inspection = try ProgramDocument.inspect(Data(contentsOf: url))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                return nil
            } catch {
                inspection = .refused(.corrupt, name: nil)
            }
            return ProjectFile(id: id, inspection: inspection, modified: modified)
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
