import Foundation
import ProgramModel
import Testing

@Suite("Program model value types")
struct ProgramModelTests {
    /// A nested program exercising every US-201 type: project-scoped variables on
    /// `Program` (Catroid `Project.userVariables`), object-scoped variables on
    /// `Object` (Catroid `Sprite.userVariables`) — the two collections US-202's
    /// shadowing rule needs.
    private func makeProgram() -> Program {
        Program(
            name: "Stitchy",
            scenes: [
                Scene(
                    name: "Scene 1",
                    objects: [
                        Object(
                            name: "Needle",
                            startX: 12.5,
                            startY: -40,
                            startHeading: 90,
                            zIndex: 1,
                            variables: [Variable(name: "speed", value: 3)]
                        ),
                        Object(
                            name: "Background",
                            variables: [Variable(name: "speed", value: 7), Variable(name: "count")]
                        )
                    ]
                )
            ],
            variables: [Variable(name: "speed", value: 1), Variable(name: "size", value: 250)]
        )
    }

    @Test("Codable round-trip preserves the whole program value")
    func codableRoundTrip() throws {
        let original = makeProgram()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Program.self, from: data)
        // ADR-006 discipline: assert the entire resulting value, not just touched fields.
        #expect(decoded == original)
    }

    @Test("independently constructed identical programs compare equal")
    func wholeValueEquality() {
        #expect(makeProgram() == makeProgram())
    }

    @Test("a one-field difference makes programs unequal")
    func oneFieldDifferenceIsUnequal() {
        var changed = makeProgram()
        changed.scenes[0].objects[0].zIndex = 2
        #expect(changed != makeProgram())
    }

    @Test("Program carries the current format version by default")
    func formatVersionDefault() {
        // ADR-003: versioned own format.
        #expect(Program().formatVersion == Program.currentFormatVersion)
    }

    @Test("a default-initialized Object sits at the center origin facing up")
    func objectDefaults() {
        let object = Object()
        // ADR-007: center origin, 0° = up.
        #expect(object.startX == 0)
        #expect(object.startY == 0)
        #expect(object.startHeading == 0)
        #expect(object.zIndex == 0)
        #expect(object.variables.isEmpty)
    }

    @Test("a Variable defaults to value 0")
    func variableDefaultValue() {
        #expect(Variable(name: "x").value == 0)
    }
}
