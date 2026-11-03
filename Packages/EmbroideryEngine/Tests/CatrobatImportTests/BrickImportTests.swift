import CatrobatImport
import EditorCore
import Foundation
import ProgramModel
import Testing

/// Slice 4, bricks (brief D3, D7, D8, D9, ADR-008): each supported Catroid brick
/// becomes its `Brick` case, the harness bricks become harness steps, and nested
/// brick lists flatten into ADR-008's paired lists.
struct BrickImportTests: ProgramImportTesting {
    private typealias XML = CodeXML

    private static let one = FormulaXML.number("1")
    private static let two = FormulaXML.number("2")
    private static let three = FormulaXML.number("3")
    private static let four = FormulaXML.number("4")

    /// Every supported brick, with each formula in its own category, so a swapped
    /// category or field turns its row red.
    static let mappings: [(String, Brick)] = [
        (XML.brick("MoveNStepsBrick", formulas: [("STEPS", one)]), .moveNSteps(.number(1))),
        (XML.brick("TurnLeftBrick", formulas: [("TURN_LEFT_DEGREES", one)]), .turnLeft(.number(1))),
        (XML.brick("TurnRightBrick", formulas: [("TURN_RIGHT_DEGREES", one)]), .turnRight(.number(1))),
        (XML.brick("PointInDirectionBrick", formulas: [("DEGREES", one)]), .pointInDirection(.number(1))),
        (
            XML.brick("PlaceAtBrick", formulas: [("Y_POSITION", two), ("X_POSITION", one)]),
            .placeAt(x: .number(1), y: .number(2))
        ),
        (XML.brick("SetXBrick", formulas: [("X_POSITION", one)]), .setX(.number(1))),
        (XML.brick("SetYBrick", formulas: [("Y_POSITION", one)]), .setY(.number(1))),
        (XML.brick("ChangeXByNBrick", formulas: [("X_POSITION_CHANGE", one)]), .changeXBy(.number(1))),
        (XML.brick("ChangeYByNBrick", formulas: [("Y_POSITION_CHANGE", one)]), .changeYBy(.number(1))),
        (
            XML.brick("ArcBrick", formulas: [("SIZE", one), ("DEGREES", two)], extra: "<direction>RIGHT</direction>"),
            .arc(direction: .right, radius: .number(1), degrees: .number(2))
        ),
        (
            XML.brick("ArcBrick", formulas: [("SIZE", one), ("DEGREES", two)], extra: "<direction>LEFT</direction>"),
            .arc(direction: .left, radius: .number(1), degrees: .number(2))
        ),
        (
            XML.brick("GoThroughBrick", formulas: [
                ("X_DESTINATION", three), ("Y_DESTINATION", four), ("X_POSITION", one), ("Y_POSITION", two)
            ]),
            .goThrough(throughX: .number(1), throughY: .number(2), x: .number(3), y: .number(4))
        ),
        (XML.brick("WaitBrick", formulas: [("TIME_TO_WAIT_IN_SECONDS", one)]), .wait(seconds: .number(1))),
        (XML.brick("WaitUntilBrick", formulas: [("IF_CONDITION", one)]), .waitUntil(condition: .number(1))),
        (
            XML.brick("SetVariableBrick", formulas: [("VARIABLE", one)], variable: XML.variable("v")),
            .setVariable(name: "v", to: .number(1))
        ),
        (
            XML.brick("ChangeVariableBrick", formulas: [("VARIABLE_CHANGE", one)], variable: XML.variable("v")),
            .changeVariableBy(name: "v", value: .number(1))
        ),
        (XML.brick("StitchBrick"), .stitch),
        (XML.brick("SewUpBrick"), .sewUp),
        (XML.brick("StopRunningStitchBrick"), .stopRunningStitch),
        (XML.brick("RunningStitchBrick", formulas: [("EMBROIDERY_LENGTH", one)]), .runningStitch(length: .number(1))),
        (XML.brick("TripleStitchBrick", formulas: [("EMBROIDERY_LENGTH", one)]), .tripleStitch(length: .number(1))),
        (
            XML.brick("ZigZagStitchBrick", formulas: [
                ("ZIGZAG_EMBROIDERY_WIDTH", two), ("ZIGZAG_EMBROIDERY_LENGTH", one)
            ]),
            .zigZagStitch(length: .number(1), width: .number(2))
        ),
        (
            XML.brick("SetThreadColorBrick", formulas: [("THREAD_COLOR", FormulaXML.string("#ff0000"))]),
            .setThreadColor(hex: "#ff0000")
        ),
        (
            XML.brick("WriteEmbroideryToFileBrick", formulas: [("WRITE_FILENAME", FormulaXML.string("design"))]),
            .writeEmbroideryToFile(name: "design")
        )
    ]

    @Test(arguments: mappings)
    func supportedBrickMapsToItsCase(xml: String, expected: Brick) throws {
        #expect(try steps(XML.run([xml])) == [.brick(expected)])
    }

    /// Every `Brick` case a Catroid brick produces appears above or among the
    /// structural cases, so a case added to `ProgramModel` must be placed here.
    @Test func censusEveryBrickKindIsReachable() {
        let mapped = Set(Self.mappings.map { BrickKind(of: $0.1) })
        let structural: Set<BrickKind> = [
            .repeatLoop, .forever, .repeatUntil, .forVariableFromTo, .loopEnd, .ifThen, .ifElse, .elseBranch, .ifEnd
        ]
        #expect(mapped.union(structural) == Set(BrickKind.allCases))
    }

    /// A string-taking brick reads its formula as text, so only a literal fits
    /// the `String` payload; anything else is refused.
    @Test func stringParametersMustBeLiterals() {
        let sum = FormulaXML.op("PLUS", FormulaXML.number("1"), FormulaXML.number("2"))
        #expect(blockers(XML.run([XML.brick("SetThreadColorBrick", formulas: [("THREAD_COLOR", sum)])]))
            == [.stringValue(.text)])
        #expect(blockers(XML.run([XML.brick("WriteEmbroideryToFileBrick", formulas: [("WRITE_FILENAME", sum)])]))
            == [.stringValue(.text)])
    }

    /// Catroid fails to load a formula whose category is no `BrickField`
    /// (`XStreamConcurrentFormulaHashMapConverter.java:75`); a category the brick
    /// does not read is refused too (Codex slice 4, finding 4).
    @Test func aFormulaCategoryTheBrickDoesNotReadIsRefused() {
        let extra = XML.brick("MoveNStepsBrick", formulas: [("STEPS", Self.one), ("NOT_A_BRICK_FIELD", Self.two)])
        #expect(blockers(XML.run([extra])) == [.brickShape("MoveNStepsBrick")])
        let onStitch = XML.brick("StitchBrick", formulas: [("STEPS", Self.one)])
        #expect(blockers(XML.run([onStitch])) == [.brickShape("StitchBrick")])
    }

    /// A child the brick has no use for is a shape error, never dropped: a nested
    /// list only some bricks read would otherwise lose its bricks silently
    /// (review, slice 4).
    @Test func aChildTheBrickDoesNotReadIsRefused() {
        let move = XML.brick("MoveNStepsBrick", formulas: [("STEPS", Self.one)])
        let ifThen = XML.brick("IfThenLogicBeginBrick", formulas: [("IF_CONDITION", Self.one)],
                               lists: [("ifBranchBricks", []), ("elseBranchBricks", [move])])
        #expect(blockers(XML.run([ifThen])) == [.brickShape("IfThenLogicBeginBrick")])
        let leafWithList = XML.brick("MoveNStepsBrick", formulas: [("STEPS", Self.one)],
                                     lists: [("loopBricks", [move])])
        #expect(blockers(XML.run([leafWithList])) == [.brickShape("MoveNStepsBrick")])
        let stray = XML.brick("FinishStageBrick", extra: "<spinnerSelection>1</spinnerSelection>")
        #expect(blockers(XML.run([stray])) == [.brickShape("FinishStageBrick")])
    }

    /// An unresolved reference is the cause; the brick's shape is not reported on top.
    @Test func anUnresolvedVariableIsReportedOnce() {
        let nowhere = XML.reference("../nowhere")
        let set = XML.brick("SetVariableBrick", formulas: [("VARIABLE", Self.one)], variable: nowhere)
        #expect(blockers(XML.run([set])) == [.unresolvedReference("../nowhere")])
    }

    /// A `formulaList` child that is not a `<formula>` becomes `Formula(0)` in
    /// Catroid and, inserted with `putIfAbsent`, wins over a later real entry of the
    /// same category; one without a category is a user-defined brick's input
    /// (`XStreamConcurrentFormulaHashMapConverter.java:74-89`). Neither is written
    /// by Catroid's serialiser; both are refused (Codex handover round 1, finding 1).
    @Test func anEntryThatIsNotACategorisedFormulaIsRefused() {
        let garbage = XML.brick("MoveNStepsBrick", formulas: [("STEPS", Self.one)])
            .replacingOccurrences(of: "<formulaList>", with: "<formulaList><garbage category=\"STEPS\"/>")
        #expect(blockers(XML.run([garbage])) == [.brickShape("MoveNStepsBrick")])
        let uncategorised = XML.brick("MoveNStepsBrick", formulas: [("STEPS", Self.one)])
            .replacingOccurrences(of: "<formulaList>",
                                  with: "<formulaList><formula><type>NUMBER</type><value>2</value></formula>")
        #expect(blockers(XML.run([uncategorised])) == [.brickShape("MoveNStepsBrick")])
    }

    /// Catroid reads a text parameter with `interpretString`, which trims a numeric
    /// string's trailing zero and dot (`Formula.java:183`, `NumberFormats.kt:30-35`):
    /// one trailing `0`, then a trailing `.`, and only where its narrow pattern
    /// matches (Codex handover round 1, finding 2).
    @Test(arguments: [
        ("10.0", "10"), ("1.50", "1.5"), ("-3.0", "-3"), ("0.0", "0"), ("1.500", "1.500"), ("1.05", "1.05"),
        ("01.0", "01.0"), ("1.", "1."), ("10", "10"), ("design", "design"), ("#ff0000", "#ff0000")
    ])
    func textParametersTrimLikeInterpretString(text: String, expected: String) throws {
        let write = XML.brick("WriteEmbroideryToFileBrick", formulas: [("WRITE_FILENAME", FormulaXML.string(text))])
        #expect(try steps(XML.run([write])) == [.brick(.writeEmbroideryToFile(name: expected))])
        let color = XML.brick("SetThreadColorBrick", formulas: [("THREAD_COLOR", FormulaXML.number(text))])
        #expect(try steps(XML.run([color])) == [.brick(.setThreadColor(hex: expected))])
    }

    @Test func missingPartsAreShapeErrors() {
        #expect(blockers(XML.run([XML.brick("MoveNStepsBrick")])) == [.brickShape("MoveNStepsBrick")])
        #expect(blockers(XML.run([XML.brick("SetVariableBrick", formulas: [("VARIABLE", Self.one)])]))
            == [.brickShape("SetVariableBrick")])
        #expect(blockers(XML.run([XML.brick("ArcBrick", formulas: [("SIZE", Self.one), ("DEGREES", Self.two)])]))
            == [.brickShape("ArcBrick")])
        #expect(blockers(XML.run([XML.brick("ArcBrick", formulas: [("SIZE", Self.one), ("DEGREES", Self.two)],
                                            extra: "<direction>UP</direction>")]))
            == [.brickShape("ArcBrick")])
    }

    // MARK: - Harness steps (D3)

    @Test func harnessBricksBecomeHarnessSteps() throws {
        let assert = XML.brick("AssertEqualsBrick", formulas: [
            ("ASSERT_EQUALS_EXPECTED", Self.two), ("ASSERT_EQUALS_ACTUAL", Self.one)
        ])
        let bricks = [assert, XML.brick("WaitTillIdleBrick"), XML.finish(), XML.brick("ExitStageBrick")]
        #expect(try steps(XML.run(bricks)) == [
            .assertEquals(actual: .number(1), expected: .number(2)), .waitTillIdle, .finishStage, .exitStage
        ])
    }

    /// The assert's operands are read in the assert's own context (brief D4).
    @Test func assertOperandsAreReadAsAssertOperands() {
        let assert = XML.brick("AssertEqualsBrick", formulas: [
            ("ASSERT_EQUALS_ACTUAL", FormulaXML.string("abc")), ("ASSERT_EQUALS_EXPECTED", Self.one)
        ])
        #expect(blockers(XML.run([assert])) == [.stringValue(.assertOperand)])
    }

    /// SetVariable's value is read in its own context (brief D4): a string it would
    /// store as a string is refused. Below the root, the parent decides.
    @Test func aSetVariableValueIsReadAsAVariableValue() {
        let set = XML.brick("SetVariableBrick", formulas: [("VARIABLE", FormulaXML.string("abc"))],
                            variable: XML.variable("v"))
        #expect(blockers(XML.run([set])) == [.stringValue(.variableValue)])
    }

    /// A fully qualified tag is the same brick: its `type` attribute names it
    /// (`brick/testDisabledBrickInLoopRegression`).
    @Test func aFullyQualifiedTagIsReadByItsType() throws {
        let tag = "org.catrobat.catroid.content.bricks.FinishStageBrick"
        let xml = "<\(tag) type=\"FinishStageBrick\"><brickId>id</brickId><commentedOut>false</commentedOut></\(tag)>"
        #expect(try steps(XML.run([xml])) == [.finishStage])
    }

    // MARK: - Structure (ADR-008)

    @Test func loopsFlattenWithTheirEnd() throws {
        let move = XML.brick("MoveNStepsBrick", formulas: [("STEPS", Self.one)])
        let repeatBrick = XML.brick(
            "RepeatBrick",
            formulas: [("TIMES_TO_REPEAT", Self.two)],
            lists: [("loopBricks", [move])]
        )
        let forever = XML.brick("ForeverBrick", lists: [("loopBricks", [repeatBrick])])
        let until = XML.brick(
            "RepeatUntilBrick",
            formulas: [("REPEAT_UNTIL_CONDITION", Self.one)],
            lists: [("loopBricks", [])]
        )
        let forLoop = XML.brick(
            "ForVariableFromToBrick",
            formulas: [("FOR_LOOP_TO", Self.three), ("FOR_LOOP_FROM", Self.one)],
            variable: XML.variable("i"),
            lists: [("loopBricks", [move])]
        )
        #expect(try steps(XML.run([forever, until, forLoop])) == [
            .brick(.forever), .brick(.repeatLoop(times: .number(2))), .brick(.moveNSteps(.number(1))),
            .brick(.loopEnd), .brick(.loopEnd),
            .brick(.repeatUntil(condition: .number(1))), .brick(.loopEnd),
            .brick(.forVariableFromTo(name: "i", from: .number(1), to: .number(3))),
            .brick(.moveNSteps(.number(1))), .brick(.loopEnd)
        ])
    }

    @Test func ifsFlattenWithElseInItsPlace() throws {
        let move = XML.brick("MoveNStepsBrick", formulas: [("STEPS", Self.one)])
        let turn = XML.brick("TurnLeftBrick", formulas: [("TURN_LEFT_DEGREES", Self.two)])
        let ifElse = XML.brick("IfLogicBeginBrick", formulas: [("IF_CONDITION", Self.one)],
                               lists: [("ifBranchBricks", [move]), ("elseBranchBricks", [turn])])
        let ifThen = XML.brick("IfThenLogicBeginBrick", formulas: [("IF_CONDITION", Self.two)],
                               lists: [("ifBranchBricks", [turn])])
        #expect(try steps(XML.run([ifElse, ifThen])) == [
            .brick(.ifElse(condition: .number(1))), .brick(.moveNSteps(.number(1))), .brick(.elseBranch),
            .brick(.turnLeft(.number(2))), .brick(.ifEnd),
            .brick(.ifThen(condition: .number(2))), .brick(.turnLeft(.number(2))), .brick(.ifEnd)
        ])
    }

    /// Catroid skips a commented-out brick and everything inside it
    /// (`content/Script.java:132`, `content/bricks/RepeatBrick.java:184`), and
    /// never interprets its formulas, so they are never imported either.
    @Test func aCommentedOutBrickIsSkippedWithItsSubtree() throws {
        let join = FormulaXML.function("JOIN", FormulaXML.string("a"), FormulaXML.string("b"))
        let move = XML.brick("MoveNStepsBrick", formulas: [("STEPS", Self.one)])
        let hidden = XML.brick("MoveNStepsBrick", commentedOut: true, formulas: [("STEPS", join)])
        let hiddenLoop = XML.brick("RepeatBrick", commentedOut: true, formulas: [("TIMES_TO_REPEAT", Self.two)],
                                   lists: [("loopBricks", [move, XML.brick("UnknownBrick")])])
        let loop = XML.brick(
            "RepeatBrick",
            formulas: [("TIMES_TO_REPEAT", Self.two)],
            lists: [("loopBricks", [hidden, move])]
        )
        #expect(try steps(XML.run([hiddenLoop, loop])) == [
            .brick(.repeatLoop(times: .number(2))), .brick(.moveNSteps(.number(1))), .brick(.loopEnd)
        ])
    }

    @Test func aNoteBrickIsDropped() throws {
        let note = XML.brick("NoteBrick", formulas: [("NOTE", FormulaXML.string("a comment"))])
        #expect(try steps(XML.run([note, XML.finish()])) == [.finishStage])
    }

    @Test func anUnsupportedBrickIsNamed() {
        #expect(blockers(XML.run([XML.brick("BroadcastBrick"), XML.brick("ShowBrick")]))
            == [.brick("BroadcastBrick"), .brick("ShowBrick")])
    }

    /// Flattening is iterative: 200 nested repeats (≈ 400 XML levels, inside the
    /// parser's cap) import without recursion, on a cooperative-pool thread.
    @Test func deepNestingFlattensWithoutRecursion() throws {
        let innermost = XML.brick("MoveNStepsBrick", formulas: [("STEPS", Self.one)])
        let nested = (0 ..< 200).reduce(innermost) { inner, _ in
            XML.brick("RepeatBrick", formulas: [("TIMES_TO_REPEAT", Self.two)], lists: [("loopBricks", [inner])])
        }
        let result = try steps(XML.run([nested]))
        #expect(result.count == 401)
        #expect(result[200] == .brick(.moveNSteps(.number(1))))
    }
}
