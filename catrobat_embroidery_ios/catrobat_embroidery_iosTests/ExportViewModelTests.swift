@testable import catrobat_embroidery_ios
import EmbroideryEngine
import Foundation
import Testing

/// US-308 test items 3 and 6b — preparing the file, and what happens when it cannot be
/// prepared.
///
/// **Export is eager**, and that is forced rather than chosen. A `ShareLink` needs its item
/// at construction time, and it reports failure to the *system* share UI rather than to the
/// app — so a write that happened inside the `FileRepresentation` closure would make
/// `ExportState.failed` unrenderable and US-211's localised message unreachable behind a
/// generic system alert. A second constraint points the same way: `Transferable.exported(as:)`
/// is iOS 18.2+, so at this app's iOS 17 target a closure-only write could not be driven by a
/// test at all — item 3 would be unbuildable, a "test that could not fail" arriving through an
/// availability boundary. So `prepare(exportModel:)` does the work and the closure only hands
/// over a URL that already exists.
///
/// One simplification falls out of that and is worth naming: because the file is already on
/// disk by the time `DSTDesign` is constructed, **the writer never crosses into nonisolated
/// code**, so `DSTFileWriting` needs no `Sendable` gymnastics — unlike `DSTDesign` itself,
/// which does need `nonisolated` because `transferRepresentation` is a nonisolated static
/// requirement under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
@MainActor
@Suite("Export preparation")
struct ExportViewModelTests {
    // MARK: - The happy path (item 3)

    /// The recorder is compared against a `DSTFile` built **independently** in the test, not
    /// against whatever it was handed. Asserting only "the writer was called" would pass
    /// against a view model that wrote an empty file.
    @Test("preparing writes the expected file under the expected name")
    func preparingWritesTheExpectedFile() throws {
        let writer = RecordingDSTFileWriter()
        let subject = ExportViewModel(writer: writer)
        subject.name = "Rose"

        let stream = Self.threeStitchStream()
        subject.prepare(exportModel: stream)

        #expect(writer.written.count == 1)
        let written = try #require(writer.written.first)
        #expect(try written.file == DSTFile(stream: stream, name: "Rose"))
        #expect(written.name.value == "Rose.dst")
        #expect(subject.state == .ready(written.url))
    }

    /// **The name reaches the bytes, not just the file name.** This is the whole point of
    /// the story — Catty's shipping app exports every `.dst` with a blank `LA:` field, and
    /// only its unit tests ever pass a name. A view model that named the file correctly and
    /// serialised with an empty label would pass the test above's file-name assertion.
    @Test("the design name is written into the header label, not only the file name")
    func theNameReachesTheHeaderLabel() throws {
        let writer = RecordingDSTFileWriter()
        let subject = ExportViewModel(writer: writer)
        subject.name = "Rose"
        subject.prepare(exportModel: Self.threeStitchStream())

        let written = try #require(writer.written.first)
        let label = try #require(Self.headerLabel(in: written.file.data))
        #expect(label == "Rose")
    }

    /// Scope decision 2 reaching the file: the trimmed name is what gets serialised, so the
    /// user cannot ship leading spaces into a machine label without seeing them.
    @Test("the name is trimmed before it reaches the file")
    func theNameIsTrimmed() throws {
        let writer = RecordingDSTFileWriter()
        let subject = ExportViewModel(writer: writer)
        subject.name = "  Rose  "
        subject.prepare(exportModel: Self.threeStitchStream())

        let written = try #require(writer.written.first)
        #expect(Self.headerLabel(in: written.file.data) == "Rose")
        #expect(written.name.value == "Rose.dst")
    }

    /// Scope decision 4: one file per session, rewritten. The previous one is removed before
    /// the next is written, so a name change does not leave a trail of stale designs in the
    /// temp directory — Catty never cleans up at all.
    @Test("preparing again removes what the previous preparation wrote")
    func preparingAgainCleansUp() {
        let writer = RecordingDSTFileWriter()
        let subject = ExportViewModel(writer: writer)
        subject.name = "First"
        subject.prepare(exportModel: Self.threeStitchStream())
        subject.name = "Second"
        subject.prepare(exportModel: Self.threeStitchStream())

        #expect(writer.removeAllCount == 2, "once before each write")
        #expect(writer.written.count == 2)
        #expect(writer.written.last?.name.value == "Second.dst")
    }

    /// Discarding is what `RunViewModel.reset()` triggers: the design is gone, so the file
    /// must be too, and the state must not keep offering a URL that no longer describes
    /// anything on screen.
    @Test("discarding returns to idle and removes the file")
    func discardingCleansUp() {
        let writer = RecordingDSTFileWriter()
        let subject = ExportViewModel(writer: writer)
        subject.name = "Rose"
        subject.prepare(exportModel: Self.threeStitchStream())

        subject.discard()

        #expect(subject.state == .idle)
        #expect(writer.removeAllCount == 2, "once before the write, once on discard")
    }

    /// **A design name containing `/` still produces a file**, and this is the one place the
    /// two name types visibly disagree: `DesignName` accepts `/` because the `LA` field
    /// carries it untouched, and a file name cannot. The label keeps it; the file name gets
    /// an underscore. Found by integration rather than by planning — the strict
    /// `DSTFileName.validating` path would have refused a name the user was just told was
    /// fine.
    @Test("a name the label accepts but a file name cannot is sanitised for the file only")
    func aPathSeparatorIsSanitisedForTheFileOnly() throws {
        let writer = RecordingDSTFileWriter()
        let subject = ExportViewModel(writer: writer)
        subject.name = "a/b"
        subject.prepare(exportModel: Self.threeStitchStream())

        let written = try #require(writer.written.first)
        #expect(Self.headerLabel(in: written.file.data) == "a/b", "the label keeps it")
        #expect(written.name.value == "a_b.dst", "the file name does not")
    }

    /// Nothing is prepared for a name the user has not finished typing. `prepare` runs on run
    /// termination regardless of what the field holds, so it must be a no-op rather than
    /// writing a file the gate would refuse to share anyway.
    @Test("an invalid name prepares nothing and stays idle")
    func anInvalidNamePreparesNothing() {
        let writer = RecordingDSTFileWriter()
        let subject = ExportViewModel(writer: writer)
        subject.name = "   "

        subject.prepare(exportModel: Self.threeStitchStream())

        #expect(subject.state == .idle)
        #expect(writer.written.isEmpty)
    }

    // MARK: - Failure (item 3's second half)

    /// A write that throws leaves the export failed and **the design untouched**. The story
    /// asks for the design to stay on screen and stay resettable, and the structural half of
    /// that is that this object owns no part of the run.
    @Test("a failing writer produces a failed state without touching the design")
    func aFailingWriterFails() {
        let writer = ThrowingDSTFileWriter()
        let subject = ExportViewModel(writer: writer)
        subject.name = "Rose"
        let stream = Self.threeStitchStream()

        subject.prepare(exportModel: stream)

        #expect(subject.state == .failed(.writeFailed))
        // The export model is a value and cannot have been mutated; asserting it says so.
        #expect(stream.count == 3)
    }

    /// **The overflow is caught before the writer is reached**, which is what makes the
    /// localised message reachable at all: inside a `Transferable` the user would get the
    /// system's generic share failure instead. `writeAttempts == 0` is the assertion that
    /// pins the pre-flight ordering — a view model that wrote first and validated afterwards
    /// would still reach `.failed` and pass every other assertion here.
    @Test("a header overflow fails before the writer is reached")
    func overflowFailsPreflight() {
        let writer = RecordingDSTFileWriter()
        let subject = ExportViewModel(writer: writer)
        subject.name = "Rose"

        subject.prepare(exportModel: Self.hundredColorBlockStream())

        #expect(
            subject.state
                == .failed(.serialization(.fieldOverflow(
                    field: .colorBlocks, value: "100", limit: 99
                )))
        )
        #expect(writer.written.isEmpty)
        #expect(writer.removeAllCount == 0, "nothing was written, so nothing was cleaned up")
    }

    /// The control: a design just inside the limit prepares successfully. Without it, the
    /// test above passes against a view model that refuses everything — US-211's own lesson,
    /// where the exit assertion for a typed-error story is the `.success` case.
    @Test("ninety-nine colour blocks still prepare")
    func ninetyNineBlocksStillPrepare() {
        let writer = RecordingDSTFileWriter()
        let subject = ExportViewModel(writer: writer)
        subject.name = "Rose"

        subject.prepare(exportModel: Self.ninetyNineColorBlockStream())

        #expect(writer.written.count == 1)
        if case .failed = subject.state {
            Issue.record("a design inside the limit must not fail")
        }
    }

    // MARK: - The message (item 6b)

    /// US-211's error carries `limit`, and this is where it becomes a sentence a user can
    /// act on rather than `print("File could not be written!")`, which is Catty's actual
    /// error handling.
    ///
    /// The `≠ key` check is the one that matters, for the reason `AppStringsTests` records:
    /// a missing catalog entry renders as its own key and looks like text.
    @Test("the colour-block overflow message names the limit")
    func theOverflowMessageNamesTheLimit() {
        let error = ExportError.serialization(
            .fieldOverflow(field: .colorBlocks, value: "100", limit: 99)
        )
        let message = String(localized: error.message)

        #expect(message.contains("99"))
        #expect(message != "stage.export.error.color.limit")
    }

    /// Three different overflowing fields must not produce one generic sentence: a design
    /// with too many stitches, too many colours, or too large an extent are different
    /// problems with different fixes.
    @Test("the three reachable overflow fields produce distinct messages")
    func theReachableFieldsReadDifferently() {
        let stitches = String(localized: ExportError.serialization(
            .fieldOverflow(field: .stitchCount, value: "1000000", limit: 999_999)
        ).message)
        let colors = String(localized: ExportError.serialization(
            .fieldOverflow(field: .colorBlocks, value: "100", limit: 99)
        ).message)
        let size = String(localized: ExportError.serialization(
            .fieldOverflow(field: .extentPlusX, value: "10000", limit: 9999)
        ).message)

        #expect(stitches != colors)
        #expect(colors != size)
        #expect(stitches != size)
        for message in [stitches, colors, size] {
            #expect(message.contains("stage.export") == false, "fell back to a key")
        }
    }

    /// The six fields ADR-025 records as unable to overflow route to one generic sentence
    /// rather than to six invented nouns. Shipping copy for unreachable states is the mistake
    /// ADR-028 had to undo; trapping is the one ADR-025 removed.
    @Test("an unreachable field falls back to a generic message rather than trapping")
    func unreachableFieldsAreGeneric() {
        let message = String(localized: ExportError.serialization(
            .fieldOverflow(field: .previousDesign, value: "******", limit: 99999)
        ).message)

        #expect(message.isEmpty == false)
        #expect(message.contains("stage.export") == false)
    }

    @Test("a write failure has its own message")
    func writeFailureHasAMessage() {
        let message = String(localized: ExportError.writeFailed.message)
        #expect(message.isEmpty == false)
        #expect(message.contains("stage.export") == false)
    }

    // MARK: - Fixtures

    private static func threeStitchStream() -> EmbroideryStream {
        var stream = EmbroideryStream()
        for x in 0 ..< 3 {
            stream.addStitch(at: StagePoint(x: Double(x), y: 0))
        }
        return stream
    }

    /// `CO` is changes + 1, so 99 changes is 100 blocks — one past the 2-wide field.
    private static func hundredColorBlockStream() -> EmbroideryStream {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        for _ in 0 ..< 99 {
            stream.addColorChange()
            stream.addStitch(at: StagePoint(x: 1, y: 1))
        }
        return stream
    }

    private static func ninetyNineColorBlockStream() -> EmbroideryStream {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        for _ in 0 ..< 98 {
            stream.addColorChange()
            stream.addStitch(at: StagePoint(x: 1, y: 1))
        }
        return stream
    }

    /// Reads the space-padded `LA` label out of a header, trimming the padding.
    ///
    /// A local reader carrying its own literals, for the reason `EmbroideryEngineTests`'
    /// `DSTFileReader` records: an oracle that shared the writer's definitions would not
    /// catch a shifted layout.
    private static func headerLabel(in data: Data) -> String? {
        let header = Array(data.prefix(512))
        let marker = Array("LA:".utf8)
        guard Array(header.prefix(3)) == marker else { return nil }
        var end = 3
        while end < header.count, header[end] != 0x0A {
            end += 1
        }
        return String(bytes: header[3 ..< end], encoding: .utf8)?
            .trimmingCharacters(in: .whitespaces)
    }
}
