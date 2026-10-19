import EditorCore
import ProgramModel
import Testing

/// Brick backend slice 4: Arc in the editor vocabulary (brief D10). The
/// property tests over `BrickKind.allCases` (templates, parameters, replacing,
/// round trip) cover Arc automatically once its kind exists; these pin what
/// they cannot: Catroid's defaults, slot order and the direction value.
@Suite("Arc in the editor")
struct ArcBrickEditorTests {
    private let arc = Brick.arc(direction: .left, radius: .number(10), degrees: .number(360))

    @Test("an arc has its own kind")
    func kind() {
        #expect(BrickKind(of: arc) == .arc)
        #expect(BrickKind(of: .arc(direction: .right, radius: .variable("r"), degrees: .number(1))) == .arc)
    }

    /// Catroid has no `BrickValues` entry for Arc; the palette hard-codes
    /// `ArcBrick(LEFT, 10f, 360f)` (`CategoryBricksFactory.kt:1091`).
    @Test("the template is Catroid's: left, radius 10, 360°")
    func template() {
        #expect(BrickDefaults.arcDirection == .left)
        #expect(BrickDefaults.arcRadius == 10)
        #expect(BrickDefaults.arcDegrees == 360)
        #expect(BrickKind.arc.template() == [arc])
    }

    @Test("parameters read direction, radius, degrees — the sentence's order")
    func parameters() {
        #expect(arc.parameters == [
            BrickParameter(slot: .direction, value: .arcDirection(.left)),
            BrickParameter(slot: .radius, value: .formula(.number(10))),
            BrickParameter(slot: .degrees, value: .formula(.number(360)))
        ])
    }

    @Test("each slot writes its own field")
    func replacingRoutesEachSlot() {
        #expect(arc.replacing(.direction, with: .arcDirection(.right))
            == .arc(direction: .right, radius: .number(10), degrees: .number(360)))
        #expect(arc.replacing(.radius, with: .formula(.number(25)))
            == .arc(direction: .left, radius: .number(25), degrees: .number(360)))
        #expect(arc.replacing(.degrees, with: .formula(.variable("d")))
            == .arc(direction: .left, radius: .number(10), degrees: .variable("d")))
    }

    @Test("a direction is refused by a formula slot, and a formula by the direction slot")
    func shapesAreRefused() {
        #expect(arc.replacing(.radius, with: .arcDirection(.right)) == nil)
        #expect(arc.replacing(.direction, with: .formula(.number(1))) == nil)
        #expect(Brick.moveNSteps(.number(1)).replacing(.direction, with: .arcDirection(.right)) == nil)
    }

    @Test("the direction gets its own editor")
    func directionEditor() {
        #expect(ParameterEditorKind(.arcDirection(.right)) == .arcDirection(.right))
    }
}
