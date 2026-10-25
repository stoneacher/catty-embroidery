@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Testing
import UIKit

/// Variables slice 7 (brief D16), the app half: the comparison editor edits one side of an If's
/// condition with the slot editors' own number and variable operations, addressed by
/// `ParameterTarget`, and its operator with a picker — all inside the one parameter session, so
/// a whole condition edit is one undo entry (ADR-036).
@MainActor
@Suite("Comparison editing")
struct ComparisonEditingTests {
    private static let first = ParameterTarget.operand(.condition, .first)
    private static let second = ParameterTarget.operand(.condition, .second)

    private static func program(_ condition: Formula, variables: [Variable] = []) -> Program {
        Program(name: "fixture", scenes: [Scene(objects: [
            Object(variables: variables, scripts: [Script(bricks: [.ifThen(condition: condition), .stitch, .ifEnd])])
        ])])
    }

    private static let seed = program(.binary(.smallerThan, .number(1), .number(2)))

    private static func editor(_ program: Program = seed) -> EditorViewModel {
        let editor = EditorViewModel(program: program, decimalSeparator: ".")
        editor.beginParameterEdit(at: 0)
        return editor
    }

    @Test("an operator, a number and a new variable are one undo entry")
    func oneEntry() {
        let editor = Self.editor()
        editor.setComparisonOperator(.greaterOrEqual)
        _ = editor.enterNumber("5", for: Self.first)
        editor.createVariable(named: "n", for: Self.second)
        editor.endParameterEdit()

        #expect(editor.program == Self.program(.binary(.greaterOrEqual, .number(5), .variable("n")),
                                               variables: [Variable(name: "n")]))
        #expect(editor.undoStack.undoDepth == 1)
        editor.undo()
        #expect(editor.program == Self.seed)
    }

    @Test("the stepper and a chosen variable write one side only")
    func sides() {
        let condition = Formula.binary(.equal, .number(1), .number(2))
        let editor = Self.editor(Self.program(condition, variables: [Variable(name: "n")]))
        editor.stepNumber(Self.second, by: 1)
        editor.chooseVariable(named: "n", for: Self.first)
        #expect(editor.editedBrick == .ifThen(condition: .binary(.equal, .variable("n"), .number(3))))
    }

    /// The anchor names the side: a rejection returns that side alone, keeping an operator
    /// chosen during the typing run (`swift-ui-design`, slice 7).
    @Test("a rejected entry returns only its side")
    func rejectionRestoresTheSide() {
        let editor = Self.editor()
        editor.beginNumberEntry(for: Self.second)
        _ = editor.enterNumber("7", for: Self.second)
        editor.setComparisonOperator(.notEqual)
        #expect(editor.enterNumber("7e999", for: Self.second) == .nonFinite)
        #expect(editor.editedBrick == .ifThen(condition: .binary(.notEqual, .number(1), .number(2))))
    }

    @Test("switching a side back to a number restores its opening number, else the template's")
    func switchToNumber() {
        let editor = Self.editor(Self.program(.binary(.smallerThan, .variable("a"), .number(7)),
                                              variables: [Variable(name: "a")]))
        editor.chooseVariable(named: "a", for: Self.second)
        editor.switchToNumber(Self.second)
        editor.switchToNumber(Self.first)
        #expect(editor.editedBrick == .ifThen(condition: .binary(.smallerThan, .number(1), .number(7))))
    }

    @Test("a locked condition is never rewritten")
    func lockedStays() {
        let locked = Formula.binary(.logicalAnd, .constant(.true), .constant(.true))
        let editor = Self.editor(Self.program(locked))
        #expect(editor.setComparisonOperator(.equal) == nil)
        #expect(editor.enterNumber("5", for: Self.first) == nil)
        editor.stepNumber(Self.first, by: 1)
        editor.endParameterEdit()
        #expect(editor.program == Self.program(locked))
        #expect(editor.undoStack.undoDepth == 0)
    }

    // MARK: - Words

    private static let english = Locale(identifier: "en_US")

    @Test("each operator has a spoken name, never a bare symbol")
    func operatorNames() {
        let names = ComparisonOperator.allCases.map { ParameterEditorText.name(of: $0, locale: Self.english) }
        #expect(names == ["Equal to", "Not equal to", "Less than", "Less than or equal to",
                          "Greater than", "Greater than or equal to"])
    }

    /// Found on the simulator: two of the first names showed no icon in the menu.
    @Test("every operator's menu symbol exists", arguments: ComparisonOperator.allCases)
    func symbols(_ comparison: ComparisonOperator) {
        #expect(UIImage(systemName: ComparisonOperatorPicker.symbol(for: comparison)) != nil)
    }

    @Test("the sides and the picker are titled")
    func titles() {
        #expect(ParameterEditorText.title(of: ComparisonSide.first, locale: Self.english) == "First value")
        #expect(ParameterEditorText.title(of: ComparisonSide.second, locale: Self.english) == "Second value")
        #expect(ParameterEditorText.comparisonTitle(locale: Self.english) == "Comparison")
    }

    /// The lock now covers only what the comparison editor cannot show — a joined condition, or a
    /// comparison where a number belongs — so its reason says what can be edited.
    @Test("a locked condition says what can be edited")
    func lockedReason() {
        #expect(ParameterEditorText.message(for: .logic, locale: Self.english)
            == "Only a single comparison of two values in a condition can be edited. "
            + "This one can't be edited yet, so it is kept exactly as it is.")
    }
}
