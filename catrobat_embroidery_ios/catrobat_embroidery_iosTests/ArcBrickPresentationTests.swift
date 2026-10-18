@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Testing

/// Brick backend slice 4, the app half: Arc reads as a sentence, offers itself in
/// the palette, and its direction is one undoable choice.
///
/// Wording is Catroid's (`arc_direction` "Go in arc", `arc_with_radius`
/// "with radius", `arc_for_degrees` "for"), as **whole sentences per direction**
/// rather than "left" spliced into one: a language may inflect or reorder the
/// side. The degree sign avoids a plural form.
@MainActor
@Suite("Arc in the app")
struct ArcBrickPresentationTests {
    private static let english = Locale(identifier: "en_US")

    private static func text(_ brick: Brick) -> String {
        BrickRowPresentation.text(of: brick, locale: english)
    }

    @Test("an arc reads as one sentence per direction")
    func sentences() {
        #expect(Self.text(.arc(direction: .left, radius: .number(10), degrees: .number(360)))
            == "Go in arc left with radius 10 for 360°")
        #expect(Self.text(.arc(direction: .right, radius: .variable("r"), degrees: .number(-45)))
            == "Go in arc right with radius \"r\" for \u{2212}45°")
    }

    /// The two sentences must stay distinct: a swapped or shared key would read
    /// "left" for a right arc.
    @Test("left and right never read alike")
    func directionsDiffer() {
        let left = Self.text(.arc(direction: .left, radius: .number(1), degrees: .number(1)))
        let right = Self.text(.arc(direction: .right, radius: .number(1), degrees: .number(1)))
        #expect(left != right)
        #expect(left.contains("left") && right.contains("right"))
    }

    @Test("the palette offers Arc after Point in direction, with its description")
    func palette() {
        let row = PaletteRowPresentation(kind: .arc, locale: Self.english)
        #expect(row.text == "Go in arc left with radius 10 for 360°")
        #expect(row.description == "Moves the needle along a circle, turning left or right.")
        // Adjacency, not position: GoThrough follows Arc (slice 5), so "last" would not hold.
        let kinds = PaletteGroup.motion.kinds
        let arc = kinds.firstIndex(of: .arc)
        #expect(arc.map { kinds[kinds.index(before: $0)] } == .pointInDirection)
    }

    @Test("the direction and radius slots have titles, and the directions names")
    func slotTitles() {
        #expect(ParameterEditorText.title(of: .direction, locale: Self.english) == "Direction")
        #expect(ParameterEditorText.title(of: .radius, locale: Self.english) == "Radius")
        #expect(ParameterEditorText.name(of: ArcDirection.left, locale: Self.english) == "Left")
        #expect(ParameterEditorText.name(of: ArcDirection.right, locale: Self.english) == "Right")
    }

    /// One discrete edit through the parameter session, like a thread swatch:
    /// the whole program changes, and one undo puts the left arc back.
    @Test("choosing a direction is one undoable edit")
    func directionEdit() {
        let arc = Brick.arc(direction: .left, radius: .number(10), degrees: .number(360))
        let program = Program(name: "fixture", scenes: [Scene(objects: [Object(scripts: [
            Script(bricks: [arc, .stitch])
        ])])])
        let editor = EditorViewModel(program: program, decimalSeparator: ".")
        editor.beginParameterEdit(at: 0)
        editor.setParameter(.direction, to: .arcDirection(.right))
        #expect(editor.program.scenes[0].objects[0].scripts[0].bricks
            == [.arc(direction: .right, radius: .number(10), degrees: .number(360)), .stitch])
        editor.endParameterEdit()
        #expect(editor.undo())
        #expect(editor.program == program)
        #expect(!editor.canUndo)
    }
}
