import StagePreview
import Testing

/// US-309 AC4: per-frame work does not grow with the settled stitch count.
///
/// **This is the story's real assertion, and it is headless.** The device capture cannot
/// discriminate here: the difference between a 5 000-stitch and a 50 000-stitch settled
/// frame is one copy-on-write of the display list's buffer (measured at 12.7 µs, 0.08 % of
/// a frame) plus the compositing of a larger raster, both well inside frame-to-frame noise.
/// A p99 comparison would come out "the same" whether ADR-009's claim held or not. What the
/// device measures is AC3's absolute bar; what *tests* the claim is here, on the fast gate.
///
/// **AC4's claim is also restated, because as written it is false.** The criterion says
/// per-frame work is "independent of total stitch count". It is independent of the settled
/// stitch count *at a fixed colour-run count*, and **linear in colour runs** —
/// `StitchDrawPlan.planning` walks `list.colorRuns` twice, so a design that changed colour
/// on every stitch has `colorRuns == count` and a per-frame cost that is O(n) after all.
/// Re-measured, and stated **with the fixture each number belongs to**, because the earlier
/// bare "300× spread" was read as applying to the 1 000-run comparison below and produced a
/// review suggestion the code fails: at 50 000 settled with a 100-stitch tail, planning the
/// live window costs **0.041 ms at one colour run, 0.246 ms at 1 000 (6.0×) and 9.791 ms at
/// 50 000 (239×)**. Both halves are asserted, because a criterion that only states the
/// flattering half is a criterion that cannot fail.
@Suite("US-309 draw-plan scaling", .serialized, .timeLimit(.minutes(1)))
struct StitchDrawPlanScalingTests {
    /// The live tail AC4 names.
    private static let tail = 100

    /// **The assertion that survives a loaded machine**: structural, not timed.
    ///
    /// If the live plan touched anything below the watermark, this number would be
    /// proportional to the settled count instead of to the tail. It is the actual proof of
    /// ADR-009's "only the live tail redrawn"; the timings below are the corroboration, and
    /// they are the parts a slow CI box can perturb.
    @Test("the live plan touches only the live window",
          arguments: [5_000, 20_000, 50_000])
    func theLivePlanTouchesOnlyTheLiveWindow(_ settled: Int) {
        let plan = StitchDrawPlan.live(of: list(settled: settled))
        let segments = plan.strokes.reduce(0) { $0 + $1.segmentStarts.count }
        let dots = plan.dots.reduce(0) { $0 + $1.indices.count }
        // The tail's own dots, and one segment more than the tail's segments: the live plan
        // deliberately starts one segment *earlier* than the dots do, because the segment
        // straddling the watermark belongs to neither window under the obvious reading and
        // would leave a permanent gap in the thread.
        #expect(dots == Self.tail)
        // **Bounded on both sides.** `<=` alone was one-sided, and this is the assertion
        // ADR-029 quotes as *the* discriminating test of ADR-009's claim: dots and strokes
        // come from two independent loops, so a `strokes(for:of:within:)` that returned `[]`
        // would give `segments == 0` and sail through an upper bound.
        #expect(
            segments >= Self.tail,
            "\(segments) segments for a \(Self.tail)-stitch tail — the stroke loop produced nothing"
        )
        #expect(segments <= Self.tail + 1)
    }

    @Test("the live plan costs the same at five thousand and fifty thousand settled")
    func theLivePlanCostsTheSameAtFiveThousandAndFiftyThousandSettled() {
        let small = list(settled: 5_000)
        let large = list(settled: 50_000)

        let smallTime = fastest { blackHole(StitchDrawPlan.live(of: small)) }
        let largeTime = fastest { blackHole(StitchDrawPlan.live(of: large)) }
        let ratio = seconds(largeTime) / seconds(smallTime)

        #expect(
            ratio <= 1.25,
            """
            a 10× settled count cost \(String(format: "%.2f", ratio))× the per-frame planning \
            (5 000: \(milliseconds(smallTime)), 50 000: \(milliseconds(largeTime)))
            """
        )
    }

    /// The half AC4 omits, asserted as a *dependence* rather than an independence.
    ///
    /// Stated as a **bound** rather than a bare inequality so it cannot pass on noise. The
    /// earlier version claimed a bound in its comment and asserted only `>`, which two
    /// adjacent noisy timings satisfy half the time.
    ///
    /// **The bound is set from a re-measurement, and the first attempt at it was refuted.**
    /// `swift-code-reviewer` proposed `>= 10` on the strength of the "300× spread" this
    /// suite's own header quoted; the test measures **6.0×**, because the header's 300× is
    /// the *50 000*-run case and this comparison builds 1 000. A figure in prose that names
    /// no fixture is how a reviewer is led to a constant the code cannot meet — so both
    /// cases are now measured here, and the discriminating one is the extreme AC4 names.
    ///
    /// Re-measured (release, M-series Mac, `fastest`): **1 run 0.041 ms · 1 000 runs
    /// 0.246 ms (6.0×) · 50 000 runs 9.791 ms (239×)**.
    @Test("the live plan grows with colour runs, not with stitch count")
    func theLivePlanGrowsWithColourRunsNotWithStitchCount() {
        let oneRun = list(settled: 50_000, colorRuns: 1)
        let manyRuns = list(settled: 50_000, colorRuns: 1_000)
        // A colour change on every stitch: `colorRuns == count`, which is the case that makes
        // AC4's "independent of total stitch count" false as written.
        let everyStitch = list(settled: 50_000, colorRuns: 50_000)

        let oneRunTime = fastest { blackHole(StitchDrawPlan.live(of: oneRun)) }
        let manyRunsTime = fastest { blackHole(StitchDrawPlan.live(of: manyRuns)) }
        let everyStitchTime = fastest { blackHole(StitchDrawPlan.live(of: everyStitch)) }

        let thousandFold = seconds(manyRunsTime) / seconds(oneRunTime)
        let perStitch = seconds(everyStitchTime) / seconds(oneRunTime)

        // The discriminating assertion: 239× measured, bounded at 50, so a loaded CI box has
        // most of an order of magnitude of slack and a removed run walk still cannot pass.
        #expect(
            perStitch >= 50,
            """
            a colour change per stitch planned in \(milliseconds(everyStitchTime)) against \
            \(milliseconds(oneRunTime)) for one run — ratio \
            \(String(format: "%.1f", perStitch)), measured at 239×. If these are comparable, \
            the run walk has been removed and this criterion no longer describes the code
            """
        )
        // Monotone in between, which is what makes it the run count rather than a threshold.
        #expect(
            thousandFold >= 2.5,
            """
            1 000 colour runs: \(milliseconds(manyRunsTime)) against \
            \(milliseconds(oneRunTime)), ratio \(String(format: "%.2f", thousandFold))
            """
        )
    }

    /// The mid-gesture path, measured rather than worried about.
    ///
    /// ADR-028's correction removed the blit AC5 asks to tune: while a gesture is live
    /// `StageRenderTransform.canUseRaster` is false, so the renderer takes the
    /// `.entire(of:)` branch **every frame** and re-strokes the whole design. This records
    /// what that costs as a number, so the device session knows which capture is the one at
    /// risk. Deliberately not bounded — the bound belongs to the device, and a wall-clock
    /// ceiling here would be a flake.
    @Test("the entire plan is linear in stitch count, and that is the mid-gesture cost")
    func theEntirePlanIsLinearInStitchCount() {
        let small = list(settled: 5_000)
        let large = list(settled: 50_000)

        let smallTime = fastest { blackHole(StitchDrawPlan.entire(of: small)) }
        let largeTime = fastest { blackHole(StitchDrawPlan.entire(of: large)) }
        let ratio = seconds(largeTime) / seconds(smallTime)

        #expect(
            ratio >= 4,
            """
            the mid-gesture full re-stroke is expected to scale with the design: \
            5 000 → \(milliseconds(smallTime)), 50 000 → \(milliseconds(largeTime)), \
            ratio \(String(format: "%.2f", ratio))
            """
        )
    }

    /// `settled` stitches below the watermark and exactly `tail` above it.
    private func list(settled: Int, colorRuns: Int = 1) -> StitchDisplayList {
        var list = SyntheticDesign.displayList(count: settled + Self.tail, colorRuns: colorRuns)
        list.markSettled(upTo: settled)
        return list
    }
}
