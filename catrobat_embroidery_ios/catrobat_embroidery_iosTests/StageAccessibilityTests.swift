@testable import catrobat_embroidery_ios
import Foundation
import StagePreview
import Testing

/// US-307 criteria 5, 6 and 7, at the layer that can actually be asserted.
///
/// **Nothing here asserts English wording**, following `AppStringsTests`' standing rule for a
/// repo shipping ~75 languages through Crowdin: what is pinned is structure — which facts
/// reach the string, that the parts survive substitution, and that the three run states are
/// distinguishable. The *numbers* are pinned in the package by `StageSummaryTests`, and the
/// catalog's plural forms in `AppStringsTests`.
///
/// This exists as a value mapping rather than as modifiers on a view for the reason
/// `RunControl` already records: nothing can read a rendered accessibility value back, so a
/// criterion asserted only through `.accessibilityValue(…)` would have no test at all.
@Suite("Stage accessibility")
struct StageAccessibilityTests {
    private static let finished = StageSummary(
        stitchCount: 3194, colorCount: 1, widthInMillimetres: 98.6, heightInMillimetres: 98.6
    )

    // MARK: - Label

    @Test func theLabelNamesTheDesignWhenThereIsOne() {
        let named = StageAccessibility.label(designName: "Octagon Rosette")
        let anonymous = StageAccessibility.label(designName: nil)

        #expect(named.contains("Octagon Rosette"))
        #expect(!anonymous.contains("Octagon Rosette"))
        #expect(named != anonymous)
        #expect(!anonymous.isEmpty)
    }

    /// An empty name must fall back rather than produce "Embroidery stage, " with a dangling
    /// separator. Reachable if a sample ever ships without a localized name.
    @Test func anEmptyNameFallsBackToThePlainLabel() {
        #expect(StageAccessibility.label(designName: "") == StageAccessibility.label(designName: nil))
    }

    // MARK: - Value

    /// Criterion 5's content, checked by what reaches the string rather than by its wording:
    /// a finished design's value carries its stitch count, its colour count and both sizes.
    ///
    /// **The digits are asserted locale-independently, and the first version of this test was
    /// not.** It expected `"3,194"` or `"3194"` and `"98.6"`; the simulator renders
    /// `"3.194 stitches, 1 colour, 98,6 millimetres by 98,6 millimetres"` — English words with
    /// **German number formatting**, because its language and its region are set separately.
    /// Asserting a grouping or decimal separator is asserting a region, which is exactly what
    /// `AppStringsTests` refuses to do. So what is pinned is the digit *runs*, which survive
    /// any separator: "194" from 3194, and "98" twice for the two axes.
    @Test func theFinishedValueCarriesTheCountsAndBothSizes() {
        let value = StageAccessibility.value(
            summary: Self.finished, state: .finished(.programFinished), magnification: 1
        )

        #expect(value.contains("194"), value.asComment)
        // Both dimensions, not one: a size phrase that dropped an axis would still mention 98
        // once. Sample 1 is square, so the two occurrences are the check.
        #expect(value.components(separatedBy: "98").count == 3, value.asComment)
        #expect(value.contains { $0.isLetter }, "the entry collapsed to its arguments")
    }

    /// **The resolution of criteria 5 and 6's contradiction**, asserted rather than left in a
    /// comment: a running stage does not claim a stitch count, because the only count it
    /// could have — the one captured at `idle → running` — is zero for the whole run.
    @Test func theRunningValueCarriesNoCounts() {
        let value = StageAccessibility.value(
            summary: .empty, state: .running, magnification: 1
        )

        #expect(!value.contains("0"))
        #expect(!value.contains { $0.isNumber })
        #expect(value.contains { $0.isLetter })
    }

    @Test func theRunningAndFinishedValuesAreDifferent() {
        let running = StageAccessibility.value(summary: .empty, state: .running, magnification: 1)
        let finished = StageAccessibility.value(
            summary: Self.finished, state: .finished(.stoppedByUser), magnification: 1
        )

        #expect(running != finished)
    }

    /// A running run's value must not depend on the summary at all — otherwise a summary that
    /// *did* update per batch would leak into the spoken value even though the state had not
    /// changed, which is the criterion's failure mode arriving by a side door.
    @Test func theRunningValueIgnoresTheSummaryEntirely() {
        let empty = StageAccessibility.value(summary: .empty, state: .running, magnification: 1)
        let full = StageAccessibility.value(summary: Self.finished, state: .running, magnification: 1)

        #expect(empty == full)
    }

    // MARK: - Zoom

    /// At the fit there is no zoom phrase, so the value stays clean until the user acts.
    @Test func aFittedStageSaysNothingAboutZoom() {
        let fitted = StageAccessibility.value(
            summary: Self.finished, state: .finished(.programFinished), magnification: 1
        )
        let zoomed = StageAccessibility.value(
            summary: Self.finished, state: .finished(.programFinished), magnification: 3
        )

        #expect(zoomed != fitted)
        // **The changed part comes first and the description survives after it**, which is
        // what lets a VoiceOver user hear the zoom and swipe past the rest. Containment
        // rather than a prefix check, because the composition order is a translator's to
        // change.
        #expect(zoomed.contains(fitted))
        #expect(zoomed.count > fitted.count)
    }

    /// Criterion 7 depends on this: VoiceOver re-reads the *value* after an adjustable
    /// action, so two different zoom levels must produce two different values or the action
    /// gives no feedback at all.
    @Test func differentZoomLevelsProduceDifferentValues() {
        let states: [RunState] = [.running, .finished(.programFinished)]
        for state in states {
            let doubled = StageAccessibility.value(
                summary: Self.finished, state: state, magnification: 2
            )
            let tripled = StageAccessibility.value(
                summary: Self.finished, state: state, magnification: 3
            )

            #expect(doubled != tripled, "zoom must be audible in \(state)")
        }
    }

    /// Rounded to whole per cent *before* the comparison, so a value that would speak
    /// "Zoom 100 per cent" is treated as fitted rather than contradicting itself.
    @Test func aMagnificationThatRoundsToOneHundredPerCentReadsAsFitted() {
        let fitted = StageAccessibility.value(
            summary: Self.finished, state: .finished(.programFinished), magnification: 1
        )

        #expect(
            StageAccessibility.value(
                summary: Self.finished, state: .finished(.programFinished), magnification: 1.004
            ) == fitted
        )
    }

    /// Total for the magnifications a degenerate fit can produce, rather than speaking a NaN.
    @Test func aNonFiniteMagnificationIsSimplyNotSpoken() {
        let fitted = StageAccessibility.value(
            summary: Self.finished, state: .finished(.programFinished), magnification: 1
        )

        for magnification in [Double.nan, .infinity, 0, -2] {
            #expect(
                StageAccessibility.value(
                    summary: Self.finished,
                    state: .finished(.programFinished),
                    magnification: magnification
                ) == fitted,
                "magnification \(magnification) must not reach the value"
            )
        }
    }

    // MARK: - Hint

    /// Criterion 5 asks the hint to describe the run state as well as the actions, so a
    /// running stage and a stopped one must be distinguishable rather than one string reused.
    ///
    /// **Two hints, not three**, and the earlier three-way version is why this comment exists:
    /// it asserted `.idle` was distinct, which kept a catalog entry alive that no user can
    /// ever hear — the canvas only exists once something is drawn, and the only route to
    /// `.idle` clears the display on the way (`swift-code-reviewer`). A test can keep dead
    /// copy alive just as easily as it can pin live behaviour.
    @Test func theHintDistinguishesARunningStageFromAStoppedOne() {
        let running = StageAccessibility.hint(for: .running)
        let finished = StageAccessibility.hint(for: .finished(.programFinished))

        #expect(running != finished)
        #expect(!running.isEmpty)
        #expect(!finished.isEmpty)
        // `.idle` is unreachable on the drawn canvas, so it shares the stopped hint rather
        // than owning copy of its own.
        #expect(StageAccessibility.hint(for: .idle) == finished)
    }

    /// The completion reason is a *notice* on screen, not a difference in what the stage can
    /// do — so all three finished reasons share one hint rather than inventing copy for each.
    @Test func everyFinishedReasonSharesOneHint() {
        let reasons: [RunCompletion] = [.programFinished, .stoppedByUser, .stitchLimitReached]
        let hints = Set(reasons.map { StageAccessibility.hint(for: .finished($0)) })

        #expect(hints.count == 1)
    }
}

private extension String {
    /// The rendered string as a failure message, so a locale-dependent surprise names itself
    /// instead of only reporting `false`. The German-formatted digits that broke the first
    /// version of `theFinishedValueCarriesTheCountsAndBothSizes` cost a round trip precisely
    /// because the failure did not show what had been produced.
    var asComment: Comment {
        Comment(rawValue: "rendered: \(self)")
    }
}
