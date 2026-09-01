import StagePreview
import Testing

/// US-309 AC6: the headless throughput guard.
///
/// **What this catches is an accidental O(n²) in `colorRuns`/`bounds` maintenance** — the
/// realistic regression, since `append` is the one function in the preview whose cost is
/// paid once per stitch and whose current O(1) is enforced by nothing but a doc comment
/// (`StitchDisplayList.swift`, "nothing here may scan `stitches` or `colorRuns`"). It runs
/// on the pre-commit gate, unlike the device measurement, which is the point: the device
/// number is taken once and the shape has to be defended on every commit.
///
/// **The assertion is a ratio between two large anchors, not a wall-clock ceiling**, and
/// that shape was chosen by measurement rather than taste:
///
/// - An absolute bound is not expressible as a trait. `TimeLimitTrait.Duration.seconds` is
///   `@available(*, unavailable)` — the compiler says so — so `.timeLimit` is a
///   minute-granularity hang net and nothing finer. It is applied below as exactly that.
/// - `.serialized` orders tests *within* a suite; it does not buy exclusive CPU, so a bare
///   ceiling would be a flake generator on a loaded machine.
/// - The 5 k ↔ 50 k ratio the criterion's wording suggests is **floor-limited**: at 5 k the
///   cost is dominated by allocation constants, so in a release build that ratio measures
///   3.7 against a linear prediction of 10 and tells you nothing. Between two large
///   anchors it behaves: 25 k → 100 k measures **4.00** against a linear 4 and a quadratic
///   16.
///
/// The bound is therefore 8 — a factor of two clear of linear in one direction and of
/// quadratic in the other. A rescanning `append` measures 16.4.
@Suite("US-309 display-list throughput", .serialized, .timeLimit(.minutes(1)))
struct StitchDisplayListThroughputTests {
    /// The batch size the criterion names: 50 000 stitches in 1 000 batches.
    private static let batchCount = 1_000

    @Test("appending is linear in stitch count, not quadratic")
    func appendingIsLinearInStitchCount() {
        let small = batches(of: 25_000)
        let large = batches(of: 100_000)

        let smallTime = fastest { appendAll(small) }
        let largeTime = fastest { appendAll(large) }
        let ratio = seconds(largeTime) / seconds(smallTime)

        #expect(
            ratio <= 8,
            """
            a 4× stitch count cost \(String(format: "%.2f", ratio))× the time \
            (25 000: \(milliseconds(smallTime)), 100 000: \(milliseconds(largeTime))) — \
            linear is 4, quadratic is 16
            """
        )
    }

    /// The criterion's literal shape, kept as a **second and deliberately generous net**.
    ///
    /// The ceiling is two orders of magnitude above the measured debug cost (5.7 ms), so it
    /// cannot flake on a loaded machine; a rescanning `append` costs ~19 s here and fails it
    /// by a factor of 95. It exists because a ratio alone would stay green if *both*
    /// anchors regressed by the same factor.
    @Test("fifty thousand stitches in one thousand batches stays within the documented bound")
    func fiftyThousandStitchesInOneThousandBatchesStaysWithinTheBound() {
        let work = batches(of: 50_000)
        let elapsed = fastest { appendAll(work) }
        #expect(seconds(elapsed) <= 0.2, "50 000 in \(Self.batchCount) batches took \(milliseconds(elapsed))")
    }

    /// The same step, with the colour-run bookkeeping actually exercised.
    ///
    /// Without this the guard only covers the stitch array: a rescan introduced into the
    /// **run** maintenance path would be invisible at one colour run, because there is
    /// nothing to rescan.
    @Test("colour-run maintenance does not rescan")
    func colourRunMaintenanceDoesNotRescan() {
        let small = batches(of: 25_000, colorRuns: 500)
        let large = batches(of: 100_000, colorRuns: 2_000)

        let smallTime = fastest { appendAll(small) }
        let largeTime = fastest { appendAll(large) }
        let ratio = seconds(largeTime) / seconds(smallTime)

        #expect(
            ratio <= 8,
            """
            a 4× stitch count at a 4× run count cost \(String(format: "%.2f", ratio))× the time \
            (\(milliseconds(smallTime)) → \(milliseconds(largeTime)))
            """
        )
    }

    // MARK: - Fixtures

    /// The stitches, pre-built and pre-split, so the measurement times `append` and not the
    /// fixture: building 100 000 `PreviewStitch`es costs more than appending them.
    private func batches(of count: Int, colorRuns: Int = 1) -> [[PreviewStitch]] {
        let stitches = Array(SyntheticDesign.displayList(count: count, colorRuns: colorRuns).stitches)
        let size = max(1, count / Self.batchCount)
        return stride(from: 0, to: stitches.count, by: size).map {
            Array(stitches[$0 ..< min($0 + size, stitches.count)])
        }
    }

    private func appendAll(_ batches: [[PreviewStitch]]) {
        var list = StitchDisplayList()
        for batch in batches {
            list.append(contentsOf: batch)
        }
        // Read the result back so the optimiser cannot delete the work under test.
        blackHole(list.count)
    }
}

/// Keeps a computed value observably alive.
///
/// Every benchmark here builds a value and discards it; without a consumer the optimiser is
/// entitled to delete the loop that built it and the test would measure nothing while
/// passing. `@inline(never)` is what makes that guarantee, not the function body.
@inline(never)
func blackHole(_ value: some Any) {
    _ = value
}
