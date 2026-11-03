import CatrobatImport
import Interpreter
import ProgramModel

/// Runs an imported language test in the interpreter's harness (brief D3, slice 7).
enum LanguageTestRunner {
    /// Catroid plays at 60 frames a second; one frame is one tick (brief D6).
    static let clock = InterpreterClock(tickDelta: 1.0 / 60)

    /// The adapter from `CatrobatImport` to `Interpreter`: the importer's flat
    /// object list in order, each built by `ImportedObject.object(zIndex:)` (the one
    /// place Catroid's start pose lives), with its scripts as steps.
    static func harness(for program: ImportedProgram) -> [HarnessObject] {
        program.objects.enumerated().map { index, object in
            HarnessObject(object.object(zIndex: index), scripts: object.scripts.map { $0.steps.map(step) })
        }
    }

    static func step(_ step: ImportedStep) -> ScriptStep {
        switch step {
        case let .brick(brick): .brick(brick)
        case let .assertEquals(actual, expected): .assertEquals(actual: actual, expected: expected)
        case .finishStage: .finishStage
        case .exitStage: .exitStage
        case .waitTillIdle: .waitTillIdle
        }
    }

    static func run(_ program: ImportedProgram, budget: Int = Interpreter.harnessBudget) -> HarnessRun {
        var interpreter = Interpreter(harness: harness(for: program), clock: clock, variables: program.variables)
        return interpreter.runHarness(budget: budget)
    }
}
