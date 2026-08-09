import EmbroideryEngine
import StagePreview
import Testing

@Suite("Stage geometry")
struct StageGeometryTests {
    @Test("the stage is ADR-007's 500 x 500 points centred on the origin")
    func stageMatchesTheADR() {
        #expect(StageGeometry.sideInPoints == 500)
        #expect(StageGeometry.halfExtentInPoints == 250)
        #expect(StageGeometry.box == StageBox(minX: -250, minY: -250, maxX: 250, maxY: 250))
        #expect(StageGeometry.box.width == StageGeometry.sideInPoints)
        #expect(StageGeometry.box.height == StageGeometry.sideInPoints)
        #expect(StageGeometry.box.center == StagePoint(x: 0, y: 0))
    }

    /// The unit chain ADR-007 pins: 1 pt = 2 embroidery units = 0.2 mm, so the
    /// stage is the ~100 mm hoop the samples are sized against.
    @Test("the stage is a 100 mm hoop")
    func stageIsAHundredMillimetreHoop() {
        #expect(StageGeometry.millimetresPerPoint == 0.2)
        #expect(StageGeometry.sideInMillimetres == 100)
        #expect(StageGeometry.millimetresPerPoint * EmbroideryPoint.stitchPointUnitFactor == 0.4)
    }

    /// The doc comment's central claim, asserted rather than left as prose: a
    /// coordinate far outside the stage still converts, still stitches, and
    /// still reaches the stream. `StageGeometry` describes the hoop; it bounds
    /// nothing.
    @Test("a point far outside the stage is still perfectly stitchable")
    func geometryDoesNotBoundEngineInput() {
        let outside = StagePoint(x: 10000, y: -8000)
        #expect(outside.x > StageGeometry.box.maxX)
        #expect(EmbroideryPoint(converting: outside) != nil)

        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: outside)
        #expect(stream.count > 1)
        #expect(stream.boundingBox?.max.x == 20000)
    }
}
