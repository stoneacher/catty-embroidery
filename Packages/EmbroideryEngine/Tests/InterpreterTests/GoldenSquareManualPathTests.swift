import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// US-209's differential half: the interpreter's bytes against a stream built by
/// hand from `goldenSquareStagePath`, plus the dedup structure that decides how
/// many records the design has.
///
/// **What this convergence can and cannot prove**, stated plainly because the
/// story's AC invites overclaiming it: both sides run through the same `DSTFile`,
/// so every defect in `DSTFile`, `DSTHeader` and `DSTStitchRecord` appears
/// identically on both sides and cancels. No serializer mutant can turn these
/// tests red. What survives the cancellation is the geometry claim — that the
/// interpreter's stream agrees with a hand-stated stage path — and US-207 already
/// pins that more strongly in unit space (`recordPositions == goldenSquareRecords`).
///
/// So the honest accounting is: this suite is *characterization*, and its unique
/// contribution is not a mutant kill but making the 22-versus-21 dedup structure
/// **executable** instead of a comment plus a count, and stating the design's
/// pre-conversion geometry (which `goldenSquareRecords`, being already converted,
/// cannot). The serializer mutants are caught by
/// `GoldenSquareBytesTests.interpreterBytesEqualTheCommittedGolden`, whose
/// expected side is a frozen file that cannot move with the code — which is
/// exactly why that leg and this one are both here. The diagnostic triangle:
/// this red and the fixture green means the hand model's own assumption broke;
/// both red means the serializer or the stream moved; fixture red and this green
/// means the pipeline moved.
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
        arguments: [1e-15, 1e-12, 1e-9, 0.24]
    )
    func residueClassProducesTheGoldenBytes(residue: Double) throws {
        // The point of walking the class rather than trusting one value: the
        // structure depends on the residue being non-zero and on nothing else
        // about it. `0.24` is the near-boundary witness — it shows the class is
        // bounded by the ×2 conversion boundary, not by the residue being small.
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
        #expect(EmbroideryPoint(converting: StagePoint(x: 0.25, y: 0.25)) == EmbroideryPoint(x: 1, y: 1))
        let stream = handBuiltStream(residue: 0.25)
        #expect(stream.count == goldenSquareRecords.count)
        #expect(try DSTFile(stream: stream, name: GoldenSquare.designName).data != goldenSquareFixture())
    }
}
