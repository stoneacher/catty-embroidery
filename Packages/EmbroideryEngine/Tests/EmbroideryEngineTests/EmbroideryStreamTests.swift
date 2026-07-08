import EmbroideryEngine
import Testing

@Suite("EmbroideryStream accumulation")
struct EmbroideryStreamTests {
    @Test("Empty stream has no stitches, no color changes, no extents")
    func emptyStream() {
        let stream = EmbroideryStream()
        #expect(stream.stitches.isEmpty)
        #expect(stream.colorChangeCount == 0)
        #expect(stream.boundingBox == nil)
        #expect(stream.firstStitchPosition == nil)
        #expect(stream.lastStitchPosition == nil)
    }

    @Test("Appending N stitches preserves count and order")
    func accumulation() {
        let stagePoints = [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 5, y: -5),
            StagePoint(x: 10.5, y: -3)
        ]
        var stream = EmbroideryStream()
        for point in stagePoints {
            stream.addStitch(at: point)
        }

        #expect(stream.count == 3)
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 10, y: -10),
            EmbroideryPoint(x: 21, y: -6)
        ])
        #expect(stream.firstStitchPosition == EmbroideryPoint(x: 0, y: 0))
        #expect(stream.lastStitchPosition == EmbroideryPoint(x: 21, y: -6))
    }

    @Test("Bounding box spans min/max over negative and positive coordinates")
    func boundingBox() {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: -10, y: 3))
        stream.addStitch(at: StagePoint(x: 4, y: -7))
        stream.addStitch(at: StagePoint(x: 1, y: 1))

        let box = stream.boundingBox
        #expect(box?.min == EmbroideryPoint(x: -20, y: -14))
        #expect(box?.max == EmbroideryPoint(x: 8, y: 6))
    }

    @Test("addJump flags exactly the next stitch")
    func jumpFlagsNextStitch() {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addJump()
        stream.addStitch(at: StagePoint(x: 5, y: 5))
        stream.addStitch(at: StagePoint(x: 6, y: 6))

        #expect(stream.stitches.map(\.isJump) == [false, true, false])
    }

    @Test("addColorChange counts immediately and flags exactly the next stitch")
    func colorChangeSemantics() {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addColorChange()
        #expect(stream.colorChangeCount == 1, "DSTStream increments the header count at addColorChange time")

        stream.addStitch(at: StagePoint(x: 5, y: 5), color: ThreadColor(red: 255, green: 0, blue: 0))
        stream.addStitch(at: StagePoint(x: 6, y: 6), color: ThreadColor(red: 255, green: 0, blue: 0))

        #expect(stream.stitches.map(\.isColorChange) == [false, true, false])
        #expect(stream.colorChangeCount == 1)
    }

    @Test("Stitches carry the color they were appended with")
    func stitchColor() {
        let red = ThreadColor(red: 255, green: 0, blue: 0)
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: 1, y: 1), color: red)

        #expect(stream.stitches.map(\.color) == [.black, red])
    }
}
