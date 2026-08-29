@testable import catrobat_embroidery_ios
import EmbroideryEngine
import Foundation
import Testing

/// The **production** writer, against a real filesystem.
///
/// **This suite exists because a cross-vendor review named its absence as the branch's
/// largest blind spot, and the point is worth stating plainly**: every other export test
/// injects `RecordingDSTFileWriter`, which returns a URL without creating anything. So the
/// entire app suite would have passed if `TemporaryDSTFileWriter.write` had written the
/// wrong bytes, written nothing at all, or handed back a URL pointing somewhere else. The
/// injected seam that makes the rest of the story testable is exactly what leaves this one
/// class untested — which is the general hazard with a mock at the I/O boundary, not a
/// peculiarity of this branch.
///
/// Each test writes into its own `UUID`-named directory and removes it afterwards, so the
/// suite stays parallel-safe and leaves nothing behind (Swift Testing runs tests in
/// parallel; a fixed path would be a shared mutable resource).
@MainActor
@Suite("Temporary DST file writer")
struct TemporaryDSTFileWriterTests {
    /// The bytes on disk are the bytes the caller handed over — the one assertion no
    /// recording double can make.
    @Test("the bytes on disk are the DSTFile's own")
    func theBytesOnDiskAreTheFiles() throws {
        try Self.inDisposableDirectory { directory in
            let writer = TemporaryDSTFileWriter(directory: directory)
            let file = try DSTFile(stream: Self.threeStitchStream(), name: "Rose")
            let name = try DSTFileName.validating("Rose").get()

            let url = try writer.write(file, named: name)

            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(try Data(contentsOf: url) == file.data)
            #expect(url.lastPathComponent == "Rose.dst")
        }
    }

    /// The name reaches the **bytes** through the production path too, not only through the
    /// recorded one. `LA:` is the first field in the header, so this reads it where a DST
    /// parser would.
    @Test("the header label written to disk carries the design name")
    func theLabelOnDiskCarriesTheName() throws {
        try Self.inDisposableDirectory { directory in
            let writer = TemporaryDSTFileWriter(directory: directory)
            let file = try DSTFile(stream: Self.threeStitchStream(), name: "Rose")

            let url = try writer.write(file, named: DSTFileName.validating("Rose").get())
            let written = try Data(contentsOf: url)

            #expect(written.prefix(3) == Data("LA:".utf8))
            #expect(written.prefix(8) == Data("LA:Rose ".utf8), "space-padded to 15")
        }
    }

    /// The writer creates its directory rather than requiring one — otherwise the very first
    /// export of an app run fails, and nothing else in the suite would notice.
    @Test("the directory is created on first write")
    func theDirectoryIsCreatedOnDemand() throws {
        try Self.inDisposableDirectory { directory in
            let nested = directory.appending(path: "not-yet-there")
            #expect(FileManager.default.fileExists(atPath: nested.path) == false)

            let writer = TemporaryDSTFileWriter(directory: nested)
            let file = try DSTFile(stream: Self.threeStitchStream(), name: "Rose")
            let url = try writer.write(file, named: DSTFileName.validating("Rose").get())

            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    /// **`removeAll()` really removes**, and it is the directory that goes, not just the
    /// file — which is what makes a rename unable to orphan the previous name (ADR-026,
    /// scope decision 4).
    @Test("removeAll deletes the directory and everything in it")
    func removeAllDeletesTheDirectory() throws {
        try Self.inDisposableDirectory { directory in
            let nested = directory.appending(path: "session")
            let writer = TemporaryDSTFileWriter(directory: nested)
            let file = try DSTFile(stream: Self.threeStitchStream(), name: "Rose")
            let url = try writer.write(file, named: DSTFileName.validating("Rose").get())
            #expect(FileManager.default.fileExists(atPath: url.path))

            writer.removeAll()

            #expect(FileManager.default.fileExists(atPath: url.path) == false)
            #expect(FileManager.default.fileExists(atPath: nested.path) == false)
        }
    }

    /// At most one file per session, which is the property scope decision 4 actually claims —
    /// and the one a per-*file* cleanup would break the moment the name changed.
    @Test("a rename leaves exactly one file behind, not two")
    func aRenameLeavesOneFile() throws {
        try Self.inDisposableDirectory { directory in
            let nested = directory.appending(path: "session")
            let writer = TemporaryDSTFileWriter(directory: nested)
            let file = try DSTFile(stream: Self.threeStitchStream(), name: "Rose")

            _ = try writer.write(file, named: DSTFileName.validating("First").get())
            writer.removeAll()
            _ = try writer.write(file, named: DSTFileName.validating("Second").get())

            let contents = try FileManager.default.contentsOfDirectory(atPath: nested.path)
            #expect(contents == ["Second.dst"])
        }
    }

    /// `removeAll()` on a directory that was never created is a no-op rather than a throw —
    /// the state `ExportViewModel.discard()` reaches before anything has been prepared, and
    /// it runs on every selection.
    @Test("removeAll on a directory that never existed does nothing")
    func removeAllOnNothingIsHarmless() throws {
        try Self.inDisposableDirectory { directory in
            TemporaryDSTFileWriter(directory: directory.appending(path: "never")).removeAll()
        }
    }

    // MARK: - Helpers

    private static func inDisposableDirectory(_ body: (URL) throws -> Void) throws {
        let directory = URL.temporaryDirectory.appending(path: "writer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private static func threeStitchStream() -> EmbroideryStream {
        var stream = EmbroideryStream()
        for x in 0 ..< 3 {
            stream.addStitch(at: StagePoint(x: Double(x), y: 0))
        }
        return stream
    }
}
