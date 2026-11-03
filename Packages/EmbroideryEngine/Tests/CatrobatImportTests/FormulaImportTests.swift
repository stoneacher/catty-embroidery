import CatrobatImport
import Foundation
import ProgramModel
import Testing

/// Slice 3 of the language-test runner (brief D2, D4, ADR-046/048): a Catroid
/// `FormulaElement` tree becomes a `Formula`, or names every reason it cannot.
struct FormulaImportTests: FormulaImportTesting {
    private typealias XML = FormulaXML

    // MARK: - Element types and names

    @Test func numberAndVariableLeaves() throws {
        #expect(try formula(XML.number("2.5")) == .number(2.5))
        #expect(try formula(XML.node("USER_VARIABLE", "Counter")) == .variable("Counter"))
    }

    /// Catroid's `Operators` names, pinned. The census below makes the table cover
    /// every `BinaryOperator` case, so a case added without an import mapping fails.
    static let binaryOperators: [(String, BinaryOperator)] = [
        ("PLUS", .plus), ("MINUS", .minus), ("MULT", .mult), ("DIVIDE", .divide), ("POW", .pow),
        ("EQUAL", .equal), ("NOT_EQUAL", .notEqual), ("SMALLER_THAN", .smallerThan),
        ("SMALLER_OR_EQUAL", .smallerOrEqual), ("GREATER_THAN", .greaterThan),
        ("GREATER_OR_EQUAL", .greaterOrEqual), ("LOGICAL_AND", .logicalAnd), ("LOGICAL_OR", .logicalOr)
    ]

    @Test(arguments: binaryOperators)
    func binaryOperatorKeepsItsOperandOrder(name: String, expected: BinaryOperator) throws {
        let xml = XML.op(name, XML.number("1"), XML.number("2"))
        #expect(try formula(xml) == .binary(expected, .number(1), .number(2)))
    }

    @Test func unaryMinusAndNotTakeTheRightChild() throws {
        #expect(try formula(XML.op("MINUS", nil, XML.number("3"))) == .unaryMinus(.number(3)))
        #expect(try formula(XML.op("LOGICAL_NOT", nil, XML.number("0"))) == .logicalNot(.number(0)))
    }

    /// The tree carries precedence; brackets carry nothing and pass their child through.
    @Test func structureComesFromTheTreeAndBracketsVanish() throws {
        let sum = XML.node("BRACKET", nil, right: XML.op("PLUS", XML.number("1"), XML.number("2")))
        let xml = XML.op("MULT", sum, XML.node("USER_VARIABLE", "x"))
        #expect(try formula(xml) == .binary(.mult, .binary(.plus, .number(1), .number(2)), .variable("x")))
    }

    static let unaryFunctions: [(String, UnaryFunction)] = [
        ("SIN", .sin), ("COS", .cos), ("TAN", .tan), ("ARCSIN", .arcsin), ("ARCCOS", .arccos),
        ("ARCTAN", .arctan), ("SQRT", .sqrt), ("ABS", .abs), ("ROUND", .round), ("FLOOR", .floor),
        ("CEIL", .ceil), ("LN", .ln), ("LOG", .log), ("EXP", .exp)
    ]
    static let binaryFunctions: [(String, BinaryFunction)] = [
        ("ARCTAN2", .arctan2), ("MIN", .min), ("MAX", .max), ("MOD", .mod), ("POWER", .power)
    ]
    static let constants: [(String, FormulaConstant)] = [("PI", .pi), ("TRUE", .true), ("FALSE", .false)]
    static let sensors: [(String, Sensor)] = [
        ("OBJECT_X", .objectX), ("OBJECT_Y", .objectY), ("MOTION_DIRECTION", .motionDirection)
    ]

    @Test(arguments: unaryFunctions)
    func unaryFunctionReadsTheLeftChild(name: String, expected: UnaryFunction) throws {
        #expect(try formula(XML.function(name, XML.number("4"))) == .unaryFunction(expected, .number(4)))
    }

    @Test(arguments: binaryFunctions)
    func binaryFunctionReadsLeftThenRight(name: String, expected: BinaryFunction) throws {
        let xml = XML.function(name, XML.number("4"), XML.number("5"))
        #expect(try formula(xml) == .binaryFunction(expected, .number(4), .number(5)))
    }

    /// Catroid's constants are functions that ignore their arguments
    /// (`MathFunctionProvider.java:45, 55-56`).
    @Test(arguments: constants)
    func constantsIgnoreTheirChildren(name: String, expected: FormulaConstant) throws {
        #expect(try formula(XML.function(name)) == .constant(expected))
        #expect(try formula(XML.function(name, XML.string("abc"))) == .constant(expected))
    }

    @Test(arguments: sensors)
    func sensorsMapByName(name: String, expected: Sensor) throws {
        #expect(try formula(XML.node("SENSOR", name)) == .sensor(expected))
    }

    /// Every case of every formula vocabulary has exactly one Catroid name in the
    /// tables above, so a case added to `ProgramModel` without an import mapping
    /// turns this red (brief, acceptance criterion 3).
    @Test func censusEveryVocabularyCaseHasOneCatroidName() {
        #expect(Self.binaryOperators.map(\.1).sortedDescriptions == BinaryOperator.allCases.sortedDescriptions)
        #expect(Self.unaryFunctions.map(\.1).sortedDescriptions == UnaryFunction.allCases.sortedDescriptions)
        #expect(Self.binaryFunctions.map(\.1).sortedDescriptions == BinaryFunction.allCases.sortedDescriptions)
        #expect(Self.constants.map(\.1).sortedDescriptions == FormulaConstant.allCases.sortedDescriptions)
        #expect(Self.sensors.map(\.1).sortedDescriptions == Sensor.allCases.sortedDescriptions)
    }

    // MARK: - Refusals

    @Test func unsupportedNamesAndTypesAreNamed() throws {
        #expect(try blockers(XML.function("JOIN", XML.string("a"), XML.string("b"))) == [.function("JOIN")])
        #expect(try blockers(XML.function("RAND", XML.number("1"), XML.number("2"))) == [.function("RAND")])
        #expect(try blockers(XML.node("SENSOR", "TIMER")) == [.sensor("TIMER")])
        // The ≤ 1.03 name Catroid renames on load (brief D1); refused, not renamed.
        #expect(try blockers(XML.node("SENSOR", "OBJECT_ROTATION")) == [.sensor("OBJECT_ROTATION")])
        #expect(try blockers(XML.node("USER_LIST", "list")) == [.elementType("USER_LIST")])
        #expect(try blockers(XML.node("COLLISION_FORMULA", "a")) == [.elementType("COLLISION_FORMULA")])
        // Catroid's `Operators.MOD` exists but falls through to 0; never written by the editor.
        #expect(try blockers(XML.op("MOD", XML.number("1"), XML.number("2"))) == [.operatorName("MOD")])
    }

    @Test func everyBlockerInAFormulaIsCollected() throws {
        let xml = XML.op(
            "PLUS",
            XML.function("JOIN", XML.string("a"), XML.string("b")),
            XML.node("SENSOR", "TIMER")
        )
        #expect(try blockers(xml) == [.function("JOIN"), .sensor("TIMER")])
    }

    @Test func malformedShapesAreRefused() throws {
        #expect(try blockers(XML.op("PLUS", XML.number("1"), nil)) == [.formulaShape("OPERATOR PLUS")])
        #expect(try blockers(XML.op("MINUS", nil, nil)) == [.formulaShape("OPERATOR MINUS")])
        #expect(try blockers(XML.op("LOGICAL_NOT", XML.number("1"), XML.number("2"))) ==
            [.formulaShape("OPERATOR LOGICAL_NOT")])
        #expect(try blockers(XML.node("BRACKET")) == [.formulaShape("BRACKET")])
        #expect(try blockers("<formula><value>1</value></formula>") == [.formulaShape("no type")])
        let extra = "<formula><additionalChildren><formulaElement/></additionalChildren>"
            + "<type>NUMBER</type><value>1</value></formula>"
        #expect(try blockers(extra) == [.formulaShape("additionalChildren")])
        let unknown = "<formula><middleChild/><type>NUMBER</type><value>1</value></formula>"
        #expect(try blockers(unknown) == [.formulaShape("middleChild")])
    }

    /// Catroid serialises an empty `textBlockFunctionProvider` on some FUNCTION
    /// nodes (185 times in the corpus); it holds no data and is ignored.
    @Test func anEmptyTextBlockFunctionProviderIsIgnored() throws {
        let xml = "<formula><leftChild><type>NUMBER</type><value>1</value></leftChild>"
            + "<textBlockFunctionProvider/><type>FUNCTION</type><value>SIN</value></formula>"
        #expect(try formula(xml) == .unaryFunction(.sin, .number(1)))
    }

    /// ADR-037's cap. Checked iteratively before any recursion, and counted in
    /// formula nesting with brackets included, which bounds the recursion itself:
    /// before the pre-check, 128 levels overflowed a 512 KB cooperative-pool stack
    /// in a debug build (SIGBUS, slice 3), and with the lean dispatch the headroom
    /// is ~1.9× (240 levels pass, 250 overflow). This test runs on that pool, so a
    /// frame that grows back towards 4 KB crashes it.
    @Test func depthIsCappedAt128() throws {
        func minus(_ depth: Int) -> String {
            (1 ..< depth).reduce(XML.number("1")) { inner, _ in XML.op("MINUS", nil, inner) }
        }
        #expect(try imported(minus(128)).1.isEmpty)
        #expect(try blockers(minus(129)) == [.formulaTooDeep])
        #expect(FormulaImport.maximumDepth == 128)
    }

    /// Brackets produce no `Formula` node, but they are recursion levels: a deep
    /// chain of them is refused, never overflows the stack.
    @Test func aDeepBracketChainIsRefusedNotOverflowed() throws {
        let chain = (0 ..< 200).reduce(XML.number("1")) { inner, _ in XML.node("BRACKET", nil, right: inner) }
        #expect(try blockers(chain) == [.formulaTooDeep])
        let shallow = (0 ..< 126).reduce(XML.number("1")) { inner, _ in XML.node("BRACKET", nil, right: inner) }
        #expect(try formula(shallow) == .number(1))
    }
}

private extension Sequence {
    var sortedDescriptions: [String] {
        map { "\($0)" }.sorted()
    }
}
