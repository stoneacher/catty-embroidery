import EmbroideryEngine
import Foundation
import ProgramModel
import StagePreview
import Testing

/// US-308 test item 5 — a stopped run exports the design it actually made.
///
/// **The story's wording is not constructible, and the correction matters.** It asks for
/// "export after `.stoppedByUser`" to be byte-identical to "export at the same point of a
/// completed run". `InterpreterDriver.completionReason` orders completion *before*
/// cancellation, so a single program can never yield `.stoppedByUser` at the point it
/// would also have finished — the reason would come back `.programFinished`. "The same
/// point of a completed run" therefore cannot mean the same program.
///
/// The buildable reading is a **twin-program pair**: one that does all its stitching and
/// then parks forever in a loop that emits nothing, stopped once the stitching is done;
/// and one that does the same stitching and stops because it ran out of bricks. Same
/// design, two endings.
///
/// This is Catty's teardown hazard closed. `Stage.stopProject()` tears down before the
/// share, so the design survives and the completion reason and export model do not — and
/// no producer-side test can see it, which is why ADR-027 makes `stop()` cancel the
/// producer only.
@Suite("Export after a user stop")
struct ExportAfterStopTests {
    /// The pair, asserted with four guards rather than one.
    ///
    /// **The byte comparison alone is vacuous** and must be said out loud: the two
    /// `EmbroideryStream`s are `Equatable` and equal, so identical bytes follow from
    /// equality for free. What earns the test is everything around it — that the stopped
    /// run reached three stitches (a `nil` or empty export model makes any "identical"
    /// claim trivially true), that its model equals one derived **without the driver**,
    /// and that the header describes the *partial* design rather than carrying a stale
    /// count from the program that was never allowed to finish.
    @Test("a stopped run and a completed twin export byte-identical files")
    func stoppedRunMatchesItsCompletedTwin() async throws {
        let stopped = try #require(await Self.stoppedAfterStitching())
        let completed = assembledStream(of: Self.completedProgram)

        // Guard 1: the stop landed where it was meant to. Without this the rest passes
        // for an empty stream.
        #expect(stopped.count == 3)

        // Guard 2: the stopped model is the interpreter's real assembled stream, compared
        // against a value derived independently of the driver — the device Codex round 3
        // forced on US-306, because `count > 0` is satisfied by any non-empty sentinel.
        #expect(stopped == completed)

        // Guard 3: the files are byte-identical.
        let name = "TwinDesign"
        let stoppedFile = try DSTFile(stream: stopped, name: name)
        let completedFile = try DSTFile(stream: completed, name: name)
        #expect(stoppedFile.data == completedFile.data)

        // Guard 4: the header describes what was actually stitched. A stale count here is
        // the failure that would make a machine read past the records that exist.
        #expect(Self.numericHeaderField("ST", in: stoppedFile.data) == "3")
        #expect(Self.numericHeaderField("LA", in: stoppedFile.data) == nil, "LA is not numeric")
    }

    /// The premise the test above rests on, pinned separately so that a failure says which
    /// half broke: the stop really does produce `.stoppedByUser` and really does carry an
    /// export model.
    @Test("the stop reports stoppedByUser and carries an export model")
    func theStopIsWhatItClaimsToBe() async {
        let drained = await Self.driveUntilStitched(3, of: Self.stoppedProgram)

        #expect(drained.termination?.reason == .stoppedByUser)
        #expect(drained.terminalCount == 1)
        #expect(drained.termination?.exportModel.count == 3)
    }

    // MARK: - The twin programs

    /// Does all its stitching, then parks in a loop that emits nothing and cannot
    /// terminate. `wait` rather than a stitching brick, so no further stitches can land
    /// between the third one and the stop — otherwise "the same design" would be a race.
    private static let stoppedProgram = singleObjectProgram([
        .placeAt(x: .number(0), y: .number(0)),
        .stitch,
        .placeAt(x: .number(5), y: .number(0)),
        .stitch,
        .placeAt(x: .number(10), y: .number(0)),
        .stitch,
        .forever,
        .wait(seconds: .number(1)),
        .loopEnd
    ])

    /// The same three stitches, ending because it ran out of bricks.
    private static let completedProgram = singleObjectProgram([
        .placeAt(x: .number(0), y: .number(0)),
        .stitch,
        .placeAt(x: .number(5), y: .number(0)),
        .stitch,
        .placeAt(x: .number(10), y: .number(0)),
        .stitch
    ])

    // MARK: - Helpers

    private static func stoppedAfterStitching() async -> EmbroideryStream? {
        await driveUntilStitched(3, of: stoppedProgram).termination?.exportModel
    }

    /// Grants frames one at a time until `target` stitches have landed, then stops —
    /// gated pacing rather than immediate, because under immediate pacing the producer
    /// races ahead and a mid-run stop is a coin toss.
    ///
    /// The frame cap is a guard against a silent hang if the program ever stops emitting;
    /// it is deliberately far above the six ticks this program needs.
    private static func driveUntilStitched(_ target: Int, of program: Program) async -> DrainedRun {
        let pacing = GatedRunPacing()
        let driver = InterpreterDriver(pacing: pacing)
        let session = driver.start(interpreter(program))

        var drained = DrainedRun()
        var iterator = session.updates.makeAsyncIterator()

        for frame in 0 ..< 50 {
            // The first frame needs no credit: the driver produces one, *then* paces.
            if frame > 0 {
                await pacing.grant()
            }
            guard let update = await iterator.next() else { break }
            drained.updates.append(update)
            if drained.stitches.count >= target {
                break
            }
        }

        // No grant after stopping, for the reason `InterpreterDriverTests` records: a
        // granted frame would wake a parked producer and hide a cancellation-deaf gate.
        session.stop()
        while let update = await iterator.next() {
            drained.updates.append(update)
        }
        return drained
    }

    /// Reads one NUL-padded numeric header field by tag, returning `nil` for a field whose
    /// padding is not NUL.
    ///
    /// A local, independent reader rather than a shared one: `EmbroideryEngineTests`'
    /// `DSTFileReader` deliberately carries its tags and widths as hard-coded literals so
    /// that a shifted layout is caught by something that does not share the writer's
    /// definitions, and the same reasoning applies here. It scans for the tag rather than
    /// assuming an offset, so it cannot silently agree with a reordered header.
    private static func numericHeaderField(_ tag: String, in data: Data) -> String? {
        let header = Array(data.prefix(512))
        let marker = Array("\(tag):".utf8)
        guard
            let start = header.indices.first(where: { index in
                index + marker.count <= header.count
                    && Array(header[index ..< index + marker.count]) == marker
            })
        else {
            return nil
        }

        var end = start + marker.count
        while end < header.count, header[end] != 0x0A {
            end += 1
        }
        let value = header[(start + marker.count) ..< end]
        // Numeric fields are NUL-padded (ADR-012); anything else is not this reader's
        // business, and saying so is what makes the `LA` assertion above meaningful.
        guard value.contains(0x00) || value.allSatisfy({ $0 != 0x20 }) else {
            return nil
        }
        return String(bytes: value.filter { $0 != 0x00 }, encoding: .utf8)
    }
}
