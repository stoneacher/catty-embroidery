import EmbroideryEngine
import Testing

@Suite("Stage → embroidery coordinate conversion (ADR-007, ADR-012)")
struct CoordinateConversionTests {
    @Test(
        "Applies factor 2.0 with Java-style floor(x + 0.5) rounding",
        arguments: zip(
            [
                StagePoint(x: 10.5, y: -3), // canonical case from the story
                StagePoint(x: -3.25, y: -3.25), // negative half: floor(−6.5 + 0.5) = −6; Swift .rounded() would give −7
                StagePoint(x: -0.25, y: 0.25), // halves around zero round toward +∞
                StagePoint(x: 0, y: 0),
                StagePoint(x: 250, y: 250) // stage edge (500×500 pt stage ≈ 100×100 mm hoop)
            ],
            [
                EmbroideryPoint(x: 21, y: -6),
                EmbroideryPoint(x: -6, y: -6),
                EmbroideryPoint(x: 0, y: 1),
                EmbroideryPoint(x: 0, y: 0),
                EmbroideryPoint(x: 500, y: 500)
            ]
        )
    )
    func conversion(stage: StagePoint, expected: EmbroideryPoint) {
        #expect(EmbroideryPoint(converting: stage) == expected)
    }

    @Test("No y-flip: stage y-up maps straight to +Y")
    func noYFlip() {
        #expect(EmbroideryPoint(converting: StagePoint(x: 0, y: 10)) == EmbroideryPoint(x: 0, y: 20))
        #expect(EmbroideryPoint(converting: StagePoint(x: 0, y: -10)) == EmbroideryPoint(x: 0, y: -20))
    }

    // MARK: - The conversion is failable (US-210, ADR-020)

    @Test("Non-finite and unrepresentable coordinates convert to nil instead of trapping")
    func unconvertibleCoordinates() {
        // `Int(javaRound(value × 2))` traps on all four of these. ADR-020 makes
        // the initializer failable so the trap is unrepresentable at the type
        // level rather than avoided by a predicate every caller must remember.
        #expect(EmbroideryPoint(converting: StagePoint(x: .infinity, y: 0)) == nil)
        #expect(EmbroideryPoint(converting: StagePoint(x: 0, y: -.infinity)) == nil)
        #expect(EmbroideryPoint(converting: StagePoint(x: .nan, y: 0)) == nil)
        #expect(EmbroideryPoint(converting: StagePoint(x: 0, y: .nan)) == nil)
        // Finite but past the ×2 conversion's `Int` range.
        #expect(EmbroideryPoint(converting: StagePoint(x: 5e18, y: 0)) == nil)
        #expect(EmbroideryPoint(converting: StagePoint(x: 0, y: -5e18)) == nil)
    }

    @Test("A coordinate just inside the ×2 conversion range still converts")
    func nearBoundaryCoordinateStillConverts() {
        // 4.6e18 × 2 = 9.2e18, just under `Int.max` — the guard rejects what
        // does not fit, not what is merely large.
        #expect(EmbroideryPoint(converting: StagePoint(x: 4.6e18, y: -4.6e18))
            == EmbroideryPoint(x: 9_200_000_000_000_000_000, y: -9_200_000_000_000_000_000))
    }
}
