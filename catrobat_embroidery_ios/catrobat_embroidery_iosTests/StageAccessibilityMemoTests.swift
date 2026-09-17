@testable import catrobat_embroidery_ios
import Foundation
import StagePreview
import Testing

/// US-313b AC10: the stage's spoken strings are computed once per distinct state, not once per
/// body evaluation.
///
/// **ADR-028 deferred this to US-309 and US-309 did not take it.** Every body evaluation
/// rebuilds the label, the hint and the value, and the value runs `Measurement.FormatStyle`
/// twice with a `.wide` unit style — tens of microseconds, on the path US-310 ground down to a
/// 16.667 ms median. This story is what makes that path hot, so this story takes it.
///
/// **Two corrections to the story's specification, both load-bearing.**
///
/// 1. Its key — `(summary, state, roundedPercent)` — omits `designName`, which the *label*
///    depends on. A memo whose key does not determine its output is unsound whether or not the
///    missing input can currently change; today it is safe only by a cross-file accident (the
///    name comes from the selected sample, and selecting resets the run, which removes the
///    canvas), which is an invariant, not a construction.
/// 2. Keying the *whole* memo on the zoom percentage would make it miss on nearly every frame
///    of a pinch — the one path it is bought for. The percentage is the only part that changes
///    per frame, and it is also the cheap part. So the keys are **split**: the expensive
///    description on `(summary, state)`, which is constant for a whole manipulation; the label
///    on `designName`; and only the zoom phrase recomputed per call.
@MainActor
@Suite("Stage accessibility memo")
struct StageAccessibilityMemoTests {
    private static let finished = StageSummary(
        stitchCount: 3194, colorCount: 1, widthInMillimetres: 98.6, heightInMillimetres: 98.6
    )
    /// One set of inputs. A named type rather than a tuple: four positional components is
    /// where a copy-paste swaps two of them, and it is over SwiftLint's cap anyway.
    private struct Reading {
        let name: String?
        let summary: StageSummary
        let state: RunState
        let magnification: Double
    }

    private static let larger = StageSummary(
        stitchCount: 50001, colorCount: 2, widthInMillimetres: 120.4, heightInMillimetres: 84.2
    )

    /// The pinch path, which is the whole point: the magnification changes every frame and the
    /// expensive half must not follow it.
    @Test func theDescriptionIsComputedOncePerManipulationRatherThanPerFrame() {
        let memo = StageAccessibilityMemo()
        let zooms = [1.0, 1.04, 1.31, 2.7, 3.02]

        let spoken = zooms.map {
            memo.strings(
                designName: "OctagonRosette",
                summary: Self.finished,
                state: .finished(.programFinished),
                magnification: $0
            )
        }

        #expect(memo.descriptionComputations == 1, "the expensive half followed the zoom")
        #expect(memo.labelComputations == 1)
        // …and the zoom itself is still live, or the memo would be caching the wrong thing.
        #expect(Set(spoken.map(\.value)).count == zooms.count)
        #expect(Set(spoken.map(\.label)).count == 1)
    }

    /// Without this, a memo that computes once and never invalidates passes the test above.
    @Test func aChangedSummaryRecomputesTheDescription() {
        let memo = StageAccessibilityMemo()
        let state = RunState.finished(.programFinished)

        let first = memo.strings(
            designName: "A", summary: Self.finished, state: state, magnification: 1
        )
        let second = memo.strings(
            designName: "A", summary: Self.larger, state: state, magnification: 1
        )

        #expect(memo.descriptionComputations == 2)
        #expect(first.value != second.value)
    }

    /// The run state is the other half of the description's key, and it is what turns "3,194
    /// stitches" into "Stitching." — so a memo ignoring it would speak counts during a run,
    /// which is the criterion ADR-028 spent a correction on.
    @Test func aChangedRunStateRecomputesTheDescriptionAndTheHint() {
        let memo = StageAccessibilityMemo()

        let running = memo.strings(
            designName: "A", summary: Self.finished, state: .running, magnification: 1
        )
        let finished = memo.strings(
            designName: "A", summary: Self.finished, state: .finished(.programFinished),
            magnification: 1
        )

        #expect(memo.descriptionComputations == 2)
        #expect(running.value != finished.value)
        #expect(running.hint != finished.hint)
    }

    /// The key the story omitted. A design name change with everything else equal must move the
    /// label — otherwise the stage announces the previous design.
    @Test func aChangedDesignNameRecomputesTheLabel() {
        let memo = StageAccessibilityMemo()
        let state = RunState.finished(.programFinished)

        let first = memo.strings(
            designName: "OctagonRosette", summary: Self.finished, state: state, magnification: 1
        )
        let second = memo.strings(
            designName: "SquareCoil", summary: Self.finished, state: state, magnification: 1
        )
        let anonymous = memo.strings(
            designName: nil, summary: Self.finished, state: state, magnification: 1
        )

        #expect(memo.labelComputations == 3)
        #expect(first.label != second.label)
        #expect(second.label != anonymous.label)
        // The description was untouched by any of it — the two keys really are separate.
        #expect(memo.descriptionComputations == 1)
    }

    /// **What keeps the counters honest.** Counting computations proves a cache exists; it does
    /// not prove the cache returns the right thing, and an implementation that memoises a stale
    /// string passes every assertion above. So the memo is compared against the uncached
    /// functions it is a cache *of*, across the states that matter — including two consecutive
    /// reads of the same state, where a cache that returned its key instead of its value would
    /// still be caught.
    @Test func theMemoAgreesWithTheUncachedStringsInEveryState() {
        let memo = StageAccessibilityMemo()
        let cases: [Reading] = [
            Reading(
                name: "OctagonRosette", summary: Self.finished,
                state: .finished(.programFinished), magnification: 1
            ),
            Reading(
                name: "OctagonRosette", summary: Self.finished,
                state: .finished(.programFinished), magnification: 2.5
            ),
            Reading(
                name: "OctagonRosette", summary: Self.finished,
                state: .running, magnification: 2.5
            ),
            Reading(
                name: nil, summary: Self.larger,
                state: .finished(.stoppedByUser), magnification: 0.4
            ),
            Reading(
                name: nil, summary: Self.larger,
                state: .finished(.stoppedByUser), magnification: 0.4
            )
        ]

        for reading in cases {
            let cached = memo.strings(
                designName: reading.name,
                summary: reading.summary,
                state: reading.state,
                magnification: reading.magnification
            )

            #expect(cached.label == StageAccessibility.label(designName: reading.name))
            #expect(cached.hint == StageAccessibility.hint(for: reading.state))
            #expect(cached.value == StageAccessibility.value(
                summary: reading.summary,
                state: reading.state,
                magnification: reading.magnification
            ))
        }
    }
}
