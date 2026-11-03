import CatrobatImport
import Foundation
import ProgramModel
import Testing

/// Slice 4, the program around the bricks (brief D1, D3, D4, D7, D9): versions,
/// scenes, objects, scripts, declarations and the SetVariable storage rule.
struct ProgramImportTests: ProgramImportTesting {
    private typealias XML = CodeXML

    private static let move = XML.brick("MoveNStepsBrick", formulas: [("STEPS", FormulaXML.number("1"))])

    // MARK: - Program, objects, scripts

    @Test func objectsKeepTheirOrderNamesAndScripts() throws {
        let program = try imported(XML.program(name: "Demo", objects: [
            XML.object("Background", scripts: []),
            XML.object("Cat", scripts: [XML.script([Self.move]), XML.script([XML.finish()])])
        ]))
        #expect(program.name == "Demo")
        #expect(program.objects.map(\.name) == ["Background", "Cat"])
        #expect(program.objects[1].scripts.map(\.steps) == [[.brick(.moveNSteps(.number(1)))], [.finishStage]])
    }

    /// Catroid starts every look at (0, 0) facing 90 (`content/Look.java:88`),
    /// and plays objects in list order.
    @Test func theProgramStartsEveryObjectAtTheOriginFacing90() throws {
        let program = try imported(XML.program(objects: [
            XML.object("A", scripts: [XML.script([Self.move])]), XML.object("B", scripts: [])
        ])).program()
        let objects = try #require(program.scenes.first).objects
        #expect(program.scenes.count == 1)
        #expect(objects.map(\.startHeading) == [90, 90])
        #expect(objects.map(\.startX) == [0, 0])
        #expect(objects.map(\.startY) == [0, 0])
        #expect(objects.map(\.zIndex) == [0, 1])
        #expect(objects[0].scripts == [Script(header: .whenStarted, bricks: [.moveNSteps(.number(1))])])
    }

    /// `program()` serves the later app import, where harness bricks have no
    /// place: they are refused there, never dropped silently.
    @Test func programRefusesHarnessSteps() throws {
        let imported = try imported(XML.run([Self.move, XML.finish()]))
        #expect(throws: CatrobatImportError(blockers: [.harnessStep])) { _ = try imported.program() }
    }

    @Test func aCommentedOutScriptIsSkipped() throws {
        let program = try imported(XML.program(objects: [XML.object(scripts: [
            XML.script(commentedOut: true, [XML.brick("BroadcastBrick")]), XML.script([XML.finish()])
        ])]))
        #expect(program.objects[0].scripts.map(\.steps) == [[.finishStage]])
    }

    /// An EmptyScript has no trigger, so its bricks never run, and their formulas
    /// are never read. The corpus's only one is also commented out, so this
    /// synthetic one is what pins the rule (brief D9).
    @Test func anEmptyScriptIsSkippedEvenWhenNotCommentedOut() throws {
        let failing = XML.brick("AssertEqualsBrick", formulas: [
            ("ASSERT_EQUALS_ACTUAL", FormulaXML.string("was executed")),
            ("ASSERT_EQUALS_EXPECTED", FormulaXML.string("should not be"))
        ])
        let program = try imported(XML.program(objects: [XML.object(scripts: [
            XML.script("EmptyScript", [failing]), XML.script([XML.finish()])
        ])]))
        #expect(program.objects[0].scripts.map(\.steps) == [[.finishStage]])
    }

    @Test func anUnsupportedScriptIsNamed() {
        let xml = XML.program(objects: [XML.object(scripts: [
            XML.script("BroadcastScript", [Self.move]), XML.script("WhenScript", [Self.move])
        ])])
        #expect(blockers(xml) == [.script("BroadcastScript"), .script("WhenScript")])
    }

    /// Every blocker in the program is collected, across objects, scripts and formulas.
    @Test func everyBlockerInTheProgramIsCollected() {
        let xml = XML.program(version: "0.5", objects: [
            XML.object("A", scripts: [XML.script([XML.brick("ShowBrick")])]),
            XML.object("B", scripts: [XML.script("WhenScript", []), XML.script([
                XML.brick("MoveNStepsBrick", formulas: [("STEPS", FormulaXML.node("SENSOR", "TIMER"))])
            ])])
        ])
        #expect(blockers(xml) == [.version("0.5"), .brick("ShowBrick"), .script("WhenScript"), .sensor("TIMER")])
    }

    // MARK: - Versions and scenes (D1)

    @Test(arguments: ["0.99995", "0.999999999", "1.03", "1.12", "1.13", "1.14"])
    func aVersionInsideTheWindowIsAccepted(version: String) throws {
        _ = try imported(XML.program(version: version, objects: [XML.object(scripts: [])]))
        #expect(CatrobatImport.supportedVersions == 0.99995 ... 1.14)
    }

    @Test(arguments: ["0.9999", "0.99994", "1.15", "2", "", "one"])
    func aVersionOutsideTheWindowIsRefused(version: String) {
        #expect(blockers(XML.program(version: version, objects: [XML.object(scripts: [])])) == [.version(version)])
    }

    @Test func moreThanOneSceneIsRefused() {
        #expect(blockers(XML.program(objects: [XML.object(scripts: [])], scenes: 2)) == [.multipleScenes])
    }

    @Test func malformedDocumentsAreRefused() {
        #expect(blockers("<program>") == [.malformed])
        #expect(blockers("<notAProgram/>") == [.malformed])
        #expect(blockers(XML.program(objects: [], scenes: 0)) == [.malformed])
    }

    /// Multiplayer variables have no counterpart in `Program`; the corpus never
    /// declares one, so a non-empty list is refused rather than guessed at.
    @Test func multiplayerVariablesAreRefused() {
        let declared = "<programMultiplayerVariableList>\(XML.variable("m"))</programMultiplayerVariableList>"
        let xml = XML.program(objects: [XML.object(scripts: [])])
            .replacingOccurrences(of: "<programMultiplayerVariableList/>", with: declared)
        #expect(blockers(xml) == [.element("programMultiplayerVariableList")])
    }

    // MARK: - Declarations (D7)

    @Test func declarationsKeepTheirScope() throws {
        let program = try imported(XML.program(
            variables: [XML.variable("p")],
            objects: [XML.object(variables: [XML.variable("o")], scripts: [])]
        ))
        #expect(program.variables == [Variable(name: "p")])
        #expect(program.objects[0].variables == [Variable(name: "o")])
    }

    /// A declaration may reference the variable's first use, and that use may sit
    /// in a commented-out brick: references resolve over the whole tree before
    /// anything is skipped (`brick/testDisabledBrickInLoopRegression`, Codex brief
    /// review finding 5).
    @Test func aDeclarationMayReferenceACommentedOutBrick() throws {
        let hidden = XML.brick("ChangeVariableBrick", commentedOut: true,
                               formulas: [("VARIABLE_CHANGE", FormulaXML.number("1"))],
                               variable: XML.variable("Counter"))
        let path = "../../scenes/scene/objectList/object/scriptList/script/brickList/brick/userVariable"
        let program = try imported(XML.run([hidden, XML.finish()], variables: [XML.reference(path)]))
        #expect(program.variables == [Variable(name: "Counter")])
        #expect(program.objects[0].scripts[0].steps == [.finishStage])
    }

    /// The text form, `<userVariable>Counter</userVariable>`, names the variable directly.
    @Test func aTextFormVariableIsItsName() throws {
        let set = XML.brick("SetVariableBrick", formulas: [("VARIABLE", FormulaXML.number("1"))],
                            variable: "<userVariable>Counter</userVariable>")
        #expect(try steps(XML.run([set])) == [.brick(.setVariable(name: "Counter", to: .number(1)))])
    }

    /// A brick's variable may be a reference to an earlier use, as Catroid writes
    /// every use after the first. (A reference forward, into the declaration list
    /// that follows the scenes, is one XStream rejects; slice 2.)
    @Test func aBricksVariableMayBeAReference() throws {
        let first = XML.brick("SetVariableBrick", formulas: [("VARIABLE", FormulaXML.number("1"))],
                              variable: XML.variable("p"))
        let second = XML.brick("ChangeVariableBrick", formulas: [("VARIABLE_CHANGE", FormulaXML.number("2"))],
                               variable: XML.reference("../../brick/userVariable"))
        #expect(try steps(XML.run([first, second])) == [
            .brick(.setVariable(name: "p", to: .number(1))), .brick(.changeVariableBy(name: "p", value: .number(2)))
        ])
    }

    /// Catroid binds a variable's identity, we bind its name; they differ only
    /// when an object and the project declare the same name, so that is refused.
    @Test func aNameDeclaredByAnObjectAndTheProjectIsRefused() {
        let xml = XML.program(variables: [XML.variable("x"), XML.variable("y")],
                              objects: [XML.object(variables: [XML.variable("x")], scripts: [])])
        #expect(blockers(xml) == [.variableShadowing("x")])
    }

    /// Catroid binds a brick's variable by identity, but a formula reads a
    /// variable by name, and the first declaration with that name wins
    /// (`UserDataWrapper.java:40`, `Project.java:247`). Two declarations a name
    /// cannot tell apart are refused, in one list as across lists (Codex slice 4,
    /// finding 1).
    @Test func twoVariablesANameCannotTellApartAreRefused() {
        let twiceInProject = XML.program(variables: [XML.variable("x"), XML.variable("x")],
                                         objects: [XML.object(scripts: [])])
        #expect(blockers(twiceInProject) == [.variableShadowing("x")])
        let twice = [XML.variable("y"), XML.variable("y")]
        let twiceInObject = XML.program(objects: [XML.object(variables: twice, scripts: [])])
        #expect(blockers(twiceInObject) == [.variableShadowing("y")])
    }

    /// Two objects may each declare `x`: those are separate scopes.
    @Test func theSameNameInTwoObjectsIsFine() throws {
        _ = try imported(XML.program(objects: [
            XML.object("A", variables: [XML.variable("x")], scripts: []),
            XML.object("B", variables: [XML.variable("x")], scripts: [])
        ]))
    }

    /// A brick whose variable no declaration visible to its object holds writes a
    /// `UserVariable` no name lookup reaches in Catroid; ours would declare it on
    /// use, so it is refused.
    @Test func aBricksUndeclaredVariableIsRefused() {
        let one = [("VARIABLE", FormulaXML.number("1"))]
        let set = XML.brick("SetVariableBrick", formulas: one, variable: XML.variable("u"))
        let alone = XML.program(objects: [XML.object(scripts: [XML.script([set])])])
        #expect(blockers(alone) == [.undeclaredVariable("u")])
        // A declared name, but another variable: the brick's own inline `x` is not
        // the object's `x`, so Catroid's write and read would miss each other.
        let ownX = XML.brick("SetVariableBrick", formulas: one, variable: XML.variable("x"))
        let declaredX = XML.object(variables: [XML.variable("x")], scripts: [XML.script([ownX])])
        #expect(blockers(XML.program(objects: [declaredX]))
            == [.undeclaredVariable("x")])
        // Declared by another object, which precedes it: resolvable, not visible here.
        let other = XML.object("Other", variables: [XML.variable("u")], scripts: [])
        let setOther = XML.brick("SetVariableBrick", formulas: [("VARIABLE", FormulaXML.number("1"))],
                                 variable: XML.reference("../../../../../../object/userVariables/userVariable"))
        #expect(blockers(XML.program(objects: [other, XML.object(scripts: [XML.script([setOther])])]))
            == [.undeclaredVariable("u")])
    }

    /// Catroid's XStream reads `commentedOut` with its Boolean converter, which
    /// ignores case (Codex slice 4, finding 3).
    @Test func commentedOutIgnoresCase() throws {
        let hidden = XML.brick("BroadcastBrick")
            .replacingOccurrences(of: "<commentedOut>false", with: "<commentedOut>TRUE")
        let script = XML.script([hidden, XML.finish()])
        let hiddenScript = XML.script("WhenScript", [Self.move])
            .replacingOccurrences(of: "<commentedOut>false", with: "<commentedOut>True")
        let program = try imported(XML.program(objects: [XML.object(scripts: [script, hiddenScript])]))
        #expect(program.objects[0].scripts.map(\.steps) == [[.finishStage]])
    }

    // MARK: - What a SetVariable stores (D4, Codex slice 3 review)

    private static func set(_ name: String, _ value: String) -> String {
        XML.brick("SetVariableBrick", formulas: [("VARIABLE", value)], variable: XML.variable(name))
    }

    private static func change(_ name: String, commentedOut: Bool = false) -> String {
        XML.brick("ChangeVariableBrick", commentedOut: commentedOut,
                  formulas: [("VARIABLE_CHANGE", FormulaXML.number("1"))], variable: XML.variable(name))
    }

    private static func loop(over name: String) -> String {
        XML.brick("ForVariableFromToBrick", formulas: [("FOR_LOOP_FROM", FormulaXML.number("1")),
                                                       ("FOR_LOOP_TO", FormulaXML.number("2"))],
                  variable: XML.variable(name), lists: [("loopBricks", [])])
    }

    private static let comparison = FormulaXML.op("EQUAL", FormulaXML.number("1"), FormulaXML.number("1"))

    /// ChangeVariable skips a variable that is not a `Double` in Catroid
    /// (`ChangeVariableAction.kt:41`) and ForVariableFromTo exits on one
    /// (`ForVariableFromToAction.java:60`), so a variable stored as a Boolean or a
    /// string and then changed or looped over is refused, by name.
    /// The storage rule follows identity: object A's `x` stored as a Boolean says
    /// nothing about object B's `x` (Codex slice 4, finding 2).
    @Test func theStorageRuleKeepsObjectsApart() throws {
        _ = try imported(XML.declaringUses(XML.program(objects: [
            XML.object("A", scripts: [XML.script([Self.set("x", Self.comparison)])]),
            XML.object("B", scripts: [XML.script([Self.change("x")])])
        ])))
    }

    @Test func aVariableStoredAsBooleanOrStringAndChangedIsRefused() {
        #expect(blockers(XML.run([Self.set("b", Self.comparison), Self.change("b")])) == [.variableStorage("b")])
        #expect(blockers(XML.run([Self.set("s", FormulaXML.string("2")), Self.loop(over: "s")])) ==
            [.variableStorage("s")])
        #expect(blockers(XML.run([Self.set("t", FormulaXML.function("TRUE")), Self.loop(over: "t")]))
            == [.variableStorage("t")])
    }

    /// A copy of a Boolean is a Boolean (`isBoolean` on a USER_VARIABLE root reads
    /// the variable's value); a copy of a numeric string is converted to a Double.
    @Test func aCopyCarriesBooleanButNotString() throws {
        let copyB = Self.set("c", FormulaXML.node("USER_VARIABLE", "b"))
        #expect(blockers(XML.run([Self.set("b", Self.comparison), copyB, Self.change("c")])) == [.variableStorage("c")])
        let copyS = Self.set("d", FormulaXML.node("USER_VARIABLE", "s"))
        _ = try imported(XML.run([Self.set("s", FormulaXML.string("2")), copyS, Self.change("d")]))
    }

    /// Only reading such a variable is fine: every read normalises it back.
    @Test func aVariableStoredAsBooleanAndOnlyReadImports() throws {
        let read = XML.brick("MoveNStepsBrick", formulas: [("STEPS", FormulaXML.node("USER_VARIABLE", "b"))])
        let result = try steps(XML.run([Self.set("b", Self.comparison), read, Self.set("n", FormulaXML.number("1")),
                                        Self.change("n")]))
        #expect(result.count == 4)
    }

    /// Skipped bricks change nothing, so they do not count.
    @Test func aCommentedOutChangeDoesNotCount() throws {
        _ = try imported(XML.run([Self.set("b", Self.comparison), Self.change("b", commentedOut: true)]))
    }
}
