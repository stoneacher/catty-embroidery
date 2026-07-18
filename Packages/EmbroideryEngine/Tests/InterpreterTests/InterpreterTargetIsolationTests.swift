import EmbroideryEngine
import ProgramModel
import Testing

@Suite("Interpreter target isolation")
struct InterpreterTargetIsolationTests {
    /// US-201 AC 4: this suite compiling with both imports proves the Interpreter
    /// test target links `ProgramModel` and `EmbroideryEngine` side by side. The
    /// negative half — `ProgramModel` never importing the engine — is a build-level
    /// guarantee: its target has no such dependency to import.
    @Test("model positions convert to engine stage points at the interpreter seam")
    func modelToEngineSeam() {
        let object = Object(name: "Needle", startX: 30, startY: -12.5)
        // The conversion the interpreter will own (ADR-016): plain Doubles → StagePoint.
        let point = StagePoint(x: object.startX, y: object.startY)
        #expect(point == StagePoint(x: 30, y: -12.5))
    }
}
