@testable import catrobat_embroidery_ios
import EmbroideryEngine
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
    /// How many ticks to allow before the run must have said *something*.
    ///
    /// 60 = one second of logical time at `AppRunClock.preview`. Generous on
    /// purpose: the number guards against a silent hang, it does not encode an
    /// expectation about pacing, which belongs to US-306.
    static let tickBudget = 60

    @Test(arguments: SampleLibrary.all)
    func anInterpreterConstructsAndStepsFromASample(_ sample: SampleProgram) {
        var interpreter = Interpreter(program: sample.program, clock: AppRunClock.preview)
        #expect(!interpreter.isFinished)

        // Two engine facts this loop respects rather than asserts against, both
        // learned by watching this test fail: the **first tick emits nothing**
        // (the runtime starts its scripts before any brick runs), and the first
        // non-empty batch carries only `.colorArmed`, because both samples open
        // with `setThreadColor`. So events are accumulated over a budget instead
        // of read off a particular tick — the engine was right both times, and
        // pinning either detail here would duplicate US-306's pacing contract.
        var events: [InterpreterEvent] = []
        for _ in 0 ..< Self.tickBudget {
            guard case let .ticked(tickEvents) = interpreter.step() else { break }
            events += tickEvents
        }
        #expect(!events.isEmpty, "no events in \(Self.tickBudget) ticks")

        // Reading a payload is what makes this a *link* proof rather than a
        // construction proof: `StagePoint` and `NeedleUpdate` are
        // `EmbroideryEngine` types, so an unlinked engine cannot reach here.
        let carriesEngineGeometry = events.contains { event in
            switch event {
            case let .needleMoved(_, update): update.position.x.isFinite
            case let .stitch(_, position, _, _): position.x.isFinite
            default: false
            }
        }
        #expect(carriesEngineGeometry, "no needle or stitch event in \(Self.tickBudget) ticks")
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
