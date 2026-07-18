import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

@Suite("Interpreter target isolation")
struct InterpreterTargetIsolationTests {
    /// US-201 AC 4: this suite compiles with `ProgramModel` and `EmbroideryEngine`
    /// imported side by side. Note the imports come from this test target's own
    /// dependencies, so the ADR-016 dependency *direction* is guarded by the
    /// manifest itself, not by this test: `ProgramModel` has no engine dependency
    /// to import, and `Interpreter`'s dependencies only gain meaning with US-204's
    /// real code.
    @Test("model positions convert to engine stage points at the interpreter seam")
    func modelToEngineSeam() {
        let object = Object(name: "Needle", startX: 30, startY: -12.5)
        // The conversion the interpreter will own (ADR-016): plain Doubles → StagePoint.
        let point = StagePoint(x: object.startX, y: object.startY)
        #expect(point == StagePoint(x: 30, y: -12.5))
    }
}
