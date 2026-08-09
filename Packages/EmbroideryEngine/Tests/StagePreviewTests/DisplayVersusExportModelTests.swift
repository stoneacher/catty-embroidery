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

    /// And the colours themselves agree, run for run — not merely the index at
    /// which they change.
    @Test("square coil: each run's color is the color the export records there")
    func squareCoilRunColorsMatchTheExport() {
        var run = interpreter(SampleLibrary[.squareCoil].program)
        let events = run.run(maxTicks: 100_000)
        let list = displayList(from: events)
        let stream = run.assembledStream()

        for colorRun in list.colorRuns {
            #expect(stream.stitches[colorRun.range.lowerBound].color == colorRun.color)
            #expect(stream.stitches[colorRun.range.upperBound - 1].color == colorRun.color)
        }
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
