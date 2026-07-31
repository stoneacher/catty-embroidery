import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// US-209's differential half: the interpreter's bytes against a stream built by
/// hand from `goldenSquareStagePath`, plus the dedup structure that decides how
/// many records the design has.
///
/// **What the convergence test can and cannot prove**, stated plainly because the
/// story's AC invites overclaiming it. The claim applies to
/// `interpreterBytesEqualTheHandBuiltStreamBytes` **only**: both of its sides run
/// through the same `DSTFile`, so every defect in `DSTFile`, `DSTHeader` and
/// `DSTStitchRecord` appears identically on both and cancels — no serializer
/// mutant can turn *that* test red. What survives the cancellation is the geometry
/// claim, and US-207 already pins that more strongly in unit space
/// (`recordPositions == goldenSquareRecords`).
///
/// It is in fact weaker still: it is a **logical consequence** of the two
/// fixture-comparing legs, not an independent assertion. With A = interpreter
/// bytes, B = hand-built bytes at the default residue, C = the fixture,
/// `GoldenSquareBytesTests.interpreterBytesEqualTheCommittedGolden` asserts A = C
/// and `residueClassProducesTheGoldenBytes(1e-12)` asserts B = C — the same B,
/// since that is `handBuiltStream()`'s default — so A = B follows by entailment
/// and can never be the only red leg. Kept because it is the AC's literal form,
/// documented so no one reads a diagnosis into it that it cannot deliver
/// (swift-code-reviewer US-209 proved the "diagnostic triangle" an earlier draft
/// claimed here is an unreachable state).
///
/// The suite's other three tests compare against the **frozen fixture**, so
/// serializer defects do *not* cancel there and they are not characterization:
/// measured, `endOfFileRecord` `0xF3` → `0xF2` takes
/// `residueClassProducesTheGoldenBytes` red on all four arguments, and heading
/// `DSTHeader` at an empty stream takes it red plus
/// `zeroResidueDedupsToTwentyOneRecords`.
///
/// So the honest accounting: the convergence leg is entailed and adds no
/// discrimination; the fixture legs do discriminate; and what the suite uniquely
/// contributes either way is making the 22-versus-21 dedup structure
/// **executable** instead of a comment plus a count, and stating the design's
/// pre-conversion stage geometry, which the already-converted
/// `goldenSquareRecords` cannot.
@Suite("Golden program: square manual path")
struct GoldenSquareManualPathTests {
    private let clock = InterpreterClock(tickDelta: 0.05)

    /// Feeds a stage path into a fresh stream through the public seam.
    private func handBuiltStream(residue: Double = goldenSquareNominalTackResidue) -> EmbroideryStream {
        var stream = EmbroideryStream()
        for point in goldenSquareStagePath(tackCentreResidue: residue) {
            // Colour is passed for fidelity only — DST carries no colour table,
            // so no byte below can witness it.
            stream.addStitch(at: point, color: GoldenSquare.color)
        }
        return stream
    }

    @Test("the interpreted bytes equal a hand-built stream's bytes for the same geometry")
    func interpreterBytesEqualTheHandBuiltStreamBytes() throws {
        let manual = handBuiltStream()
        #expect(manual.count == goldenSquareRecords.count)
        try expectBytesEqual(
            runAndSerialize(GoldenSquare.program, clock: clock).file.data,
            DSTFile(stream: manual, name: GoldenSquare.designName).data
        )
    }

    @Test(
        "any distinct tack centre inside the conversion boundary yields the same bytes",
        arguments: [-0.25, -1e-9, -1e-15, 1e-15, 1e-12, 1e-9, 0.24]
    )
    func residueClassProducesTheGoldenBytes(residue: Double) throws {
        // The point of walking the class rather than trusting one value: within the
        // class the structure depends on the residue being non-zero and on nothing
        // else about it — not on its magnitude, not on its sign, and certainly not
        // on it being as small as the interpreter's trig dust.
        //
        // The arguments span the class in both directions, and `−0.25` is the true
        // lower end (`javaRound(2·−0.25) = floor(0.0) = 0`, admissible) while
        // `+0.25` is *outside* it — the asymmetry ADR-012's `floor(x + 0.5)`
        // creates. `0.24` shows the bound is the conversion boundary rather than
        // smallness. Negative witnesses were absent from the first version, which
        // Codex US-209 showed would let a *directional* dedup mutant through: one
        // that dropped only negative unit-identical moves passed every positive
        // residue case and the engine's existing positive dedup test while
        // violating ADR-012's raw-stage comparison.
        #expect(EmbroideryPoint(converting: StagePoint(x: residue, y: residue)) == EmbroideryPoint(x: 0, y: 0))
        let stream = handBuiltStream(residue: residue)
        #expect(stream.count == goldenSquareRecords.count)
        try expectBytesEqual(DSTFile(stream: stream, name: GoldenSquare.designName).data, goldenSquareFixture())
    }

    @Test("a tack centre equal to the last path point dedups away, and the file loses a record")
    func zeroResidueDedupsToTwentyOneRecords() throws {
        // The trap, made permanent and executable. A clean (0, 0) fed straight
        // after the path's closing (0, 0) is dropped by ADR-012's workspace dedup,
        // and the 22nd record — a real zero-delta stitch a machine will sew —
        // never appears. This is why a "clean geometry" hand model would predict
        // 21 records and be wrong, and why the interpreter's trig dust is
        // load-bearing (`tackCentreIsNotTheLastPathPoint`).
        let stream = handBuiltStream(residue: 0)
        #expect(stream.count == goldenSquareRecords.count - 1)

        let file = DSTFile(stream: stream, name: GoldenSquare.designName)
        #expect(file.data.count == 512 + 3 * (goldenSquareRecords.count - 1) + 3)
        #expect(dstHeaderField(Array(file.data.prefix(512)), .stitchCount) == "21")
        #expect(try file.data != goldenSquareFixture())
    }

    @Test("a tack centre at the conversion boundary moves the coordinate instead")
    func boundaryResidueMovesTheCoordinate() throws {
        // Bounds the admissible class from above: at ε = 0.25 the doubled value is
        // exactly 0.5, which `javaRound` (floor(x + 0.5)) takes *up* to unit 1, so
        // the record moves and the design is no longer the golden. Together with
        // the ε = 0 case this pins both ends of the class.
        //
        // Above only — the class is asymmetric. ε = −0.25 doubles to −0.5, which
        // floors to 0 and *is* admissible. `GoldenSquareLiterals` states the bound;
        // `CoordinateConversionTests` owns the rule itself.
        #expect(EmbroideryPoint(converting: StagePoint(x: 0.25, y: 0.25)) == EmbroideryPoint(x: 1, y: 1))
        let stream = handBuiltStream(residue: 0.25)
        #expect(stream.count == goldenSquareRecords.count)
        #expect(try DSTFile(stream: stream, name: GoldenSquare.designName).data != goldenSquareFixture())
    }
}
