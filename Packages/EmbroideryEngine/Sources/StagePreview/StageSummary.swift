import EmbroideryEngine

/// What the stage holds, as the four facts a VoiceOver user needs: how many stitches, how
/// many colours, and how big the finished design is.
///
/// A pure value in the package rather than strings in the view, because the *facts* are
/// what can be got wrong and the strings are what cannot be tested from a hosted view —
/// nothing can read a rendered accessibility value back. The app maps this onto String
/// Catalog entries in one place (`StageAccessibility`).
///
/// **The size prefers the export model, and that is a fidelity decision.** ADR-021
/// divergence #5 lets a coordinate the stream *rejects* reach the display trace, so it is
/// drawn but never stitched; the display bounds therefore describe what is on screen while
/// the export model describes what the machine will sew. A size in millimetres is a claim
/// about fabric, so it comes from the export model whenever a run has produced one.
///
/// **The counts do not**, and the asymmetry is deliberate. `display.count` is what the
/// milestone already tells the user — `stage.run.limit.notice`'s own comment argues "the
/// count is what is on screen; the cap is an implementation detail the user never agreed
/// to" — and using two different sources for "how many" in two places on one screen would
/// be worse than either choice. Measured on both bundled samples the two agree exactly
/// (3194/3194 and 2976/2976), so nothing observable rests on it this milestone.
public struct StageSummary: Equatable, Sendable {
    public let stitchCount: Int

    /// **Distinct thread colours, not colour *blocks*.**
    ///
    /// `StitchDisplayList.ColorRun` is a run partition, so red → green → red is three runs
    /// and two colours; DST's `CO` header field counts blocks, i.e. changes + 1, which is
    /// three (ADR-012). This number is the one a user threads, and it must not be reused
    /// for the header — US-308 derives `CO` from `EmbroideryStream.colorChangeCount`.
    ///
    /// Neither bundled sample can tell the two definitions apart (1 of each and 2 of each,
    /// measured), which is exactly why `StageSummaryTests` pins it with a hand-built
    /// three-run list.
    public let colorCount: Int

    public let widthInMillimetres: Double
    public let heightInMillimetres: Double

    /// Nothing stitched — the value a fresh or reset run reports.
    public static let empty = StageSummary(
        stitchCount: 0, colorCount: 0, widthInMillimetres: 0, heightInMillimetres: 0
    )

    public init(
        stitchCount: Int,
        colorCount: Int,
        widthInMillimetres: Double,
        heightInMillimetres: Double
    ) {
        self.stitchCount = stitchCount
        self.colorCount = colorCount
        self.widthInMillimetres = widthInMillimetres
        self.heightInMillimetres = heightInMillimetres
    }

    /// Summarises a run's display list, preferring `exportModel`'s bounding box for the
    /// size when there is one.
    ///
    /// Total for every input: a stream with no records has no bounding box, an empty
    /// display list has no bounds, and both fall through to zeros rather than trapping.
    public init(display: StitchDisplayList, exportModel: EmbroideryStream?) {
        stitchCount = display.count
        // O(runs), not O(stitches): the runs are already a gapless partition by colour, so
        // the distinct colours are among their labels and nothing has to scan 50 000 stitches
        // to find them.
        colorCount = Set(display.colorRuns.map(\.color)).count

        let extent = Self.extentInMillimetres(display: display, exportModel: exportModel)
        widthInMillimetres = extent.width
        heightInMillimetres = extent.height
    }

    /// The design's size, preferring the export model. Returns zeros rather than trapping for
    /// every empty or degenerate input.
    private static func extentInMillimetres(
        display: StitchDisplayList,
        exportModel: EmbroideryStream?
    ) -> (width: Double, height: Double) {
        if let box = exportModel?.boundingBox {
            let units = StageGeometry.millimetresPerEmbroideryUnit
            // `subtractingReportingOverflow`, because these are `Int`s and an overflow here
            // would **trap** — a crash, in an accessibility summary. Not reachable through a
            // run: ADR-020's move guard drops any step longer than `maxInterpolatedMoveInUnits`
            // (measured — a stream handed ±1e18 keeps one stitch and rejects the other), and
            // the record count is bounded by `maxStitchesPerRun` besides. But
            // `EmbroideryStream` is public and this is one line.
            let (width, widthOverflowed) = box.max.x.subtractingReportingOverflow(box.min.x)
            let (height, heightOverflowed) = box.max.y.subtractingReportingOverflow(box.min.y)
            if !widthOverflowed, !heightOverflowed {
                return (width: Double(width) * units, height: Double(height) * units)
            }
            return unmeasurable
        }

        // No export model yet — a run in flight, or one that produced no records at all.
        // `bounds` is already `nil` when nothing finite has been stitched and drops a
        // non-finite edge per axis, so an ADR-021 divergence #5 coordinate cannot make the
        // spoken size an infinity.
        guard let bounds = display.bounds else { return unmeasurable }

        let width = bounds.width * StageGeometry.millimetresPerPoint
        let height = bounds.height * StageGeometry.millimetresPerPoint

        // **Two finite edges can still have an infinite span.** `bounds` drops a *non-finite*
        // coordinate per axis, so both edges here are finite — but `maxX − minX` overflows for
        // a design spanning the `Double` range, and the summary is spoken, so the user would
        // hear an infinity (Codex round 2, reproduced: a list holding ±greatestFiniteMagnitude
        // reported `inf` mm). Reachable through the display list specifically, because ADR-021
        // divergence #5 lets it hold coordinates the export stream rejects.
        //
        // Reported as unmeasurable rather than clamped: a design that large has no size any
        // number would convey, and 0 is what every other "nothing to state" case reports.
        guard width.isFinite, height.isFinite else { return unmeasurable }
        return (width: width, height: height)
    }

    /// No size that can honestly be stated — an empty design, or one too large for a `Double`
    /// to span.
    private static let unmeasurable = (width: 0.0, height: 0.0)
}
