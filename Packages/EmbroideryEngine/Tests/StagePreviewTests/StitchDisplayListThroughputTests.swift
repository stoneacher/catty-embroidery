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
///   minute-granularity net and nothing finer. **And it is a weaker net than it looks**:
///   measured against the quadratic mutant, it records `Time limit was exceeded: 60.000
///   seconds` and then lets the synchronous body run to completion, more than ten further
///   minutes. It is kept as a backstop, but what actually keeps this suite fast under a
///   regression is `fastest(within:)`'s budget.
/// - `.serialized` orders tests *within* a suite; it does not buy exclusive CPU, so a bare
///   ceiling would be a flake generator on a loaded machine.
/// - The 5 k ↔ 50 k ratio the criterion's wording suggests is **floor-limited**: at 5 k the
///   cost is dominated by allocation constants, so in a release build that ratio measures
///   3.7 against a linear prediction of 10 and tells you nothing.
/// - **The step is 16×, and the bound is the geometric mean of the two predictions.** For a
///   step of k, linear predicts k and quadratic predicts k², so the bound that is equally
///   far from both *in log space* — which is the space this question lives in — is k^1.5.
///   The first version used a 4× step and a bound of 8, leaving only a factor of two of
///   headroom in each direction, and **CI refuted it**: on the unmutated implementation the
///   hosted runner measured **9.62×** for a 4× step (6 250: 1.730 ms, 25 000: 16.653 ms)
///   where this machine measures 3.45–3.71× (0.88 ms → 3.27 ms). The per-element cost is
///   not constant across sizes on every machine — the larger buffer leaves cache — so a
///   wall-clock ratio conflates algorithmic complexity with the memory hierarchy unless the
///   step is wide enough to swamp it. At 16× the predictions are 16 and 256, the bound is
///   64, and even the runner's ~2.4× per-element inflation lands near 38.
/// - The anchors are also a **failure-mode** choice: the time a guard takes to go *red* is
///   set by how slow the bad implementation is, not by how fast the good one is. On the
///   quadratic mutant in a debug build — which is what `swift test` and the pre-commit gate
///   run — one 50 000-append run costs **~180 s** against 5.7 ms for the real
///   implementation, and ~45 s at 25 600. So the discriminating assertions are made where a
///   regression announces itself in under a minute, and the criterion's own literal 50 000
///   figure is kept below as a ceiling that is simply slower to go red.
///
/// A rescanning `append` measures a ratio in the thousands at this step, against a bound of
/// 64 and a healthy 16.
@Suite("US-309 display-list throughput", .serialized, .timeLimit(.minutes(1)))
struct StitchDisplayListThroughputTests {
    /// The batch size the criterion names: 50 000 stitches in 1 000 batches.
    private static let batchCount = 1_000

    @Test("appending is linear in stitch count, not quadratic")
    func appendingIsLinearInStitchCount() {
        let small = batches(of: 1_600)
        let large = batches(of: 25_600)

        let smallTime = fastest { appendAll(small) }
        let largeTime = fastest { appendAll(large) }
        let ratio = seconds(largeTime) / seconds(smallTime)

        #expect(
            ratio <= 64,
            """
            a 16× stitch count cost \(String(format: "%.2f", ratio))× the time \
            (1 600: \(milliseconds(smallTime)), 25 600: \(milliseconds(largeTime))) — \
            linear is 16, quadratic is 256
            """
        )
    }

    /// The criterion's literal shape, kept as a **second and deliberately generous net**.
    ///
    /// The ceiling is more than an order of magnitude above the measured debug cost (5.7 ms),
    /// so it cannot flake on a loaded machine. It exists because a ratio alone would stay
    /// green if *both* anchors regressed by the same factor.
    ///
    /// **This is the slow one, and deliberately so.** A rescanning `append` takes ~180 s to
    /// reach this assertion — the regression's own cost, not the guard's — where the ratio
    /// tests above are red inside a minute. It is kept at 50 000 because that is the figure
    /// AC6 names, and a guard that asserts at a smaller scale than the criterion is a guard
    /// for a different criterion.
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
        let small = batches(of: 1_600, colorRuns: 128)
        let large = batches(of: 25_600, colorRuns: 2_048)

        let smallTime = fastest { appendAll(small) }
        let largeTime = fastest { appendAll(large) }
        let ratio = seconds(largeTime) / seconds(smallTime)

        #expect(
            ratio <= 64,
            """
            a 16× stitch count at a 16× run count cost \(String(format: "%.2f", ratio))× the \
            time (\(milliseconds(smallTime)) → \(milliseconds(largeTime))) — \
            linear is 16, quadratic is 256
            """
        )
    }

    // MARK: - Fixtures

    /// The stitches, pre-built and pre-split, so the measurement times `append` and not the
    /// fixture: building the stitches costs more than appending them.
    ///
    /// **`SyntheticDesign.stitches`, never `SyntheticDesign.displayList`** — the fixture must
    /// not be produced by the function under guard, or a regression in that function makes
    /// the *setup* pathological and the suite hangs before it can assert anything. Measured
    /// on the quadratic mutant: 400 s without reaching an assertion.
    private func batches(of count: Int, colorRuns: Int = 1) -> [[PreviewStitch]] {
        let stitches = SyntheticDesign.stitches(count: count, colorRuns: colorRuns)
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
