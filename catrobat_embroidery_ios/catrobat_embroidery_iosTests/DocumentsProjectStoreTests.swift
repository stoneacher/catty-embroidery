@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Samples
import Testing

/// The **production** project store against a real filesystem (project management slice 3,
/// brief D1, D9 and D11): one file per project, `Projects/<UUID>.json`. Each test works in its
/// own disposable directory, as `DocumentsProgramStoreTests` does for M4's single file.
@MainActor
@Suite("Documents project store")
struct DocumentsProjectStoreTests {
    private static let rosette = SampleLibrary[.octagonRosette].program
    private static let coil = SampleLibrary[.squareCoil].program
    private static let first = ProjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    private static let second = ProjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
    /// An ID with hex letters: an all-digit UUID reads the same in either case, so it cannot
    /// tell the canonical uppercase file name from a lowercase one (slice 3 review).
    private static let lettered = ProjectID(UUID(uuidString: "ABCDEF00-0000-0000-0000-00000000000A")!)

    private static func projects(in root: URL) -> URL {
        root.appending(path: "Projects")
    }

    private static func names(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    // MARK: Paths and round trip

    @Test("a save creates Projects/<UUID>.json holding ProgramDocument's encoding")
    func saveCreatesTheProjectFile() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)

            try store.save(Self.rosette, as: Self.first)

            let file = Self.projects(in: root).appending(path: "00000000-0000-0000-0000-000000000001.json")
            #expect(store.url(for: Self.first) == file)
            #expect(try Data(contentsOf: file) == ProgramDocument.encode(Self.rosette))
            #expect(try store.load(Self.first) == Self.rosette)
        }
    }

    @Test("the file name is the UUID's canonical uppercase spelling, and lists back")
    func theFileNameIsUppercase() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)

            try store.save(Self.rosette, as: Self.lettered)

            #expect(try Self.names(in: Self.projects(in: root)) == ["ABCDEF00-0000-0000-0000-00000000000A.json"])
            #expect(try store.list().map(\.id) == [Self.lettered])
        }
    }

    @Test("projects are separate files: saving one leaves the other's bytes alone")
    func projectsAreSeparateFiles() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            try store.save(Self.rosette, as: Self.first)
            try store.save(Self.coil, as: Self.second)
            try store.save(Self.coil, as: Self.first)

            #expect(try store.load(Self.first) == Self.coil)
            #expect(try store.load(Self.second) == Self.coil)
            #expect(try Self.names(in: Self.projects(in: root)) == [
                "00000000-0000-0000-0000-000000000001.json", "00000000-0000-0000-0000-000000000002.json"
            ])
        }
    }

    @Test("a project with no file loads as nil")
    func aMissingProjectLoadsAsNil() throws {
        try inDisposableDirectory { root in
            let loaded = try DocumentsProjectStore(directory: root).load(Self.first)
            #expect(loaded == nil)
        }
    }

    // MARK: Failure keeps the old bytes

    @Test("a program that cannot be encoded leaves the previous file byte for byte")
    func aFailedEncodeLeavesThePreviousFile() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            try store.save(Self.rosette, as: Self.first)
            let before = try Data(contentsOf: store.url(for: Self.first))
            var unencodable = Self.rosette
            unencodable.scenes[0].objects[0].startX = .infinity

            #expect(throws: ProgramDocumentError.encodingFailed) {
                try store.save(unencodable, as: Self.first)
            }

            #expect(try Data(contentsOf: store.url(for: Self.first)) == before)
        }
    }

    @Test("a program that cannot be encoded creates no file for a new project")
    func aFailedEncodeCreatesNoFile() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            var unencodable = Self.rosette
            unencodable.scenes[0].objects[0].startX = .nan

            #expect(throws: ProgramDocumentError.encodingFailed) {
                try store.save(unencodable, as: Self.first)
            }

            #expect(!FileManager.default.fileExists(atPath: store.url(for: Self.first).path))
        }
    }

    /// US-406's proxy for `.atomic`: an atomic write renames a new file into place, so the path
    /// gets a new inode, where a plain write truncates the old one.
    @Test("each save replaces the file rather than rewriting it in place")
    func eachSaveReplacesTheFile() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)

            try store.save(Self.rosette, as: Self.first)
            let before = try Self.inode(of: store.url(for: Self.first))
            try store.save(Self.coil, as: Self.first)
            let after = try Self.inode(of: store.url(for: Self.first))

            #expect(before != after)
        }
    }

    private static func inode(of url: URL) throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int
    }

    // MARK: Refused files load with the codec's reason

    @Test("a refused project file loads as the codec's reason and is left in place")
    func aRefusedFileIsLeftInPlace() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            let bytes = try RefusedDocument.futureVersion
            try FileManager.default.createDirectory(at: Self.projects(in: root), withIntermediateDirectories: true)
            try bytes.write(to: store.url(for: Self.first))

            #expect(throws: ProgramLoadError.document(.unsupportedVersion(2))) {
                try store.load(Self.first)
            }

            #expect(try Data(contentsOf: store.url(for: Self.first)) == bytes)
        }
    }

    @Test("a project path that cannot be read is unreadable, not missing")
    func anUnreadablePathIsNotMissing() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            try FileManager.default.createDirectory(at: store.url(for: Self.first), withIntermediateDirectories: true)

            #expect(throws: ProgramLoadError.unreadable) {
                try store.load(Self.first)
            }
        }
    }

    // MARK: Listing

    @Test("with no projects directory the list is empty")
    func noDirectoryListsNothing() throws {
        try inDisposableDirectory { root in
            let files = try DocumentsProjectStore(directory: root).list()
            #expect(files.isEmpty)
        }
    }

    /// D11: a refused file is listed, with whatever name the probe could read, so the list can
    /// badge it and offer Delete.
    @Test("the list holds every project file, refused ones included, with their dates")
    func theListHoldsEveryProjectFile() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            try store.save(Self.rosette, as: Self.first)
            try RefusedDocument.futureVersion.write(to: store.url(for: Self.second))
            let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
            let secondDate = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes(
                [.modificationDate: firstDate],
                ofItemAtPath: store.url(for: Self.first).path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: secondDate],
                ofItemAtPath: store.url(for: Self.second).path
            )

            let files = try store.list().sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }

            #expect(files == [
                ProjectFile(id: Self.first, inspection: .openable(Self.rosette), modified: firstDate),
                ProjectFile(
                    id: Self.second,
                    inspection: .refused(.unsupportedVersion(2), name: "from the future"),
                    modified: secondDate
                )
            ])
        }
    }

    /// Only a canonical `<UUID>.json` is a project: an atomic write's temporary file, anything
    /// that is not JSON, a name that is not a UUID, a lowercase spelling `url(for:)` would never
    /// produce, and a directory are all skipped rather than listed or refused.
    @Test("the list skips everything that is not a project file")
    func theListSkipsNonProjects() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            try store.save(Self.rosette, as: Self.first)
            let directory = Self.projects(in: root)
            let uuid = Self.second.rawValue.uuidString
            for name in [
                ".dat.nosync1234.abcd", "\(uuid).json.tmp", "\(uuid).txt", "notes.json",
                "abcdef00-0000-0000-0000-000000000004.json", ".\(uuid).json"
            ] {
                try Data(ProgramDocument.encode(Self.coil)).write(to: directory.appending(path: name))
            }
            try FileManager.default.createDirectory(
                at: directory.appending(path: "00000000-0000-0000-0000-000000000003.json"),
                withIntermediateDirectories: false
            )

            #expect(try store.list().map(\.id) == [Self.first])
        }
    }

    /// One file the store cannot read must not hide the others (slice 3 review: Codex and
    /// `swift-code-reviewer`). It is listed as damaged, with no name, so it can be deleted.
    @Test("an unreadable project file is listed as damaged beside the readable ones")
    func anUnreadableFileIsListedAsDamaged() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            try store.save(Self.rosette, as: Self.first)
            try store.save(Self.coil, as: Self.second)
            let path = store.url(for: Self.second).path
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }

            let files = try store.list().sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }

            #expect(files.map(\.id) == [Self.first, Self.second])
            #expect(files.map(\.inspection) == [.openable(Self.rosette), .refused(.corrupt, name: nil)])
        }
    }

    /// Only "no directory yet" is an empty list. Anything else wrong with the directory must
    /// not pass for "no projects", or launch would start a draft over a library it cannot see.
    @Test("a projects path that is not a directory makes the list throw")
    func aBrokenProjectsDirectoryThrows() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            try Data("not a directory".utf8).write(to: Self.projects(in: root))

            #expect(throws: (any Error).self) {
                try store.list()
            }
        }
    }

    /// The store never makes links; one found in the directory is not a project.
    @Test("a symbolic link named like a project is skipped")
    func aSymlinkIsSkipped() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            try store.save(Self.rosette, as: Self.first)
            try FileManager.default.createSymbolicLink(
                at: store.url(for: Self.second), withDestinationURL: store.url(for: Self.first)
            )

            #expect(try store.list().map(\.id) == [Self.first])
        }
    }

    // MARK: Deleting

    @Test("delete removes exactly its own project's file")
    func deleteRemovesOnlyItsOwnFile() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            try store.save(Self.rosette, as: Self.first)
            try store.save(Self.coil, as: Self.second)

            try store.delete(Self.first)

            #expect(try store.load(Self.first) == nil)
            #expect(try store.load(Self.second) == Self.coil)
            #expect(try store.list().map(\.id) == [Self.second])
        }
    }

    /// The caller asked for the file to be gone, and it is: a project that was never saved
    /// (a draft) deletes without error.
    @Test("deleting a project with no file succeeds and touches nothing")
    func deletingAMissingProjectSucceeds() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            try store.save(Self.coil, as: Self.second)

            try store.delete(Self.first)

            #expect(try store.list().map(\.id) == [Self.second])
        }
    }

    /// D9's precondition: a removal that fails must throw, so the library changes nothing.
    @Test("a delete the file system refuses throws")
    func aRefusedDeleteThrows() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            try store.save(Self.rosette, as: Self.first)
            let directory = Self.projects(in: root)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

            #expect(throws: (any Error).self) {
                try store.delete(Self.first)
            }

            #expect(try store.load(Self.first) == Self.rosette)
        }
    }
}
