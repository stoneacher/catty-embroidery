import EmbroideryEngine
import Foundation
import Testing

/// Self-test for the ADR-019 screen's measuring instrument.
///
/// `compensatedMagnitude` is what decides whether a sample sits inside half an
/// ulp of a `floor(distance / length)` boundary, so every number the screening
/// reports — sample 1's seven libm-decided sides, sample 2's 5.2e13 ulps of
/// margin — is only as trustworthy as this function. An instrument that is never
/// calibrated is not evidence.
@Suite("Compensated magnitude")
struct CompensatedMagnitudeTests {
    /// When the true magnitude is exactly representable, the compensated result
    /// must *be* it, with a zero tail. Pythagorean triples give exact cases with
    /// no appeal to a higher-precision reference — which matters here, because
    /// `Float80` does not exist on arm64 and the whole point is to avoid
    /// measuring libm with libm.
    @Test("exact on Pythagorean triples, with a zero tail",
          arguments: [(3.0, 4.0, 5.0), (5.0, 12.0, 13.0), (20.0, 21.0, 29.0),
                      (9.0, 40.0, 41.0), (65.0, 72.0, 97.0)])
    func exactOnPythagoreanTriples(_ dx: Double, _ dy: Double, _ expected: Double) {
        let (head, tail) = compensatedMagnitude(dx, dy)
        #expect(head == expected)
        #expect(tail == 0)
    }

    /// Scaling both legs by a power of two scales the magnitude exactly — no new
    /// rounding is introduced — so the identity must hold bit for bit. This
    /// catches an error term that is right at unit scale and wrong elsewhere,
    /// which a triple test alone would miss.
    @Test("scales exactly by powers of two", arguments: [-40, -8, 0, 8, 40])
    func scalesByPowersOfTwo(_ exponent: Int) {
        let scale = exp2(Double(exponent))
        let (head, tail) = compensatedMagnitude(3 * scale, 4 * scale)
        #expect(head == 5 * scale)
        #expect(tail == 0)
    }

    /// Agreement with libm to within one ulp across the magnitudes the samples
    /// actually visit. This is a sanity bound, not a correctness proof — libm is
    /// the thing under test — but a compensated value that disagreed with `hypot`
    /// by more than an ulp would mean the compensation itself is broken, since
    /// Darwin's error on these operands is measured in fractions of one.
    @Test("agrees with libm to within an ulp over the samples' range")
    func agreesWithLibmWithinAnUlp() {
        // A deterministic spread — no Double.random, because a test that samples
        // a different set each run reports a different fact each run.
        var worstUlps = 0.0
        for step in 1 ... 400 {
            let dx = Double(step) * 0.7357
            let dy = Double(401 - step) * 1.3179
            let (head, tail) = compensatedMagnitude(dx, dy)
            let reference = hypot(dx, dy)
            let difference = abs((head - reference) + tail) / reference.ulp
            worstUlps = max(worstUlps, difference)
        }
        #expect(worstUlps < 1, "worst disagreement with libm: \(worstUlps) ulps")
    }

    /// The along/perpendicular split, pinned on the one case where the correct
    /// formula and the wrong one disagree.
    ///
    /// This is Codex round 1's counterexample, kept as a test because round 2
    /// pointed out that nothing else can catch a regression here: within the
    /// samples' small-angle regime the true remainder `q²/(d + p)` and the
    /// discarded approximation `q²/(2B)` agree to many digits, since `d ≈ p ≈ B`.
    /// Only a large perpendicular component separates them — so the guard has to
    /// be a synthetic case, not a sample.
    ///
    /// `(0,0) → (3,4)` at heading 0 against stitch length 5: the projection onto
    /// the heading is 4, the boundary is 5, so the along component is **−1** and
    /// the perpendicular remainder is **+1**. The old formula reported −0.9 / 0.9.
    @Test("the residue decomposition is exact where the small-angle form is not")
    func decompositionIsNotTheSmallAngleApproximation() {
        let probe = boundaryProbe(
            moveIndex: 0,
            from: StagePoint(x: 0, y: 0),
            to: StagePoint(x: 3, y: 4),
            heading: 0,
            length: 5
        )
        #expect(probe.distance == 5)
        #expect(probe.intervals == 1)
        #expect(abs(probe.alongComponent - -1) < 1e-12, "along \(probe.alongComponent), expected -1")
        #expect(abs(probe.perpendicularContribution - 1) < 1e-12,
                "perpendicular \(probe.perpendicularContribution), expected 1")

        // What the discarded approximation would have said, spelled out so the
        // difference is visible rather than asserted from memory: q²/(2B) with
        // q = 3 and B = 5 is 0.9, not 1.
        #expect(abs(probe.perpendicularContribution - 0.9) > 0.05)
    }

    /// The tail must actually carry information. Without this, a
    /// `compensatedMagnitude` that returned `(hypot(dx, dy), 0)` would satisfy
    /// every other test in this suite while measuring nothing at all — and the
    /// screen would then be measuring libm with libm.
    ///
    /// The property is checked **as an unevaluated sum**, not by adding the two
    /// together. `head + tail` rounds straight back to `head` whenever the head is
    /// already correctly rounded, which for √2 it is — so comparing the rounded
    /// sum against the head is vacuous, and an earlier version of this test that
    /// did exactly that passed against any tail whatsoever.
    ///
    /// Instead: `fma` gives `head² − 2` exactly, and the first-order effect of the
    /// tail on the square is `2 · head · tail`. If the tail points the right way
    /// and has the right size, adding that term must shrink the residual.
    @Test("the tail improves on the head for an inexact magnitude")
    func tailCarriesInformation() {
        // √2 is irrational, so no Double is exact and the tail must be non-zero.
        let (head, tail) = compensatedMagnitude(1.0, 1.0)
        #expect(tail != 0, "a zero tail here means the compensation is not running")

        let residual = (-2.0).addingProduct(head, head) // head² − 2, exact
        let corrected = residual.addingProduct(2 * head, tail) // + 2·head·tail
        #expect(abs(corrected) < abs(residual), "residual \(residual) → \(corrected)")
    }
}
