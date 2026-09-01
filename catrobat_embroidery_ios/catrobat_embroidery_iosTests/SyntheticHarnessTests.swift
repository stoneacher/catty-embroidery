@testable import catrobat_embroidery_ios
import Interpreter
import Samples
import StagePreview
import Testing

/// US-309's app-side harness: how a 50 000-stitch design becomes reachable in the running
/// app, and how it is kept out of any build a user could get.
///
/// **The synthetic is a `SampleProgram` with a `#if DEBUG` `SampleID`, appended by the app
/// rather than by `SampleLibrary`.** Both halves of that are load-bearing:
///
/// - It needs a real `SampleID` because the stage's title, its accessibility label and
///   `ExportControl.readiness` all key off a selected `SampleProgram`. A launch-argument
///   path that ran the program without selecting anything would produce screenshots of a
///   half-configured screen — no title, and an export gate reading "no design".
/// - It must **not** be in `SampleLibrary.all`, because five suites iterate that array to
///   assert things true of shipping content — a checked-in JSON encoding, a DST golden, an
///   ADR-019 threshold screen — none of which a measurement fixture should have to satisfy.
///   ROADMAP M3 also requires the bundled samples to be "visually appealing designs … not
///   test shapes", and a 50 000-stitch hatch is the definition of a test shape.
@MainActor
struct SyntheticHarnessTests {
    @Test("the picker offers the synthetic design in debug builds")
    func thePickerOffersTheSyntheticDesignInDebugBuilds() {
        #expect(AppModel().samples.map(\.id).contains(.us309Synthetic))
    }

    /// It is **last**, so it can never displace a shipping sample from the top of the picker
    /// and every existing screenshot and index-based expectation keeps its meaning.
    @Test("the synthetic design is last in the picker")
    func theSyntheticDesignIsLastInThePicker() {
        let ids = AppModel().samples.map(\.id)
        #expect(ids.last == .us309Synthetic)
        #expect(ids.dropLast() == SampleLibrary.all.map(\.id))
    }

    /// The guard that keeps ROADMAP M3's "not test shapes" rule true, and that keeps the five
    /// `SamplesTests` suites off this design.
    @Test("the synthetic design is not in the shipping library")
    func theSyntheticDesignIsNotInTheShippingLibrary() {
        #expect(!SampleLibrary.all.map(\.id).contains(.us309Synthetic))
        #expect(!SampleID.shipping.contains(.us309Synthetic))
    }

    /// Selecting it must give the stage everything a shipping sample gives it — otherwise the
    /// screenshots this story owes are of a different screen from the one users see.
    @Test("selecting the synthetic design configures the stage like any other")
    func selectingTheSyntheticDesignConfiguresTheStageLikeAnyOther() throws {
        let model = AppModel()
        let synthetic = try #require(model.samples.last)

        model.select(synthetic)

        #expect(model.selection?.sample.id == .us309Synthetic)
        #expect(model.isSelected(synthetic))
        // Seeded from the sample, exactly as US-308 does for the shipping two, and valid —
        // a name the field rejected would leave the export gate shut in every screenshot.
        #expect(try model.exporter.validatedName.get().value == SampleID.us309Synthetic.resourceName)
    }

    /// The design actually reaches the scale the story is about.
    ///
    /// Asserted here as well as in the package, because these are two different claims: the
    /// package pins what the *builder* produces, and this pins that the builder the **app
    /// links** is that one. A harness wired to the wrong program would pass every test in
    /// `SyntheticDesignTests` and still capture a 3 000-stitch design.
    @Test("the synthetic design the app links reaches fifty thousand stitches")
    func theSyntheticDesignTheAppLinksReachesFiftyThousandStitches() throws {
        let model = AppModel()
        let synthetic = try #require(model.samples.last)

        var interpreter = Interpreter(program: synthetic.program, clock: InterpreterClock(tickDelta: 1.0 / 60.0))
        var stitches = 0
        var ticks = 0
        while case let .ticked(events) = interpreter.step() {
            stitches += RunBatch.reducing(events).stitches.count
            ticks += 1
        }

        #expect(stitches >= 50_000)
        // ≥ 10 s of animation at ADR-018's one tick per displayed frame, so the run itself is
        // long enough to be one of AC3's capture windows.
        #expect(ticks >= 600)
    }
}
