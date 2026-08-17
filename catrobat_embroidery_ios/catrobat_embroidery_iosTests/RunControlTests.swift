@testable import catrobat_embroidery_ios
import Foundation
import StagePreview
import Testing

/// The transport button's title, symbol and enablement per run state.
///
/// This is the only way the story's "accessibility labels that change with state"
/// criterion is checkable: nothing can read a rendered `Button`'s label back out of a
/// hosted view, and a screenshot cannot show what VoiceOver would say.
@Suite("Run control")
struct RunControlTests {
    @Test("with no design selected the control is disabled")
    func withNoSelectionTheControlIsDisabled() {
        #expect(!RunControl.appearance(for: .idle, hasSelection: false).isEnabled)
    }

    @Test("with a design selected every state offers an enabled control",
          arguments: [
              RunState.idle,
              .running,
              .finished(.programFinished),
              .finished(.stoppedByUser)
          ])
    func everyStateOffersAnEnabledControl(_ state: RunState) {
        #expect(RunControl.appearance(for: state, hasSelection: true).isEnabled)
    }

    /// The three titles must be **pairwise distinct**, which is the substance of the
    /// criterion. A mapping that returned "Play" for both `.idle` and `.finished` would
    /// leave a VoiceOver user unable to tell a design that has not run from one that
    /// has — and it would pass a test that only checked each label was non-empty.
    @Test("idle, running and finished have pairwise distinct titles")
    func theThreeStatesHaveDistinctTitles() {
        let titles = [RunState.idle, .running, .finished(.programFinished)].map {
            String(localized: RunControl.appearance(for: $0, hasSelection: true).title)
        }

        #expect(Set(titles).count == 3, "two run states share a title: \(titles)")
        #expect(titles.allSatisfy { !$0.isEmpty })
    }

    /// Every completion reason keeps the finished title, because all three mean the
    /// same thing to the button: the run is over and pressing it starts a new one.
    @Test("all three completion reasons share the finished title")
    func allCompletionReasonsShareTheFinishedTitle() {
        let titles = [RunCompletion.programFinished, .stoppedByUser, .stitchLimitReached].map {
            String(localized: RunControl.appearance(for: .finished($0), hasSelection: true).title)
        }

        #expect(Set(titles).count == 1)
    }

    @Test("running shows a stop symbol and the others a play symbol")
    func theSymbolsMatchTheState() {
        let running = RunControl.appearance(for: .running, hasSelection: true)
        let idle = RunControl.appearance(for: .idle, hasSelection: true)
        let finished = RunControl.appearance(for: .finished(.programFinished), hasSelection: true)

        #expect(running.symbol != idle.symbol)
        #expect(idle.symbol.contains("play"))
        #expect(finished.symbol.contains("play"))
        #expect(running.symbol.contains("stop"))
    }
}
