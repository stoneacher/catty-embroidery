import ProgramModel
import Samples
import Testing

/// ADR-016/ADR-022: `Samples` depends on `ProgramModel` **only**.
///
/// Like `InterpreterTests/InterpreterTargetIsolationTests`, the dependency
/// *direction* is enforced by the manifest, not by this suite — a test cannot
/// observe an edge that does not exist. What this pins is the consequence a
/// reader can check: a sample is expressible in pure model types, so nothing in
/// `Samples` needs an engine type to describe a design.
///
/// Note the asymmetry, because it looks like a contradiction and is not: this
/// *test target* does depend on `Interpreter` and `EmbroideryEngine`, since six of
/// the story's eight test items run the interpreter or build a DST file. ADR-016's
/// DAG constrains library targets; SwiftPM permits the test target more, and it
/// has to, or the story's own acceptance criteria would be unmeasurable.
@Suite("Samples target isolation")
struct SamplesTargetIsolationTests {
    @Test("a sample is expressible in ProgramModel types alone", arguments: SampleLibrary.all)
    func samplesAreModelOnly(_ sample: SampleProgram) {
        let program: Program = sample.program
        let objects = program.scenes.flatMap(\.objects)
        #expect(!objects.isEmpty)

        // Positions are plain Doubles and colours plain hex strings at this layer
        // (ADR-016) — the interpreter owns every model→engine conversion.
        for object in objects {
            #expect(object.startX.isFinite)
            #expect(object.startY.isFinite)
            #expect(object.startHeading.isFinite)
        }
    }
}
