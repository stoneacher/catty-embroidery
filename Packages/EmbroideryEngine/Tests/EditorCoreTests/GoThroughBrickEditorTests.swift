import EditorCore
import ProgramModel
import Testing

/// Brick backend slice 5: GoThrough in the editor vocabulary (brief D10).
@Suite("GoThrough in the editor")
struct GoThroughBrickEditorTests {
    private let curve = Brick.goThrough(throughX: .number(1), throughY: .number(2), x: .number(3), y: .number(4))

    @Test("a GoThrough has its own kind and follows Arc in the palette")
    func kindAndPalette() {
        #expect(BrickKind(of: curve) == .goThrough)
        #expect(PaletteGroup.motion.kinds.suffix(3) == [.pointInDirection, .arc, .goThrough])
    }

    /// `GoThroughBrick(0, 0, 0, 0)` (`CategoryBricksFactory.kt:1092`); Catroid
    /// has no `BrickValues` entry for it.
    @Test("the template is Catroid's: all four fields 0")
    func template() {
        #expect(BrickDefaults.goThroughThroughX == 0 && BrickDefaults.goThroughThroughY == 0)
        #expect(BrickDefaults.goThroughX == 0 && BrickDefaults.goThroughY == 0)
        #expect(BrickKind.goThrough.template() == [
            .goThrough(throughX: .number(0), throughY: .number(0), x: .number(0), y: .number(0))
        ])
    }

    @Test("parameters read through-point then destination")
    func parameters() {
        #expect(curve.parameters.map(\.slot) == [.throughX, .throughY, .x, .y])
    }

    /// One field at a time, each to its own slot: a field writing a neighbour's
    /// slot passes every other GoThrough test (Codex brief review, finding 7).
    @Test("each slot writes its own field", arguments: [
        (ParameterSlot.throughX, Brick.goThrough(
            throughX: .number(9), throughY: .number(2), x: .number(3), y: .number(4)
        )),
        (.throughY, .goThrough(throughX: .number(1), throughY: .number(9), x: .number(3), y: .number(4))),
        (.x, .goThrough(throughX: .number(1), throughY: .number(2), x: .number(9), y: .number(4))),
        (.y, .goThrough(throughX: .number(1), throughY: .number(2), x: .number(3), y: .number(9)))
    ])
    func replacingRoutesEachSlot(_ slot: ParameterSlot, _ expected: Brick) {
        #expect(curve.replacing(slot, with: .formula(.number(9))) == expected)
    }
}
