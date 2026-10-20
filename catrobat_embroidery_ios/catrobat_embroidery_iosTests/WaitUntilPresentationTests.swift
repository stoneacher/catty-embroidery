@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Testing

/// Variables slice 5, the app half: Wait until reads as Catroid writes it (`brick_wait_until`
/// "Wait until", `brick_wait_until_second_part` "is true") and sits between If and Repeat in the
/// palette.
@MainActor
@Suite("Wait until in the app")
struct WaitUntilPresentationTests {
    private static let english = Locale(identifier: "en_US")
    private static let condition = Formula.binary(.smallerThan, .number(1), .number(2))

    @Test("a Wait until reads as Catroid's sentence")
    func row() {
        #expect(BrickRowPresentation.text(of: .waitUntil(condition: Self.condition), locale: Self.english)
            == "Wait until 1 < 2 is true")
    }

    @Test("the palette offers Wait until after If and before Repeat, with its description")
    func palette() {
        let row = PaletteRowPresentation(kind: .waitUntil, locale: Self.english)
        #expect(row.text == "Wait until 1 < 2 is true")
        #expect(row.description == "Pauses until the condition is true.")
        let kinds = PaletteGroup.controlAndData.kinds
        let index = kinds.firstIndex(of: .waitUntil)
        #expect(index.map { kinds[kinds.index(before: $0)] } == .ifThen)
        #expect(index.map { kinds[kinds.index(after: $0)] } == .repeatLoop)
    }

    @Test("its condition has the condition slot")
    func conditionSlot() {
        #expect(Brick.waitUntil(condition: Self.condition).parameters.map(\.slot) == [.condition])
        #expect(ParameterEditorText.title(of: .condition, in: .waitUntil, locale: Self.english) == "Condition")
    }
}
