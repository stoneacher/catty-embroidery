@testable import catrobat_embroidery_ios
import EmbroideryEngine
import Foundation
import Interpreter
import ProgramModel
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

    /// How many ticks to allow before the run must have said *something*.
    ///
    /// 60 = one second of logical time at `AppRunClock.preview`. Generous on
    /// purpose: the number guards against a silent hang, it does not encode an
    /// expectation about pacing, which belongs to US-306.
    static let tickBudget = 60

    /// The link proof: a real program, through the app's own clock, produces a
    /// tick. Nothing here is a stub — `SampleLibrary` builds the brick graph,
    /// `Interpreter` compiles and runs it, and the events it emits carry
    /// `EmbroideryEngine` types.
    ///
    /// Note how the linkage actually resolves: the test target declares **no**
    /// `packageProductDependencies` of its own. These imports work because the
    /// host app links the products and the test bundle resolves through
    /// `TEST_HOST` + `BUILT_PRODUCTS_DIR`. That is deliberate — adding the
    /// products to the test target would make this file compile even if the app
    /// stopped using them, i.e. it would stop proving the thing it is named for.
    /// The cost is diagnostic: if a later story drops a product from *app* code,
    /// this file fails at link time with a message that does not mention why.
    @Test(arguments: SampleLibrary.all)
    func anInterpreterConstructsAndStepsFromASample(_ sample: SampleProgram) {
        var interpreter = Interpreter(program: sample.program, clock: AppRunClock.preview)
        #expect(!interpreter.isFinished)

        // Events are accumulated over a budget rather than read off a particular
        // tick, because **the two samples do not agree on what the early ticks
        // look like** (measured, in-loop review 2026-08-11):
        //
        //   squareCoil      tick 0 emits 1 event (`.colorArmed`)
        //   octagonRosette  tick 0 is empty; first batch is tick 3, 52 events
        //                   led by `.needleMoved`
        //
        // Two earlier versions of this test asserted on tick 1 and then on the
        // first non-empty batch, and an earlier version of *this comment* stated
        // both behaviours as general engine facts. Each is true of one sample and
        // false of the other. The budget is what makes the test independent of a
        // detail that belongs to US-306's pacing contract, not to this smoke test.
        //
        // Margin, per ADR-019's spirit: the first geometry event lands at tick 3
        // of 60, and a full run is 137/139 ticks. The budget is one second of
        // *logical* time, so a future sample opening with `wait(1)` would need
        // 61+ ticks and fail here with a message that reads like a link failure.
        var events: [InterpreterEvent] = []
        for _ in 0 ..< Self.tickBudget {
            guard case let .ticked(tickEvents) = interpreter.step() else { break }
            events += tickEvents
        }
        #expect(!events.isEmpty, "no events in \(Self.tickBudget) ticks")

        // Reading a payload is what makes this a *link* proof rather than a
        // construction proof: `StagePoint` and `NeedleUpdate` are
        // `EmbroideryEngine` types, so an unlinked engine cannot reach here.
        // Distinct positions, not merely *a* position. Asserting that some event
        // carries finite geometry would still pass if a regression emitted the
        // same `.needleMoved` forever — i.e. while the program was stuck. Two
        // different positions is the weakest claim that means "it progressed",
        // and it is what makes this a smoke test rather than a liveness check
        // dressed up as one. (Cross-vendor review found the earlier version.)
        var positions: Set<[Double]> = []
        for event in events {
            switch event {
            case let .needleMoved(_, update): positions.insert([update.position.x, update.position.y])
            case let .stitch(_, position, _, _): positions.insert([position.x, position.y])
            default: break
            }
        }
        // **Both** properties, because each fix lost the other. Requiring only a
        // finite position passed while the needle repeated one point forever;
        // requiring only two distinct points passes for `(nan, 0)` and
        // `(infinity, 0)`, which are two set members and no geometry at all. The
        // pair is the claim: it moved, and it moved somewhere representable.
        #expect(
            positions.count >= 2,
            "expected two distinct needle positions in \(Self.tickBudget) ticks, saw \(positions.count)"
        )
        #expect(
            positions.allSatisfy { $0.allSatisfy(\.isFinite) },
            "needle reached a non-finite coordinate: \(positions)"
        )
    }

    /// ADR-018 requires only `tickDelta > 0`; the *app* pins one tick per frame,
    /// which is the coupling the acceptance criterion asks to have recorded, and
    /// the value US-306's driver inherits.
    ///
    /// Asserts the clock's *effect*, not its definition.
    ///
    /// The earlier version compared `AppRunClock.preview` against
    /// `InterpreterClock(tickDelta: 1.0 / 60.0)` — restating the constant one
    /// file away, which cannot fail for any reason worth knowing about, and
    /// testing nothing about advancement despite the name. A `wait(1)` brick
    /// under this clock occupies exactly 60 ticks, so `.waited` is emitted on
    /// tick index 59 and the program is finished by tick 60. *That* is what "one
    /// tick per frame" means, and it fails if the constant changes.
    @Test func theAppClockMakesAWaitOfOneSecondTakeSixtyTicks() {
        let program = Program(scenes: [
            Scene(objects: [
                Object(scripts: [Script(bricks: [.wait(seconds: .number(1))])])
            ])
        ])
        var interpreter = Interpreter(program: program, clock: AppRunClock.preview)

        var waitedTicks: [Int] = []
        for tick in 0 ..< 120 {
            guard case let .ticked(events) = interpreter.step() else { break }
            if events.contains(where: {
                if case .waited = $0 {
                    true
                } else {
                    false
                }
            }) {
                waitedTicks.append(tick)
            }
        }

        // `last`, and also the count: asserting only the last tick would pass if
        // the wait emitted spurious extra `.waited` events along the way, as long
        // as the final one landed on 59. A one-second wait is one wait.
        #expect(
            waitedTicks.last == 59,
            "a one-second wait should end on tick 59, ended on \(String(describing: waitedTicks.last))"
        )
        #expect(waitedTicks.count == 1, "expected exactly one .waited event, saw \(waitedTicks.count)")
        #expect(interpreter.isFinished)
    }
}
