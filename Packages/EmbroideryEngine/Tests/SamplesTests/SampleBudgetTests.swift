import EmbroideryEngine
import Samples
import Testing

/// Story items 4 and 5 — the budgets every sample must satisfy, parameterised so
/// a sample added later inherits them automatically.
@Suite("Sample budgets")
struct SampleBudgetTests {
    /// Story item 5. At one tick per frame (ADR-018's `tickDelta = 1/60`) a
    /// 120-tick program animates for two seconds. The AC's own wording for why:
    /// "a sample that finishes in 39 ticks (0.65 s) is not a preview, it is a
    /// flash."
    @Test("every sample animates for at least two seconds", arguments: SampleLibrary.all)
    func tickCountIsAtLeast120(_ sample: SampleProgram) {
        let measured = run(sample)
        #expect(
            measured.ticks >= 120,
            "\(sample.id.rawValue) runs \(measured.ticks) ticks — \(Double(measured.ticks) / 60.0) s"
        )
    }

    /// Story item 4 — ADR-007's stage is 500 × 500 points about a centre origin,
    /// so every coordinate must be within ±250 on both axes.
    ///
    /// Asserted in **stage points**, the unit ADR-007 states, by converting the
    /// stream's machine units back through the engine's own factor rather than a
    /// re-typed 2.0.
    @Test("every design fits ADR-007's 500 x 500 stage", arguments: SampleLibrary.all)
    func boundingBoxFitsTheStage(_ sample: SampleProgram) throws {
        let measured = run(sample)
        let bounds = try #require(stageBounds(of: measured.stream), "\(sample.id.rawValue) stitched nothing")
        let extreme = bounds.extreme
        #expect(
            extreme <= 250,
            """
            \(sample.id.rawValue) reaches \(extreme) stage points \
            (x [\(bounds.minX), \(bounds.maxX)], y [\(bounds.minY), \(bounds.maxY)])
            """
        )
    }

    /// Story item 5's second half: the per-tick stitch maximum is **recorded in
    /// the test output**, because US-306 sizes its per-frame budget against it.
    ///
    /// It is also *pinned*, which is strictly stronger than recording — a printed
    /// number nobody asserts drifts silently, and US-306 would then be citing a
    /// figure no test defends.
    @Test("per-tick stitch maximum is the number US-306's budget is sized against",
          arguments: [
              (SampleID.octagonRosette, 51),
              (SampleID.squareCoil, 132)
          ])
    func perTickStitchMaximum(_ id: SampleID, _ expected: Int) {
        let measured = run(SampleLibrary[id])
        print("""
        US-301 budget — \(id.rawValue): \
        \(measured.ticks) ticks, \
        \(measured.stitchEventCount) stitch events, \
        per-tick maximum \(measured.perTickStitchMaximum)
        """)
        #expect(measured.perTickStitchMaximum == expected)
    }

    /// A sample that reached the harness's tick cap is a broken sample, not a
    /// long one — assert the run terminated on its own.
    @Test("every sample finishes well inside the harness cap", arguments: SampleLibrary.all)
    func everySampleTerminates(_ sample: SampleProgram) {
        let measured = run(sample)
        #expect(measured.ticks < 10000)
    }
}
