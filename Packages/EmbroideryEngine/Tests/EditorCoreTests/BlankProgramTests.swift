import EditorCore
import ProgramModel
import Testing

/// US-405 test-plan item 8: the program M4 builds from nothing.
///
/// Whole-value first (ADR-006 pattern 3), then the parts the story names one by one, so a
/// failure says *which* part is wrong rather than only that two trees differ.
@Suite("Program.blank")
struct BlankProgramTests {
    @Test("one scene, one object, one empty whenStarted script — as a whole value")
    func theBlankProgramIsExactlyThisValue() {
        let expected = Program(
            name: "",
            scenes: [Scene(name: "Scene 1", objects: [
                Object(name: "Needle", startHeading: 90, scripts: [Script(header: .whenStarted)])
            ])]
        )
        #expect(Program.blank == expected)
    }

    @Test("exactly one scene, one object and one script, with no bricks")
    func theBlankProgramHasOneOfEachAndNoBricks() throws {
        let blank = Program.blank
        try #require(blank.scenes.count == 1)
        try #require(blank.scenes[0].objects.count == 1)
        let object = blank.scenes[0].objects[0]
        try #require(object.scripts.count == 1)

        #expect(object.scripts[0].header == .whenStarted)
        #expect(object.scripts[0].bricks.isEmpty)
        #expect(blank.variables.isEmpty)
        #expect(object.variables.isEmpty)
    }

    /// Catroid's default heading, and the one the Rosette sample uses: 90° is "right" under
    /// ADR-007's 0° = up, so the first `moveNSteps` a user adds draws a line they can see
    /// going somewhere. 0 would be an easy value to leave in by accident — `Object`'s own
    /// default — which is why it is pinned by itself.
    @Test("the needle starts at the origin facing right")
    func theNeedleStartsAtTheOriginFacingRight() throws {
        let object = try #require(Program.blank.scenes.first?.objects.first)
        #expect(object.startHeading == 90)
        #expect(object.startX == 0)
        #expect(object.startY == 0)
    }

    @Test("the blank script passes validation")
    func theBlankScriptValidates() throws {
        let script = try #require(Program.blank.scenes.first?.objects.first?.scripts.first)
        #expect(throws: Never.self) { try script.validate() }
    }

    /// The program's name is empty rather than an English word: it is persisted (US-406), so
    /// a literal here would reach disk and never be localised. The scene and object names are
    /// *not* held to that — they are Catroid's defaults and what both shipping samples store,
    /// and no M4 surface shows them.
    @Test("the blank program carries no stored name")
    func theBlankProgramHasNoStoredName() {
        #expect(Program.blank.name.isEmpty)
        #expect(Program.blank.formatVersion == Program.currentFormatVersion)
    }
}
