import EditorCore
import ProgramModel
import Testing

/// Variables slice 7 (brief D16; ADR-040 amendment), the package half: a condition that is one
/// comparison of two plain values gets the comparison editor; anything else stays locked. The
/// editor addresses one operand of the condition (`ParameterTarget`), so the number and variable
/// controls work on a side as they work on a slot, and nothing it writes can reshape the tree.
@Suite("Comparison editor")
struct ComparisonEditorTests {
    static let counter = Formula.variable("Counter")
    static let less = Formula.binary(.smallerThan, counter, .number(10))
    static let ifLess = Brick.ifThen(condition: less)

    // MARK: - The operator picker's choices

    @Test("the six operators in Catroid's order, each mapping to its formula operator and back")
    func operators() {
        #expect(ComparisonOperator.allCases.map(\.binaryOperator)
            == [.equal, .notEqual, .smallerThan, .smallerOrEqual, .greaterThan, .greaterOrEqual])
        for comparison in ComparisonOperator.allCases {
            #expect(ComparisonOperator(comparison.binaryOperator) == comparison)
        }
        #expect(ComparisonOperator(.plus) == nil)
        #expect(ComparisonOperator(.logicalAnd) == nil)
    }

    // MARK: - Which conditions get the editor

    @Test("a comparison of two plain values in a condition slot is editable, sides in order")
    func editable() {
        let parameter = BrickParameter(slot: .condition, value: .formula(Self.less))
        #expect(ParameterEditorKind(parameter)
            == .comparison(lhs: Self.counter, relation: .smallerThan, rhs: .number(10)))
        let atLeast = Formula.binary(.greaterOrEqual, .number(2), .number(1))
        let numbers = BrickParameter(slot: .condition, value: .formula(atLeast))
        #expect(ParameterEditorKind(numbers)
            == .comparison(lhs: .number(2), relation: .greaterOrEqual, rhs: .number(1)))
    }

    @Test("anything else in a condition slot stays locked, for the reason it had", arguments: [
        Formula.binary(.logicalAnd, .binary(.equal, .number(1), .number(1)), .constant(.true)),
        .logicalNot(.binary(.equal, .number(1), .number(1))),
        .constant(.true),
        .binary(.smallerThan, .unaryMinus(.number(1)), .number(2)),
        .binary(.smallerThan, .binary(.plus, .number(1), .number(1)), .number(2)),
        .binary(.equal, .binary(.smallerThan, .number(1), .number(2)), .number(1))
    ])
    func locked(_ condition: Formula) {
        let kind = ParameterEditorKind(BrickParameter(slot: .condition, value: .formula(condition)))
        #expect(kind == .readOnlyFormula(condition, reason: .logic))
    }

    @Test("a comparison outside a condition slot stays locked; other slots keep their editor")
    func onlyConditionSlots() {
        #expect(ParameterEditorKind(BrickParameter(slot: .steps, value: .formula(Self.less)))
            == .readOnlyFormula(Self.less, reason: .logic))
        #expect(ParameterEditorKind(BrickParameter(slot: .steps, value: .formula(.number(10)))) == .number(10))
        let sum = Formula.binary(.plus, .number(1), .number(1))
        #expect(ParameterEditorKind(BrickParameter(slot: .condition, value: .formula(sum)))
            == .readOnlyFormula(sum, reason: .binary))
    }

    // MARK: - Reading and writing one side

    @Test("a target reads a slot's value or one side of its comparison")
    func reading() {
        #expect(Self.ifLess.value(at: .slot(.condition)) == .formula(Self.less))
        #expect(Self.ifLess.value(at: .operand(.condition, .first)) == .formula(Self.counter))
        #expect(Self.ifLess.value(at: .operand(.condition, .second)) == .formula(.number(10)))
        #expect(Self.ifLess.value(at: .operand(.steps, .first)) == nil)
    }

    @Test("writing one side keeps the other side and the operator", arguments: [
        Brick.ifThen(condition: less), .ifElse(condition: less),
        .repeatUntil(condition: less), .waitUntil(condition: less)
    ])
    func writeSide(_ brick: Brick) throws {
        let first = try #require(brick.replacing(.operand(.condition, .first), with: .formula(.number(3))))
        #expect(first.value(at: .slot(.condition)) == .formula(.binary(.smallerThan, .number(3), .number(10))))
        let second = try #require(brick.replacing(.operand(.condition, .second), with: .formula(.variable("n"))))
        #expect(second.value(at: .slot(.condition)) == .formula(.binary(.smallerThan, Self.counter, .variable("n"))))
        #expect(BrickKind(of: second) == BrickKind(of: brick))
    }

    @Test("a side takes only a number or a variable, and a locked tree is never rewritten")
    func refusals() {
        let sum = ParameterValue.formula(.binary(.plus, .number(1), .number(1)))
        #expect(Self.ifLess.replacing(.operand(.condition, .first), with: sum) == nil)
        #expect(Self.ifLess.replacing(.operand(.condition, .first), with: .variableName("n")) == nil)
        let conjunction = Brick.ifThen(condition: .binary(.logicalAnd, Self.less, Self.less))
        #expect(conjunction.replacing(.operand(.condition, .first), with: .formula(.number(1))) == nil)
        #expect(conjunction.replacingComparisonOperator(in: .condition, with: .equal) == nil)
        #expect(Brick.moveNSteps(.number(1)).replacing(.operand(.steps, .first), with: .formula(.number(2))) == nil)
    }

    /// The slot rule lives in one place: a comparison in a number slot is locked for the editor
    /// kind, so no target can read or write its sides either (`swift-code-reviewer`, feature
    /// review). Move's steps holding `1 < 2` stays exactly as it is.
    @Test("a comparison outside a condition slot has no sides to edit")
    func sidesOnlyInConditionSlots() {
        let move = Brick.moveNSteps(Self.less)
        #expect(move.value(at: .operand(.steps, .first)) == nil)
        #expect(move.replacing(.operand(.steps, .first), with: .formula(.number(5))) == nil)
        #expect(move.replacingComparisonOperator(in: .steps, with: .equal) == nil)
    }

    @Test("a slot target replaces as the slot does")
    func slotTarget() {
        #expect(Self.ifLess.replacing(.slot(.condition), with: .formula(.constant(.true)))
            == Self.ifLess.replacing(.condition, with: .formula(.constant(.true))))
    }

    @Test("the operator changes alone")
    func operatorChange() {
        #expect(Self.ifLess.replacingComparisonOperator(in: .condition, with: .notEqual)
            == .ifThen(condition: .binary(.notEqual, Self.counter, .number(10))))
    }
}
