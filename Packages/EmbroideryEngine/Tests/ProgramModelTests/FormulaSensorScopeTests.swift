import ProgramModel
import Testing

/// Brick backend slice 3: outside the interpreter there is no needle, so the
/// model's own scope answers a sensor with 0, Catroid's value for unknown data.
@Suite("Formula sensors without a needle")
struct FormulaSensorScopeTests {
    @Test("VariableScope reads every sensor as 0", arguments: Sensor.allCases)
    func variableScopeReadsZero(_ sensor: Sensor) throws {
        #expect(try Formula.sensor(sensor).interpretDouble(scope: VariableScope()) == 0)
    }
}
