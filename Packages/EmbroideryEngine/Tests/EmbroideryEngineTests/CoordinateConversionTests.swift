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
}
