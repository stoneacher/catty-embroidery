import EditorCore
import ProgramModel
import Testing

/// US-410's sixth `EditAction`: `declareVariable(name:script:)`, the way a variable
/// comes into existence in the editor (decided by Sebastian, 2026-10-03;
/// ADR-035 amendment).
///
/// Without it the variable menu reads `Object.variables + Program.variables`
/// and nothing can ever add to either, so from the blank program a
/// variable-driven design is inexpressible (test-first item 7b). It declares at
/// **object** scope, where the runtime puts an undeclared name too
/// (`Interpreter+Step.swift`), and it owns `Variable.swift`'s "name uniqueness
/// is enforced by the editor" duty: a name already resolvable in that object —
/// declared in its own scope or the project's — is refused.
@Suite("EditorCore.apply — declareVariable")
struct EditDeclareVariableTests {
    typealias Fixtures = EditorCoreFixtures

    @Test("declaring appends a zero-valued variable to the addressed object only")
    func declares() {
        var expected = Fixtures.program
        expected.scenes[1].objects[2].variables.append(Variable(name: "Count"))
        #expect(
            EditorCore.apply(.declareVariable(name: "Count", script: Fixtures.address), to: Fixtures.program)
                == .applied(expected)
        )
    }

    @Test("a name already declared in the object is refused")
    func duplicateInObject() {
        var program = Program.blank
        program.scenes[0].objects[0].variables = [Variable(name: "Side", value: 3)]
        #expect(
            EditorCore.apply(.declareVariable(name: "Side", script: ScriptAddress()), to: program)
                == .rejected(.variableAlreadyDeclared(name: "Side"))
        )
    }

    /// Declaring an object variable over a project one would silently re-point
    /// every existing `.variable("Speed")` in this object — a shadowing the user
    /// never asked for. The menu already offers the project's.
    @Test("a name already declared in the project is refused")
    func duplicateInProject() {
        var program = Program.blank
        program.variables = [Variable(name: "Speed")]
        #expect(
            EditorCore.apply(.declareVariable(name: "Speed", script: ScriptAddress()), to: program)
                == .rejected(.variableAlreadyDeclared(name: "Speed"))
        )
    }

    /// The funnel validates; it does not trust the field to have done so.
    @Test("an invalid name is refused with the rule it broke")
    func invalidName() {
        #expect(
            EditorCore.apply(.declareVariable(name: "", script: ScriptAddress()), to: .blank)
                == .rejected(.invalidVariableName(.empty))
        )
        #expect(
            EditorCore.apply(.declareVariable(name: "a\"b", script: ScriptAddress()), to: .blank)
                == .rejected(.invalidVariableName(.quotationMark))
        )
    }

    /// Resolution reports its hop, like every other addressed case — each hop wrong on its own
    /// (review mutant D2: the script hop's guard was untested). The fixture's real script is
    /// scene 1 / object 2 / script 1, with 2 scenes, 3 objects and 2 scripts.
    @Test("an unresolvable address names the hop that failed", arguments: [
        (ScriptAddress(sceneIndex: 2, objectIndex: 2, scriptIndex: 1), AddressComponent.scene),
        (ScriptAddress(sceneIndex: 1, objectIndex: 9, scriptIndex: 1), .object),
        (ScriptAddress(sceneIndex: 1, objectIndex: 2, scriptIndex: 2), .script)
    ])
    func outOfBounds(address: ScriptAddress, component: AddressComponent) {
        #expect(
            EditorCore.apply(.declareVariable(name: "Count", script: address), to: Fixtures.program)
                == .rejected(.addressOutOfBounds(component, at: BrickAddress(brickIndex: 0, script: address)))
        )
    }

    /// A declaration touches no script, so balance holds by construction.
    @Test("no script changes")
    func touchesNoScript() {
        let result = EditorCore.apply(.declareVariable(name: "Count", script: Fixtures.address), to: Fixtures.program)
        guard case let .applied(program) = result else {
            Issue.record("expected applied, got \(result)")
            return
        }
        #expect(program.scenes.map { $0.objects.map(\.scripts) } == Fixtures.program.scenes
            .map { $0.objects.map(\.scripts) })
    }

    // MARK: 7b — the blank-program workflow, package half

    /// From the blank program: add `setVariable`, name it `Side`, add
    /// `moveNSteps`, make it use `Side`. The fails-against-an-edit-only-rule
    /// test: with five actions there is no step that makes the menu non-empty.
    @Test("item 7b: from blank, a variable is authored and referenced")
    func blankProgramWorkflow() {
        var stack = UndoStack(program: .blank)
        let script = ScriptAddress()
        stack.apply(.insert(.setVariable, at: BrickAddress(brickIndex: 0)))

        let naming = stack.beginEdit(of: BrickAddress(brickIndex: 0))
        stack.apply(.declareVariable(name: "Side", script: script), coalescing: naming)
        stack.apply(
            .replaceBrick(at: BrickAddress(brickIndex: 0), with: .setVariable(name: "Side", to: .number(1))),
            coalescing: naming
        )
        stack.endEdit(naming)

        stack.apply(.insert(.moveNSteps, at: BrickAddress(brickIndex: 1)))
        #expect(VariableMenu(program: stack.current, script: script).names == ["Side"])
        stack.apply(.replaceBrick(at: BrickAddress(brickIndex: 1), with: .moveNSteps(.variable("Side"))))

        var expected = Program.blank
        expected.scenes[0].objects[0].variables = [Variable(name: "Side")]
        expected.scenes[0].objects[0].scripts[0].bricks = [
            .setVariable(name: "Side", to: .number(1)),
            .moveNSteps(.variable("Side"))
        ]
        #expect(stack.current == expected)

        // Four entries, not five: the declaration and the rename it served are
        // one, so undoing the naming session removes both — never a name left
        // pointing at a variable that is no longer declared.
        #expect(stack.undoDepth == 4)
        stack.undo()
        stack.undo()
        stack.undo()
        var afterInsert = Program.blank
        afterInsert.scenes[0].objects[0].scripts[0].bricks = BrickKind.setVariable.template()
        #expect(stack.current == afterInsert)
    }
}
