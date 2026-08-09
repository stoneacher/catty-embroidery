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

        #expect(list.stitches.map(\.color) == [red, green, green])
        #expect(stream.stitches.map(\.color) == [red, green])
        #expect(list.count == stream.count + 1)

        // The path is unchanged: the extra entry sits on the previous stitch.
        #expect(list.stitches[0].position == list.stitches[1].position)

        // And this is why the square-coil colour-sequence test needs its length
        // precondition — that sample simply contains no deduped command.
        #expect(list.colorRuns.map(\.range) == [0 ..< 1, 1 ..< 3])
    }

    // MARK: - Two actors on one layer: clause B, where they diverge

    /// Item 9. Two objects on one layer, red then green, so the export's two
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
        #expect(previewColors == [red, green])
        #expect(!previewColors.contains(.black))

        let blackRecords = stream.stitches.filter { $0.color == .black }
        #expect(blackRecords.count == 2, "clause B emits exactly two, not one and not three")

        // Both sit at the *previous* actor's workspace position, i.e. where the
        // red object last stitched — (10, 0) → 20 embroidery units.
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
}
