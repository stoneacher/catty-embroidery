import EmbroideryEngine
import Interpreter
import ProgramModel
import Samples
import StagePreview
import Testing

/// The display model and the export model are **deliberately different
/// objects** (ADR-021), and this suite pins where they agree and where they do
/// not. Catroid needed `EmbroideryExportIsolationTest` for the same concern.
///
/// They agree on the drawn path for a single-object design: clause C/D re-emits
/// and interpolation intermediates are duplicates or on-segment points.
/// **Clause B is stronger** — it emits two records in explicit black that have
/// no counterpart in the display list at all, so a multi-actor export carries
/// black where the preview carries the incoming actor's colour. M3's samples
/// are single-object, so no user sees it this milestone; the test exists so the
/// difference is asserted rather than assumed away.
@Suite("Display versus export model")
struct DisplayVersusExportModelTests {
    // MARK: - A single-object sample: the two agree

    /// **The precondition is what makes the index comparison mean anything.**
    /// The colour-run boundary and the colour-change record can only be
    /// compared by index while the two sequences are the same length — which
    /// holds for this sample because nothing interpolates and nothing dedups.
    /// Without this assertion the equality below would be accidental agreement
    /// dressed up as an invariant, and would go quietly vacuous the day a
    /// sample starts interpolating.
    @Test("square coil: the display list and the assembled stream are the same length")
    func squareCoilDisplayAndExportAgreeInLength() {
        var run = interpreter(SampleLibrary[.squareCoil].program)
        let events = run.run(maxTicks: 100_000)
        let list = displayList(from: events)

        #expect(list.count == run.assembledStream().count)
        #expect(list.count == 2976)
    }

    /// Item 3: the colour-run boundary lands on the same index as the export
    /// model's colour change. Derived the same way `SquareCoilTests` derives
    /// it — 31 sides at 3 points per interval over `1 + 2 + … + 31` intervals
    /// plus the pattern's first anchor — so this is a claim about ADR-015's
    /// placement, not a number read off a run.
    @Test("square coil: the color-run boundary matches the export's color change")
    func squareCoilColorRunBoundaryMatchesTheColorChange() throws {
        var run = interpreter(SampleLibrary[.squareCoil].program)
        let events = run.run(maxTicks: 100_000)
        let list = displayList(from: events)
        let stream = run.assembledStream()

        let changeIndex = try #require(stream.stitches.firstIndex { $0.isColorChange })
        let intervalsBeforeChange = (1 ... 31).reduce(0, +)
        #expect(changeIndex == 3 * intervalsBeforeChange + 1)

        #expect(list.colorRuns.count == 2)
        #expect(list.colorRuns[0].range == 0 ..< changeIndex)
        #expect(list.colorRuns[1].range == changeIndex ..< list.count)
        #expect(list.colorRuns[0].color != list.colorRuns[1].color)
    }

    /// And the colours themselves agree — **stitch for stitch, not run endpoint
    /// for run endpoint** (Codex round 1). An earlier version checked only the
    /// first and last stitch of each run, which a regression at any interior
    /// stitch survives untouched. ADR-021's claim for a single-object design is
    /// that the whole colour *sequence* agrees, so that is what is asserted.
    @Test("square coil: the color sequence agrees stitch for stitch with the export")
    func squareCoilColorSequenceMatchesTheExport() {
        var run = interpreter(SampleLibrary[.squareCoil].program)
        let events = run.run(maxTicks: 100_000)
        let list = displayList(from: events)
        let stream = run.assembledStream()

        #expect(list.stitches.map(\.color) == stream.stitches.map(\.color))
    }

    // MARK: - Clause A: a fourth divergence, found in review

    /// **A divergence ADR-021's original enumeration missed** (Codex round 2).
    /// It listed clause C/D re-emits, interpolation intermediates and clause B;
    /// workspace dedup is a fourth, and it is reachable with a *single* actor.
    ///
    /// `emitStitches` emits one event per `addStitch` **call** — documented
    /// since M2, and deliberate: the event is the trace of what the program
    /// asked for, which is what US-306's stitch budget counts. But clause A
    /// drops an identical consecutive command from the same actor, so the
    /// export has no record for it while the display list does.
    ///
    /// The drawn *path* is unaffected — the extra entry is at the position the
    /// previous stitch already occupies — but the colour run boundary moves one
    /// entry earlier when a colour change is armed across the dedup.
    ///
    /// **Not fixed in the app, deliberately.** Filtering it preview-side would
    /// put ADR-012's clause A into the app layer, which is exactly what ADR-021
    /// exists to prevent. Pinned instead, and the ADR corrected.
    @Test("workspace dedup leaves an entry in the display list with no export record")
    func clauseADedupIsAFourthDivergence() {
        var run = interpreter(singleObjectProgram([
            .setThreadColor(hex: "#ff0000"),
            .stitch,
            .setThreadColor(hex: "#00ff00"),
            .stitch, // same position, same actor — clause A drops this one
            .placeAt(x: .number(1), y: .number(0)),
            .stitch
        ]))
        let events = run.run(maxTicks: 200)
        let list = displayList(from: events)
        let stream = run.assembledStream()

        #expect(list.stitches.map(\.color) == [PreviewColor.red, PreviewColor.green, PreviewColor.green])
        #expect(stream.stitches.map(\.color) == [PreviewColor.red, PreviewColor.green])
        #expect(list.count == stream.count + 1)

        // **Positions and the surviving flag, not just the colours** (Codex
        // round 3). Colours and counts alone are satisfied by an implementation
        // that dropped the *final* stitch instead of the duplicate — asserting
        // which record survived is what distinguishes the two.
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0), EmbroideryPoint(x: 2, y: 0)
        ])
        #expect(list.stitches.map(\.position) == [
            StagePoint(x: 0, y: 0), StagePoint(x: 0, y: 0), StagePoint(x: 1, y: 0)
        ])
        // ADR-015: the change armed across the dedup rides the next *surviving*
        // stitch, so the colour change lands on the export's second record.
        #expect(stream.stitches.map(\.isColorChange) == [false, true])
        #expect(stream.colorChangeCount == 1)

        // The path is unchanged: the extra entry sits on the previous stitch.
        #expect(list.stitches[0].position == list.stitches[1].position)

        // And this is why the square-coil colour-sequence test needs its length
        // precondition — that sample simply contains no deduped command.
        #expect(list.colorRuns.map(\.range) == [0 ..< 1, 1 ..< 3])
    }

    /// **A fifth divergence** (Codex round 3), and the one with the largest
    /// visible gap: ADR-020 rejection. `emitStitches` publishes the event
    /// unconditionally, while `assembled()` asks `canAppend` first and skips a
    /// recorded op the stream would refuse — so an unconvertible coordinate is
    /// drawn but never stitched.
    ///
    /// This is the case the milestone README already anticipates for the export
    /// gate ("ops recorded and drawn, every one rejected at replay"), which is
    /// why export gates on the post-replay stream rather than on
    /// `hasValidPattern`. It belongs in ADR-021's list too.
    @Test("an ADR-020-rejected coordinate is drawn but never stitched")
    func adr020RejectionIsAFifthDivergence() {
        var run = interpreter(singleObjectProgram([
            .setThreadColor(hex: "#ff0000"),
            .stitch,
            .placeAt(x: .number(1e300), y: .number(0)),
            .stitch
        ]))
        let events = run.run(maxTicks: 200)
        let list = displayList(from: events)
        let stream = run.assembledStream()

        #expect(list.count == 2, "the preview draws what the program asked for")
        #expect(stream.count == 1, "the machine never goes there")
        #expect(list.stitches[1].position == StagePoint(x: 1e300, y: 0))
        #expect(stream.stitches.map(\.position) == [EmbroideryPoint(x: 0, y: 0)])
    }

    /// **A sixth divergence** (Codex round 4): the assembler's inter-layer
    /// boundary. On the first surviving op of a later layer, `assembled()`
    /// emits a colour change and a jump, each re-emitting the previous layer's
    /// last point — two export-only records with no display counterpart, and
    /// none of the other five mechanisms.
    @Test("the inter-layer boundary adds two export-only records")
    func layerBoundaryIsASixthDivergence() {
        var run = interpreter(twoLayersProgram(waitTicks: 40))
        let events = run.run(maxTicks: 100_000)
        let list = displayList(from: events)
        let stream = run.assembledStream()

        #expect(list.count == 4, "four program stitches")
        #expect(stream.count == 6, "plus the boundary's colour-change and jump re-emits")

        // Both boundary records sit on the lower layer's last point, (10, 0)
        // → 20 embroidery units, and carry the change and the jump in order.
        #expect(stream.stitches[2].position == EmbroideryPoint(x: 20, y: 0))
        #expect(stream.stitches[3].position == EmbroideryPoint(x: 20, y: 0))
        #expect(stream.stitches[2].isColorChange)
        #expect(stream.stitches[3].isJump)
    }

    /// **A seventh** (Codex round 4), and the one that matters most for M4/M5:
    /// ordering. `assembled()` replays `layerOps.keys.sorted()`, so the export
    /// is ordered by layer while the display list keeps interpreter execution
    /// order. For a program whose upper layer stitches *first* the two
    /// sequences are genuinely reordered, not merely padded.
    ///
    /// This is the concrete form of the structural reason ADR-021 rejected
    /// per-frame `assembled()`: a new stitch can land in the middle of the
    /// returned array, which is what forecloses ADR-009's immutable prefix.
    @Test("export is ordered by layer while the display keeps execution order")
    func layerOrderingIsASeventhDivergence() {
        // The *upper* layer runs first here, so sorting by layer reorders it
        // behind the lower one.
        let upperFirst = Program(scenes: [Scene(objects: [
            Object(
                name: "Upper",
                startX: 0, startY: 0, zIndex: 5,
                scripts: [Script(bricks: [
                    .placeAt(x: .number(50), y: .number(0)), .stitch
                ])]
            ),
            Object(
                name: "Lower",
                startX: 0, startY: 0, zIndex: 0,
                scripts: [Script(bricks: [
                    .wait(seconds: .number(40 * previewClock.tickDelta)),
                    .placeAt(x: .number(-50), y: .number(0)), .stitch
                ])]
            )
        ])])

        var run = interpreter(upperFirst)
        let events = run.run(maxTicks: 100_000)
        let list = displayList(from: events)
        let stream = run.assembledStream()

        // Display: execution order — the upper layer stitched first.
        #expect(list.stitches.map(\.position.x) == [50, -50])
        // Export: layer order — the lower layer's record comes first.
        #expect(stream.stitches.first?.position == EmbroideryPoint(x: -100, y: 0))
    }

    // MARK: - Two actors on one layer: clause B, where they diverge

    /// Item 9. Two objects on one layer, PreviewColor.red then PreviewColor.green, so the export's two
    /// **black** clause-B records are distinguishable from everything else.
    ///
    /// Asserting the count rather than mere presence is the point: "some black
    /// points appear" passes against a one-point implementation, and clause B
    /// emits exactly two — both unconditional, with `isFar` deciding only
    /// whether the second arms a jump.
    @Test("clause B puts exactly two black records in the export and none in the preview")
    func clauseBDivergesInColorNotJustInRecordCount() {
        var run = interpreter(twoActorsOnOneLayerProgram(waitTicks: 40))
        let events = run.run(maxTicks: 100_000)
        let list = displayList(from: events)
        let stream = run.assembledStream()

        // Both actors are non-black, or this proves only that extra records
        // exist — not that they differ in *colour*, which is the claim.
        let previewColors = Set(list.stitches.map(\.color))
        #expect(previewColors == [PreviewColor.red, PreviewColor.green])
        #expect(!previewColors.contains(.black))

        let blackRecords = stream.stitches.filter { $0.color == .black }
        #expect(blackRecords.count == 2, "clause B emits exactly two, not one and not three")

        // Both sit at the *previous* actor's workspace position, i.e. where the
        // PreviewColor.red object last stitched — (10, 0) → 20 embroidery units.
        #expect(blackRecords.allSatisfy { $0.position == EmbroideryPoint(x: 20, y: 0) })
        #expect(blackRecords[0].isColorChange)

        // And they have no counterpart in the display list at all.
        #expect(stream.count == list.count + 2)
    }

    /// The alternation must happen exactly **once**, or the record count above
    /// is not derivable: ADR-018 round-robins one action brick per thread per
    /// tick, so without the wait the two objects interleave and clause B fires
    /// on nearly every stitch. This pins the fixture's own premise.
    @Test("the fixture produces exactly one actor alternation on the layer")
    func fixtureHasASingleActorAlternation() {
        var run = interpreter(twoActorsOnOneLayerProgram(waitTicks: 40))
        let events = run.run(maxTicks: 100_000)

        let actorsInStitchOrder = events.compactMap { event -> ActorID? in
            if case let .stitch(actor, _, _, _) = event {
                actor
            } else {
                nil
            }
        }
        let alternations = zip(actorsInStitchOrder, actorsInStitchOrder.dropFirst())
            .count { $0 != $1 }
        #expect(alternations == 1, "actors: \(actorsInStitchOrder.map(\.rawValue))")
        #expect(actorsInStitchOrder.first == ActorID(0))
        #expect(actorsInStitchOrder.last == ActorID(1))
    }

    /// The inputs are ordinary and convertible, so ADR-020 cannot reject them.
    /// A rejected emission is skipped whole by the replay — which would delete
    /// the very records the test above counts, and it would do so silently.
    @Test("the fixture's coordinates are all comfortably convertible")
    func fixtureCoordinatesAreNotRejected() {
        var run = interpreter(twoActorsOnOneLayerProgram(waitTicks: 40))
        let events = run.run(maxTicks: 100_000)
        let positions = RunBatch.reducing(events).stitches.map(\.position)

        #expect(positions.allSatisfy { EmbroideryPoint(converting: $0) != nil })
        for (previous, next) in zip(positions, positions.dropFirst()) {
            #expect(!EmbroideryStream.requiresTraversal(from: previous, to: next))
        }
    }

    // MARK: - US-307 item 6: the two size sources agree

    /// The size in millimetres may be read from either model, and for a design with no
    /// rejected coordinates the two must agree — which is what lets the summary prefer the
    /// export model without the spoken figure jumping when a run ends.
    ///
    /// **They agree to a tolerance, not exactly, and the bound is derived rather than
    /// picked.** The export path rounds each coordinate to a whole embroidery unit through
    /// `javaRound`, whose error per edge is in (−0.5, +0.5]; a span is a difference of two
    /// edges, so its error is strictly within ±1 unit = **±0.1 mm**. Measured on this sample:
    /// 98.5676 mm from the display bounds against 98.6 mm from the export model, a gap of
    /// 0.032 mm — three times inside the bound.
    ///
    /// Per this suite's own standing rule, the preconditions that make agreement *possible*
    /// are asserted first. Without them the equality would be accidental agreement dressed up
    /// as an invariant, and would go quietly vacuous the day a sample started interpolating.
    @Test("the summary's size agrees between the display list and the export model")
    func theSummarySizeAgreesBetweenBothModels() async throws {
        let drained = await driveToCompletion(SampleLibrary[.octagonRosette].program)
        var run = PreviewRunState()
        run.begin()
        for update in drained.updates {
            run.apply(update)
        }
        let exported = try #require(run.exportModel)

        // Preconditions: nothing interpolated, nothing jumped, nothing was rejected — so the
        // two models describe the same point set and a size comparison means something.
        #expect(run.display.count == exported.count)
        #expect(exported.stitches.allSatisfy { !$0.isJump })
        #expect(
            run.display.stitches.allSatisfy { EmbroideryPoint(converting: $0.position) != nil }
        )

        let fromExport = StageSummary(display: run.display, exportModel: exported)
        let fromDisplay = StageSummary(display: run.display, exportModel: nil)

        // **Both sizes are real before they are compared.** Without this the test is green
        // for a summary that reports zeros from both sources — 0 agrees with 0 to any
        // tolerance — which is the "what could be deleted while this stays green" failure
        // this repo has now hit nine times across two stories. Caught here by running the
        // red phase and reading which suites *passed*.
        #expect(abs(fromExport.widthInMillimetres - 98.6) < 0.05)
        #expect(abs(fromDisplay.widthInMillimetres - 98.6) < 0.05)

        #expect(
            abs(fromExport.widthInMillimetres - fromDisplay.widthInMillimetres) < 0.1,
            "width \(fromExport.widthInMillimetres) vs \(fromDisplay.widthInMillimetres)"
        )
        #expect(
            abs(fromExport.heightInMillimetres - fromDisplay.heightInMillimetres) < 0.1,
            "height \(fromExport.heightInMillimetres) vs \(fromDisplay.heightInMillimetres)"
        )
        // The counts are read from the display list either way, which is the documented
        // asymmetry — so switching source cannot change them at all.
        #expect(fromExport.stitchCount == fromDisplay.stitchCount)
        #expect(fromExport.colorCount == fromDisplay.colorCount)
    }
}
