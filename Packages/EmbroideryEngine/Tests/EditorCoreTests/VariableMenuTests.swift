import EditorCore
import ProgramModel
import Testing

/// US-410 test-first item 7: the variable menu lists what a formula in that
/// object can resolve, in the order the interpreter resolves it — object scope
/// first, then project scope, first match by name (`VariableScope.value(of:)`).
@Suite("Variable menu")
struct VariableMenuTests {
    /// Two objects, so a menu that read the wrong object's variables, or the
    /// first object's regardless of the address, lands on a decoy.
    private static let program = Program(
        scenes: [Scene(objects: [
            Object(name: "decoy", variables: [Variable(name: "Decoy")], scripts: [Script()]),
            Object(
                name: "needle",
                variables: [Variable(name: "Side"), Variable(name: "Count"), Variable(name: "Side")],
                scripts: [Script()]
            )
        ])],
        variables: [Variable(name: "Speed"), Variable(name: "Side"), Variable(name: "Angle"), Variable(name: "Speed")]
    )

    private static let needle = ScriptAddress(objectIndex: 1)

    @Test("item 7: object variables come first, then project ones")
    func order() {
        let menu = VariableMenu(program: Self.program, script: Self.needle)
        #expect(menu.objectVariables == ["Side", "Count"])
        #expect(menu.projectVariables == ["Speed", "Angle"])
        #expect(menu.names == ["Side", "Count", "Speed", "Angle"])
    }

    /// The shadowed project `Side` is not offered: choosing it would produce a
    /// `.variable("Side")` the interpreter resolves to the object's anyway, so
    /// listing it twice would offer a choice that does not exist.
    @Test("item 7: a shadowed name resolves to the object's and is listed once")
    func shadowing() {
        let menu = VariableMenu(program: Self.program, script: Self.needle)
        #expect(menu.names.filter { $0 == "Side" }.count == 1)
        #expect(menu.scope(of: "Side") == .object)
        #expect(menu.scope(of: "Angle") == .project)
        #expect(menu.scope(of: "Decoy") == nil)
    }

    @Test("the menu reads the addressed object, not the first one")
    func readsTheAddressedObject() {
        #expect(VariableMenu(program: Self.program, script: ScriptAddress()).objectVariables == ["Decoy"])
    }

    /// Total, like `apply`: an address that does not resolve still offers the
    /// project's variables rather than trapping.
    @Test("an unresolvable address offers the project's variables only")
    func unresolvable() {
        let menu = VariableMenu(program: Self.program, script: ScriptAddress(sceneIndex: 5, objectIndex: -1))
        #expect(menu.objectVariables == [])
        #expect(menu.projectVariables == ["Speed", "Side", "Angle"])
    }

    @Test("the blank program's menu is empty")
    func blank() {
        #expect(VariableMenu(program: .blank, script: ScriptAddress()).names == [])
    }
}
