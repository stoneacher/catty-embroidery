@testable import catrobat_embroidery_ios
import Foundation
import Interpreter
import Samples
import Testing

/// Proves the five package products are *genuinely* linked to the app target,
/// not merely declared in the project file.
///
/// The distinction is the whole point of US-303: `packageProductDependencies`
/// can list a product that no code ever touches, and the app would still build.
/// Constructing a real `Interpreter` from a real `SampleProgram` and stepping it
/// exercises `Samples`, `ProgramModel`, `Interpreter` and `EmbroideryEngine` in
/// one call — if any of the four is unlinked, this file does not compile.
struct SampleLinkageTests {
    @Test func theSampleLibraryShipsAtLeastOneProgram() {
        #expect(!SampleLibrary.all.isEmpty)
    }

    /// The sample's name resolves to real text rather than falling back to its
    /// own key.
    ///
    /// Asserting "≠ key" rather than "== Octagon Rosette" deliberately: the
    /// English wording belongs to the `Samples` package and may be edited there
    /// without this story's knowledge, whereas a lookup that silently falls back
    /// to `sample.octagonRosette.name` is always a bug. That fallback is exactly
    /// what US-301 measured and designed around — SwiftPM copies an `.xcstrings`
    /// into a resource bundle without running `xcstringstool`, so the samples ship
    /// a legacy `en.lproj/Localizable.strings` instead.
    ///
    /// **The story's test-first plan is wrong about where these strings live.**
    /// It says the sample names resolve "through the String Catalog", meaning the
    /// app's `Localizable.xcstrings`. They do not and must not: they resolve
    /// through the `Samples` package's own bundle, which is what keeps the samples
    /// self-describing for M5. Corrected here rather than implemented as written.
    @Test(arguments: SampleLibrary.all)
    func aSampleNameResolvesRatherThanFallingBackToItsKey(_ sample: SampleProgram) {
        let name = String(localized: sample.displayName)
        #expect(!name.isEmpty)
        #expect(name != sample.nameKey)

        let summary = String(localized: sample.summary)
        #expect(!summary.isEmpty)
        #expect(summary != sample.descriptionKey)
    }

    /// The link proof: a real program, through the app's own clock, produces a
    /// tick. Nothing here is a stub — `SampleLibrary` builds the brick graph,
    /// `Interpreter` compiles and runs it, and the events it emits carry
    /// `EmbroideryEngine` types.
    @Test(arguments: SampleLibrary.all)
    func anInterpreterConstructsAndStepsFromASample(_ sample: SampleProgram) throws {
        var interpreter = Interpreter(program: sample.program, clock: AppRunClock.preview)
        #expect(!interpreter.isFinished)

        let outcome = interpreter.step()
        let events = try #require(
            if case let .ticked(events) = outcome {
                events
            } else {
                nil
            },
            "a freshly constructed interpreter must tick, not report finished"
        )
        #expect(!events.isEmpty)
    }

    /// ADR-018 requires only `tickDelta > 0`; the *app* pins one tick per frame,
    /// so a `wait(1)` brick occupies 60 ticks and reads as one second on screen.
    /// Recording it as an asserted constant rather than a comment is what the
    /// acceptance criterion asks for, and it is the value US-306's driver inherits.
    @Test func theAppClockAdvancesOneFramePerTick() {
        #expect(AppRunClock.preview == InterpreterClock(tickDelta: 1.0 / 60.0))
        #expect(AppRunClock.preview.tickDelta > 0)
    }
}
