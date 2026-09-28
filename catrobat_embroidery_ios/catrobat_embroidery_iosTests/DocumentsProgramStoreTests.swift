@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Samples
import Testing

/// The **production** store against a real filesystem (US-406).
///
/// `TemporaryDSTFileWriterTests` exists because every other export test injected a double and
/// so could not see the bytes; this suite exists for the same reason one story later. Each test
/// works in its own disposable directory.
@MainActor
@Suite("Documents program store")
struct DocumentsProgramStoreTests {
    private static let rosette = SampleLibrary[.octagonRosette].program
    private static let coil = SampleLibrary[.squareCoil].program

    // MARK: No file

    @Test("with no file, load is a first launch rather than an error")
    func noFileLoadsAsNil() throws {
        try inDisposableDirectory { directory in
            let loaded = try DocumentsProgramStore(directory: directory).load()
            #expect(loaded == nil)
        }
    }

    @Test("a directory that does not exist yet is created by the first save")
    func theFirstSaveCreatesTheDirectory() throws {
        try inDisposableDirectory { parent in
            let store = DocumentsProgramStore(directory: parent.appending(path: "not-yet"))

            try store.save(Self.rosette)

            #expect(try store.load() == Self.rosette)
        }
    }

    // MARK: Round trip

    @Test("the bytes on disk are ProgramDocument's encoding, and load reads them back")
    func theBytesOnDiskAreTheDocumentEncoding() throws {
        try inDisposableDirectory { directory in
            let store = DocumentsProgramStore(directory: directory)

            try store.save(Self.rosette)

            #expect(try Data(contentsOf: store.workingURL) == ProgramDocument.encode(Self.rosette))
            #expect(try store.load() == Self.rosette)
        }
    }

    /// Test-plan item 9, at the level this story can assert it: the second save replaces the
    /// first cleanly and leaves no temporary file beside it.
    @Test("two saves in a row leave exactly one readable file")
    func twoSavesInARowLeaveOneReadableFile() throws {
        try inDisposableDirectory { directory in
            let store = DocumentsProgramStore(directory: directory)

            try store.save(Self.rosette)
            try store.save(Self.rosette)
            try store.save(Self.coil)

            #expect(try store.load() == Self.coil)
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(names == ["WorkingProgram.json"])
        }
    }

    /// A proxy for `.atomic`, which no in-process test can observe directly: an atomic write
    /// renames a new file into place, so the path gets a new inode, where a plain write
    /// truncates the old one. The force-quit check on the simulator is the real evidence.
    @Test("each save replaces the file rather than rewriting it in place")
    func eachSaveReplacesTheFile() throws {
        try inDisposableDirectory { directory in
            let store = DocumentsProgramStore(directory: directory)

            try store.save(Self.rosette)
            let before = try Self.inode(of: store.workingURL)
            try store.save(Self.coil)
            let after = try Self.inode(of: store.workingURL)

            #expect(before != after)
        }
    }

    private static func inode(of url: URL) throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int
    }

    // MARK: A failed encode

    /// "A half-written program is worse than a stale one": the encode runs before the disk is
    /// touched. A non-finite start position is one of ADR-037's residual `.encodingFailed`
    /// routes, reachable through the public model API.
    @Test("a program that cannot be encoded leaves the previous file byte for byte")
    func aFailedEncodeLeavesThePreviousFile() throws {
        try inDisposableDirectory { directory in
            let store = DocumentsProgramStore(directory: directory)
            try store.save(Self.rosette)
            let before = try Data(contentsOf: store.workingURL)
            var unencodable = Self.rosette
            unencodable.scenes[0].objects[0].startX = .infinity

            #expect(throws: ProgramDocumentError.encodingFailed) {
                try store.save(unencodable)
            }

            #expect(try Data(contentsOf: store.workingURL) == before)
        }
    }

    // MARK: Refusal

    @Test("a later format version is refused with its version, and left where it was")
    func aFutureVersionIsRefusedAndLeftInPlace() throws {
        try inDisposableDirectory { directory in
            let store = DocumentsProgramStore(directory: directory)
            let bytes = try RefusedDocument.futureVersion
            try bytes.write(to: store.workingURL)

            #expect(throws: ProgramLoadError.document(.unsupportedVersion(2))) {
                try store.load()
            }

            #expect(try Data(contentsOf: store.workingURL) == bytes)
        }
    }

    @Test("a file that is not JSON is refused as corrupt")
    func aCorruptFileIsRefused() throws {
        try inDisposableDirectory { directory in
            let store = DocumentsProgramStore(directory: directory)
            try RefusedDocument.corrupt.write(to: store.workingURL)

            #expect(throws: ProgramLoadError.document(.corrupt)) {
                try store.load()
            }
        }
    }

    /// The reason is the codec's own, propagated rather than re-classified.
    @Test("an unbalanced script is refused with the codec's own reason")
    func anUnbalancedFileIsRefusedWithTheCodecsReason() throws {
        try inDisposableDirectory { directory in
            let store = DocumentsProgramStore(directory: directory)
            let bytes = try RefusedDocument.unbalanced
            try bytes.write(to: store.workingURL)
            let codecError = try #require(throws: ProgramDocumentError.self) {
                try ProgramDocument.decode(bytes)
            }
            guard case .unbalancedScript = codecError else {
                Issue.record("the fixture should be unbalanced, not \(codecError)")
                return
            }

            #expect(throws: ProgramLoadError.document(codecError)) {
                try store.load()
            }
        }
    }

    /// A read failure that is not "no such file" — here, a directory where the file should be.
    @Test("a working path that cannot be read is unreadable, not a first launch")
    func anUnreadablePathIsNotAFirstLaunch() throws {
        try inDisposableDirectory { directory in
            let store = DocumentsProgramStore(directory: directory)
            try FileManager.default.createDirectory(at: store.workingURL, withIntermediateDirectories: false)

            #expect(throws: ProgramLoadError.unreadable) {
                try store.load()
            }
        }
    }

    // MARK: Setting aside

    @Test("setting aside moves the bytes unchanged and frees the working path")
    func settingAsideMovesTheBytes() throws {
        try inDisposableDirectory { directory in
            let store = DocumentsProgramStore(directory: directory)
            let bytes = try RefusedDocument.futureVersion
            try bytes.write(to: store.workingURL)

            let aside = try store.setAside()

            #expect(aside != store.workingURL)
            #expect(aside.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
            #expect(try Data(contentsOf: aside) == bytes)
            #expect(!FileManager.default.fileExists(atPath: store.workingURL.path))
            #expect(try store.load() == nil)
        }
    }

    @Test("a second file set aside never overwrites the first")
    func aSecondSetAsideNeverOverwritesTheFirst() throws {
        try inDisposableDirectory { directory in
            let store = DocumentsProgramStore(directory: directory)
            let first = try RefusedDocument.futureVersion
            let second = RefusedDocument.corrupt

            try first.write(to: store.workingURL)
            let firstAside = try store.setAside()
            try second.write(to: store.workingURL)
            let secondAside = try store.setAside()

            #expect(firstAside != secondAside)
            #expect(try Data(contentsOf: firstAside) == first)
            #expect(try Data(contentsOf: secondAside) == second)
        }
    }

    @Test("setting aside with nothing at the working path throws")
    func settingAsideNothingThrows() throws {
        try inDisposableDirectory { directory in
            let store = DocumentsProgramStore(directory: directory)

            #expect(throws: (any Error).self) {
                try store.setAside()
            }
        }
    }
}
