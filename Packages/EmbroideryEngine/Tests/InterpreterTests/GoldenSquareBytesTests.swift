import EmbroideryEngine
import Foundation
import Interpreter
import ProgramModel
import Testing

/// US-209: the square program piped all the way to **machine bytes** —
/// `Interpreter.assembledStream()` → `DSTFile` → `Data` — closing the blind spot
/// the workflow journal has carried since US-107 (2026-07-10): no test took
/// pattern output through the stream and the serializer to real bytes.
///
/// **What the byte path can and cannot add.** `DSTFile` is a pure function of the
/// stream *and a lossy one* — DST stores no thread-colour table, only change
/// flags — so the byte vector is a coarsening of what US-207 already pins twice
/// over. Every interpreter defect visible here is visible in `assembledStream()`,
/// which means this suite adds no interpreter discrimination at all. What it adds
/// is **composition** (the header, the deltas and the terminator produced from a
/// real program rather than a synthetic stream), the **name join** below, the
/// **extent semantics** ADR-012 says the Catty fixtures cannot reach, and an
/// externally validated fixture. Coverage claimed beyond that would be the defect
/// class US-207 and US-208 each surfaced.
///
/// Specifically not covered: ADR-015 colour application (no byte can witness it —
/// `GoldenProgramSquareTests.silentStartStillAppliesTheColour` owns it), and
/// `javaRound`'s negative-half asymmetry (every stage value here doubles to an
/// exact integer and none is a negative half, so `javaRound` and `.rounded()`
/// agree at every point; US-105/US-106 own that edge).
///
/// ADR-019 screening, which that ADR asks of any golden compared against a
/// threshold: the pattern interval threshold is *inherited* — 20.0 / 5 is exactly
/// 4.0, on the boundary, but the residues are purely perpendicular to motion
/// (~3e-31 against a 1.776e-15 half-ulp) and ADR-019 states outright that
/// US-207's square needs no tripwire. This story changes no geometry. The two
/// thresholds this story newly compares against are measured in
/// `thresholdMarginsAreWideEnoughToNotDecideTheBytes`.
@Suite("Golden program: square bytes")
struct GoldenSquareBytesTests {
    private let clock = InterpreterClock(tickDelta: 0.05)

    // MARK: - The committed golden

    @Test("the golden fixture is bundled and intact")
    func goldenFixtureIsBundledAndIntact() throws {
        // Separate from the byte diff so a broken `resources:` declaration names
        // itself instead of surfacing as a puzzling #require failure there.
        // 512-byte header + 22 three-byte records + the 3-byte end-of-file record.
        #expect(try goldenSquareFixture().count == 512 + 3 * goldenSquareRecords.count + 3)
    }

    @Test("the interpreted square serializes to the committed golden bytes")
    func interpreterBytesEqualTheCommittedGolden() throws {
        // The regression anchor for the whole program→machine path, and the leg
        // that carries the external verification: these exact bytes were opened
        // in an embroidery viewer and decoded independently (see the fixture's
        // PROVENANCE.md). US-210 will edit `EmbroideryStream` and
        // `DSTStitchRecord` and requires this to stay green untouched.
        try expectBytesEqual(run().file.data, goldenSquareFixture())
    }

    // MARK: - Header fields

    @Test("the file's header declares the program's own stitch and colour-stop counts")
    func headerFieldsMatchTheProgramsActualCounts() throws {
        let result = try run()
        let file = result.file
        let stream = result.stream
        let header = Array(file.data.prefix(512))

        // Read out of the *file*, not a separately built `DSTHeader` — which is
        // what US-208's CO assertion did, and it cannot see a serializer that
        // fails to put the header it built into the file it emits.
        #expect(dstHeaderTag(header, .stitchCount) == "ST:")
        #expect(dstHeaderTag(header, .colorBlocks) == "CO:")

        // Against what the run actually produced, not against literals: the AC is
        // that the header agrees with the program, and a golden matching only a
        // hardcoded "22" would not notice the two drifting apart.
        #expect(dstHeaderField(header, .stitchCount) == "\(stream.count)")
        #expect(dstHeaderField(header, .colorBlocks) == "\(stream.colorChangeCount + 1)")
        // And the values, so the pair cannot agree on a wrong number: 22 records
        // (US-207's golden), and one colour block because a single colour set
        // before the first stitch is silent (ADR-015).
        #expect(stream.count == 22)
        #expect(stream.colorChangeCount + 1 == 1)
    }

    @Test("a design wholly in negative space writes extents relative to its first stitch")
    func displacedSquareWritesExtentsRelativeToItsFirstStitch() {
        // Composition, **not** a unique mutant kill — the first draft of this
        // comment claimed one and mutation testing disproved it. Replacing
        // `abs(min(box.min.x - first.x, 0))` with `abs(box.min.x)` dies in
        // `DSTHeaderTests.nonOriginFirstStitch` too, whose synthetic stream has
        // first stitch (20, 10) over a box starting at (0, 0), so the mutant
        // reads 0 where 20 is correct. Measured, not assumed: with this test
        // skipped the mutant still takes two pre-existing tests red.
        //
        // What is new here is the *route*: this is the only design in the package
        // that reaches `DSTHeader` through a real interpreted program while lying
        // wholly in negative embroidery space, with the box corner distinct from
        // both the origin and the first stitch. The object starts at (−20, −20)
        // heading 90, so the closing heading is 90 again and the tack runs along
        // ±x, putting the box at min (−46, −80) / max (0, −40) with the first
        // stitch at (−40, −40). ADR-012 calls a non-origin-start case out
        // specifically as what the Catty fixtures cannot cover.
        var interpreter = Interpreter(program: GoldenSquare.displacedProgram, clock: clock)
        _ = interpreter.run(maxTicks: 100)
        let header = Array(DSTFile(stream: interpreter.assembledStream(), name: GoldenSquare.designName)
            .data.prefix(512))

        // Magnitudes only, relative to the first stitch (ADR-012). The mutant
        // named above reads 46 and 80 here.
        #expect(dstHeaderField(header, .extentPlusX) == "40")
        #expect(dstHeaderField(header, .extentMinusX) == "6")
        #expect(dstHeaderField(header, .extentPlusY) == "0")
        #expect(dstHeaderField(header, .extentMinusY) == "40")
        // A closed path returns to its start, so the absolute end offsets vanish —
        // which is also why neither square can pin a *signed* AX/AY (a gap left
        // to the engine suite, noted in the story close-out).
        #expect(dstHeaderField(header, .endOffsetX) == "0")
        #expect(dstHeaderField(header, .endOffsetY) == "0")
    }

    // MARK: - The name join

    @Test("the design name in the file comes from the program's own brick")
    func designNameInTheFileComesFromTheProgram() throws {
        let result = try run()
        let file = result.file
        let events = result.events

        // `Interpreter` has no API that produces a file: the name lives only in
        // the `finalizeRequested` payload, and nothing in the package joined it to
        // `LA` before this story. A test restating "square" itself would still
        // pass with the brick's name ignored entirely.
        #expect(finalizedDesignName(events) == GoldenSquare.designName)
        #expect(dstHeaderTag(Array(file.data.prefix(512)), .label) == "LA:")
        #expect(dstHeaderField(Array(file.data.prefix(512)), .label) == GoldenSquare.designName)
    }

    @Test("a name needing sanitization reaches the label field raw and is sanitized there")
    func designNameIsSanitizedAtTheHeaderNotByTheInterpreter() {
        // Written as escapes, not literal characters, so the test states its own
        // scalar sequence: a decomposed "ä" in the source would be two scalars and
        // sanitize differently.
        let name = "N\u{E4}hen \u{2B50} Quadrat gro\u{DF}"
        var spec = GoldenSquare.spec
        spec.designName = name

        var interpreter = Interpreter(program: polygonProgram(spec), clock: clock)
        let events = interpreter.run(maxTicks: 100)

        // The event carries the name *unsanitized* — sanitization is `DSTHeader`'s
        // job (ADR-012's 15-char limit, non-ASCII to "_"). A mutant that truncated
        // in the interpreter would pass `designNameInTheFileComesFromTheProgram`,
        // whose name is 6 ASCII characters and survives any sanitizer untouched.
        #expect(finalizedDesignName(events) == name)

        let file = DSTFile(stream: interpreter.assembledStream(), name: name)
        // Each non-ASCII scalar becomes one "_", then the whole is cut to 15:
        // N ä h e n ␠ ⭐ ␠ Q u a d r a t | ␠ g r o ß
        #expect(dstHeaderField(Array(file.data.prefix(512)), .label) == "N_hen _ Quadrat")
    }

    // MARK: - ADR-019 threshold screening

    @Test("the thresholds this story compares against are not close enough to decide the bytes")
    func thresholdMarginsAreWideEnoughToNotDecideTheBytes() throws {
        let stream = try run().stream

        // (1) The ±121 record-delta limit. `DSTStitchRecord.init` *traps* outside
        // it and `DSTFile`'s own doc flags a round-then-subtract disagreement at
        // the exact boundary, so this measures the quantity rather than asserting
        // the consequence (US-207 asserts `!isJump`; ADR-019 asks for the margin).
        let deltas = zip(goldenSquareRecords, goldenSquareRecords.dropFirst()).map {
            max(abs($1.x - $0.x), abs($1.y - $0.y))
        }
        #expect(deltas.max() == 10)
        #expect(DSTStitchRecord.maxDelta - (deltas.max() ?? 0) == 111)

        // (2) The ×2 + `javaRound` conversion boundary — the threshold that
        // actually decides these bytes, and the one the residue class is bounded
        // by. Every doubled stage coordinate sits on a whole unit, so the margin
        // is the full half-unit; nothing here rounds by a hair.
        let doubled = goldenSquareStagePath().flatMap {
            [$0.x * EmbroideryPoint.stitchPointUnitFactor, $0.y * EmbroideryPoint.stitchPointUnitFactor]
        }
        #expect(doubled.allSatisfy { abs($0 - $0.rounded()) < 1e-9 })
        #expect(stream.stitches.allSatisfy { !$0.isJump && !$0.isColorChange })
    }

    // MARK: - Helpers

    /// The square, run and serialized. `runAndSerialize` lives in
    /// `DSTHeaderFieldReader.swift` so both US-209 suites share one path to bytes.
    private func run() throws -> GoldenProgramRun {
        try runAndSerialize(GoldenSquare.program, clock: clock)
    }
}
