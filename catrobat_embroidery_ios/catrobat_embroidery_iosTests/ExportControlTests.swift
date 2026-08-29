@testable import catrobat_embroidery_ios
import EmbroideryEngine
import Foundation
import StagePreview
import Testing

/// US-308's definition of done: **the disabled share affordance says *why*.**
///
/// A value rather than modifiers inside a view, for the reason `RunControl` records: nothing
/// can read a rendered `.accessibilityHint` back out of a hosted view, so a hint built inline
/// in `body` is checkable only by a screenshot — and a screenshot cannot show what VoiceOver
/// would say. Putting the mapping in a pure function is what gives the criterion a test at
/// all.
///
/// Two or more reasons can be true at once — no design selected *and* an empty name — so the
/// precedence is part of the contract and is asserted here rather than left to the order the
/// `if`s happen to be in.
@Suite("Export control")
struct ExportControlTests {
    // MARK: - Precedence

    /// Nothing selected outranks everything, including a perfectly good name.
    @Test("no selection outranks every other reason")
    func noSelectionWins() {
        #expect(
            Self.readiness(hasSelection: false, runState: .running, name: "Rose")
                == .noSelection
        )
    }

    /// **A run in flight outranks "not run", and the two must not be confused.** They share
    /// an `ExportEligibility` case — `exportModel` is `nil` throughout a run — so the run
    /// state is the only thing that can tell them apart, and a VoiceOver user mid-run would
    /// otherwise be told to press Play while the button beneath reads "Stop".
    @Test("a run in flight is distinct from never having run")
    func runningIsDistinctFromNotRun() throws {
        // Both pass `eligibility: .notRun`, because that is the *only* honest value while a
        // run is in flight or has never happened — `exportModel` is `nil` in both — and
        // pairing `.running` with `.ready` would assert against a state the engine cannot
        // produce.
        let running = Self.readiness(runState: .running, eligibility: .notRun, name: "Rose")
        let notRun = Self.readiness(runState: .idle, eligibility: .notRun, name: "Rose")

        #expect(running == .running)
        #expect(notRun == .notRun)
        #expect(try String(localized: #require(running.hint)) != String(localized: #require(notRun.hint)))
    }

    /// The run must be exportable before the name is judged: a name is only actionable once
    /// there is something to name. Reversing this would tell a user to fix their name while
    /// the design had not been run.
    @Test("run readiness is judged before the name")
    func runReadinessOutranksTheName() {
        let unrun = Self.readiness(runState: .idle, eligibility: .notRun, name: "")
        #expect(unrun == .notRun, "not .nameEmpty, though the name is empty too")
        #expect(unrun.hint != nil)
    }

    // MARK: - The engine's verdicts

    /// **The app collapses two of the engine's five verdicts into one sentence, and keeps the
    /// third distinct.** Zero stitches and one stitch are different facts — which is why
    /// `ExportEligibility` reports them separately, since the engine should not be deciding
    /// copy — but they are the same sentence to a user. `nothingEmbroiderable` is not, because
    /// it is the only one where something is visibly on screen.
    @Test("zero and one stitch read the same; a rejected design does not")
    func theEngineVerdictsMapToTwoSentences() throws {
        let none = Self.readiness(eligibility: .nothingStitched, name: "Rose")
        let one = Self.readiness(eligibility: .singleStitch, name: "Rose")
        let rejected = Self.readiness(eligibility: .nothingEmbroiderable, name: "Rose")

        #expect(none == .tooFewStitches)
        #expect(one == .tooFewStitches)
        #expect(rejected == .nothingEmbroiderable)
        #expect(try String(localized: #require(none.hint)) != String(localized: #require(rejected.hint)))
    }

    /// The story's own sentence for the divergence case, and the one place the export gate
    /// and the render empty-state legitimately disagree. Catty ships a valid-looking 515-byte
    /// header-plus-EOF file here; we say why instead.
    @Test("a rejected design gets a visible notice, not only a hint")
    func theRejectedDesignIsSaidOutLoud() throws {
        let rejected = Self.readiness(eligibility: .nothingEmbroiderable, name: "Rose")
        #expect(rejected.notice != nil)
        #expect(try String(localized: #require(rejected.notice)) == String(localized: #require(rejected.hint)))
    }

    // MARK: - The name

    @Test("an empty name and an invalid one are different reasons")
    func theTwoNameProblemsAreDistinct() throws {
        let empty = Self.readiness(name: "")
        let tooLong = Self.readiness(name: "1234567890123456")
        let nonASCII = Self.readiness(name: "Rösé")

        #expect(empty == .nameEmpty)
        #expect(tooLong == .nameInvalid)
        #expect(nonASCII == .nameInvalid)
        #expect(try String(localized: #require(empty.hint)) != String(localized: #require(tooLong.hint)))
    }

    // MARK: - Ready

    /// The only enabled state, and it carries the URL — so a view cannot construct a
    /// `ShareLink` for a file that was never prepared.
    @Test("ready is the only enabled state and it carries the URL")
    func readyCarriesTheURL() {
        let url = URL.temporaryDirectory.appending(path: "Rose.dst")
        let readiness = Self.readiness(name: "Rose", exportState: .ready(url))

        #expect(readiness == .ready(url))
        #expect(readiness.isEnabled)
        #expect(readiness.shareURL == url)
        #expect(readiness.hint == nil, "an enabled control explains itself")
    }

    /// **Everything else is disabled and everything else has a hint.**
    ///
    /// An earlier version of this comment claimed to assert "over the whole enum, so a tenth
    /// case cannot ship silently without one". **That was false and an in-loop review proved
    /// it** by adding a tenth case with a `nil` hint and watching this suite stay green:
    /// `Readiness` carries associated values, so it is not `CaseIterable`, and any list of it
    /// is hand-written. The list now lives on the type as `reasonsOwingAHint` rather than
    /// here, which does not make the omission impossible — it makes it visible next to the
    /// enum. Stated at its real strength, because overstating exactly this kind of claim is a
    /// finding class this repo counts.
    @Test("every disabled reason except a missing selection carries a hint")
    func everyDisabledReasonExplainsItself() {
        let url = URL.temporaryDirectory.appending(path: "Rose.dst")
        let all: [ExportControl.Readiness] =
            ExportControl.Readiness.reasonsOwingAHint + [.noSelection, .ready(url)]

        for readiness in all {
            switch readiness {
            case .ready:
                #expect(readiness.isEnabled)
                #expect(readiness.hint == nil)
            case .noSelection:
                // The control is not rendered at all when nothing is selected, so a hint
                // would be copy for an unreachable state — the mistake ADR-028 undid.
                #expect(readiness.isEnabled == false)
                #expect(readiness.hint == nil)
            default:
                #expect(readiness.isEnabled == false)
                #expect(readiness.hint != nil, "\(readiness) has no hint")
            }
        }
    }

    /// Every hint resolves to real English rather than to its own key — the `≠ key` check
    /// `AppStringsTests` makes, applied to strings that are *only* ever spoken, where a
    /// screenshot could never catch the fallback.
    @Test("every hint resolves rather than falling back to its key")
    func everyHintResolves() {
        let readinesses = ExportControl.Readiness.reasonsOwingAHint
        var seen: Set<String> = []

        for readiness in readinesses {
            guard let hint = readiness.hint else {
                Issue.record("\(readiness) has no hint")
                continue
            }
            let text = String(localized: hint)
            #expect(text.contains("stage.export") == false, "\(readiness) fell back to a key")
            #expect(text.isEmpty == false)
            seen.insert(text)
        }

        // Distinctness in one assertion: seven reasons that say the same thing would be
        // seven reasons the user cannot tell apart.
        #expect(seen.count == readinesses.count, "two reasons share a sentence")
    }

    /// **A failed export is said out loud, not only spoken.** The acceptance criterion is
    /// that US-211's overflow surfaces "with the design still on screen" — so a sighted user
    /// needs the sentence *visibly*, not only in a VoiceOver hint. An in-loop review moved
    /// `.failed` into `notice`'s nil group and the whole 114-test suite stayed green, which
    /// is what this test now closes.
    @Test("a failed export gets a visible notice, not only a hint")
    func aFailureIsSaidOutLoud() throws {
        let readiness = ExportControl.Readiness.failed(.writeFailed)
        let notice = try #require(readiness.notice, "a failure with no visible explanation")
        #expect(String(localized: notice) == String(localized: try #require(readiness.hint)))
    }

    /// Every reason that carries a visible notice carries the *same* sentence as its hint,
    /// so the two can never drift — and the reasons that carry none are the ones the screen
    /// already explains.
    @Test("notices and hints never disagree")
    func noticesAgreeWithHints() throws {
        for readiness in ExportControl.Readiness.reasonsOwingAHint {
            guard let notice = readiness.notice else { continue }
            #expect(String(localized: notice) == String(localized: try #require(readiness.hint)))
        }
    }

    /// A failed export speaks the error's own message, so US-211's limit reaches the user
    /// through the control as well as through the notice.
    @Test("a failed export speaks the error's message")
    func aFailureSpeaksItsError() throws {
        let error = ExportError.serialization(
            .fieldOverflow(field: .colorBlocks, value: "100", limit: 99)
        )
        let readiness = ExportControl.Readiness.failed(error)

        #expect(try String(localized: #require(readiness.hint)) == String(localized: error.message))
        #expect(try String(localized: #require(readiness.hint)).contains("99"))
    }

    // MARK: - Helper

    /// Defaults chosen so each test names only what it is about; every one of them is the
    /// "everything is fine" value, so a test that changes one argument is changing exactly
    /// one thing.
    private static func readiness(
        hasSelection: Bool = true,
        runState: RunState = .finished(.programFinished),
        eligibility: ExportEligibility = .ready,
        name: String = "Rose",
        exportState: ExportState = .ready(URL.temporaryDirectory.appending(path: "Rose.dst"))
    ) -> ExportControl.Readiness {
        ExportControl.readiness(
            hasSelection: hasSelection,
            runState: runState,
            eligibility: eligibility,
            name: DesignName.validating(name),
            exportState: exportState
        )
    }
}
