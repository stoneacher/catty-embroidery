import EmbroideryEngine
import Testing

@Suite("Stitch domain model")
struct StitchTests {
    @Test("Defaults: black thread, no jump, no color change")
    func defaults() {
        let stitch = Stitch(position: EmbroideryPoint(x: 4, y: -2))
        #expect(stitch.color == ThreadColor.black)
        #expect(!stitch.isJump)
        #expect(!stitch.isColorChange)
    }

    @Test("Equality covers position, color, and flags")
    func equality() {
        let base = Stitch(position: EmbroideryPoint(x: 1, y: 2))
        #expect(base == Stitch(position: EmbroideryPoint(x: 1, y: 2)))
        #expect(base != Stitch(position: EmbroideryPoint(x: 1, y: 3)))
        #expect(base != Stitch(position: EmbroideryPoint(x: 1, y: 2), isJump: true))
        #expect(base != Stitch(position: EmbroideryPoint(x: 1, y: 2), isColorChange: true))
        #expect(base != Stitch(position: EmbroideryPoint(x: 1, y: 2), color: ThreadColor(red: 255, green: 0, blue: 0)))
    }

    @Test("Crosses isolation boundaries as a Sendable value")
    func sendable() async {
        let stitch = Stitch(position: EmbroideryPoint(x: 7, y: 7), isJump: true)
        let roundTripped = await Task.detached { stitch }.value
        #expect(roundTripped == stitch)
    }
}
