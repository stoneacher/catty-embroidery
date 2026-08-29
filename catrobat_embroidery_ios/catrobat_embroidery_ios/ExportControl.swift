import EmbroideryEngine
import Foundation
import StagePreview
import SwiftUI

/// What the share affordance offers, as a pure function of everything that bears on it.
///
/// **A value rather than modifiers inside a view**, for the reason `RunControl` records:
/// nothing can read a rendered `.accessibilityHint` back out of a hosted view, so a hint
/// built inline in `body` is checkable only by a screenshot — and a screenshot cannot show
/// what VoiceOver would say. US-308's definition of done requires the disabled control to
/// say *why*, and putting the mapping here is what gives that criterion a test.
enum ExportControl {
    /// Why the control is offering what it is offering.
    ///
    /// **Two or more reasons can be true at once** — nothing selected *and* an empty name —
    /// so the order below is a contract, asserted in `ExportControlTests` rather than left
    /// to the order the branches happen to be written in.
    enum Readiness: Equatable {
        /// No design chosen. The control is not rendered at all, so this carries no hint.
        case noSelection

        /// A run is in flight. **Distinct from `notRun` even though the engine cannot tell
        /// them apart**: `exportModel` is `nil` throughout a run, so `ExportEligibility`
        /// reports `.notRun` for both, and the run state is the only thing that separates
        /// them. Without the split, a VoiceOver user mid-run would be told to press Play
        /// while the button beneath them reads "Stop".
        case running

        /// Never run, or discarded.
        case notRun

        /// Ran, but produced fewer than two stitches.
        ///
        /// **Collapses two of the engine's verdicts.** `nothingStitched` and `singleStitch`
        /// are different facts, which is why `ExportEligibility` keeps them apart — the
        /// engine should report what happened, not decide copy — but they are one sentence
        /// to a reader: a design needs at least two points.
        case tooFewStitches

        /// Ran and drew, but every coordinate was refused at replay (ADR-020). The one case
        /// where the export gate and the render empty-state legitimately disagree, and the
        /// reason they are two predicates rather than Catroid's one.
        case nothingEmbroiderable

        case nameEmpty
        case nameInvalid

        case failed(ExportError)

        /// The only enabled state. It **carries the URL**, so a view cannot build a
        /// `ShareLink` for a file that was never prepared.
        case ready(URL)
    }

    /// Resolves one reason from every input that bears on export.
    ///
    /// Order, and why each step precedes the next:
    /// 1. **Selection** outranks everything — there is no design to talk about.
    /// 2. **The run** outranks the name: a name is only actionable once there is something
    ///    to name, and reversing these would tell a user to fix their name for a design
    ///    they have not run.
    /// 3. **The name** outranks the prepared file, because an unusable name is why no file
    ///    was prepared.
    static func readiness(
        hasSelection: Bool,
        runState: RunState,
        eligibility: ExportEligibility,
        name: Result<DesignName, DesignNameProblem>,
        exportState: ExportState
    ) -> Readiness {
        guard hasSelection else { return .noSelection }
        if runState.isRunning {
            return .running
        }
        return runReason(eligibility) ?? nameReason(name) ?? preparedReason(exportState)
    }

    /// Step 2. `nil` means "the run is no obstacle", which is what lets the caller read as
    /// the precedence list its doc comment describes.
    ///
    /// Split out because the whole resolution crossed SwiftLint's cyclomatic-complexity
    /// limit of 10 — three switches and two guards in one function. The seam was already
    /// there in the documentation, so the rule asked for the shape the comment claimed.
    private static func runReason(_ eligibility: ExportEligibility) -> Readiness? {
        switch eligibility {
        case .notRun: .notRun
        case .nothingStitched, .singleStitch: .tooFewStitches
        case .nothingEmbroiderable: .nothingEmbroiderable
        case .ready: nil
        }
    }

    /// Step 3.
    private static func nameReason(
        _ name: Result<DesignName, DesignNameProblem>
    ) -> Readiness? {
        switch name {
        case .failure(.empty): .nameEmpty
        case .failure: .nameInvalid
        case .success: nil
        }
    }

    /// Step 4: what was actually prepared.
    private static func preparedReason(_ exportState: ExportState) -> Readiness {
        switch exportState {
        case let .failed(error): .failed(error)
        case let .ready(url): .ready(url)
        // Exportable, validly named, and yet nothing on disk. Not reachable through the
        // app's own wiring — `prepare` runs on every termination and every name commit —
        // and resolved toward the truthful answer rather than trapping: there is nothing
        // to share, and "not run" is the sentence that sends the user to press Play.
        case .idle: .notRun
        }
    }
}

extension ExportControl.Readiness {
    /// Every reason that dims the control **and owes an explanation**.
    ///
    /// It exists because the tests that claim to cover "the whole enum" cannot: `Readiness`
    /// has associated values, so it is not `CaseIterable`, and an in-loop review proved the
    /// point by adding a tenth case with a `nil` hint and watching the suite stay green. The
    /// exhaustive `switch` in `hint` forces a *compile-time* decision for a new case, but
    /// `nil` is a legal answer there — so this list is the one obvious place a new case has
    /// to be added, sitting next to the type rather than in a test file.
    ///
    /// **This is a chokepoint, not an impossibility**, and it is labelled that way for the
    /// reason `RunPhase` labels its own: a case omitted from this list is still
    /// representable. What it buys is that the omission is visible next to the enum instead
    /// of only in a screenshot.
    static var reasonsOwingAHint: [Self] {
        [
            .running, .notRun, .tooFewStitches, .nothingEmbroiderable,
            .nameEmpty, .nameInvalid, .failed(.writeFailed)
        ]
    }

    var isEnabled: Bool {
        shareURL != nil
    }

    /// The file to hand the share sheet, and `nil` in every state that has none — which is
    /// what makes `isEnabled` derived rather than a second thing to keep in step.
    var shareURL: URL? {
        if case let .ready(url) = self {
            url
        } else {
            nil
        }
    }

    /// Why the control is dimmed, spoken by VoiceOver.
    ///
    /// `nil` for `ready` (an enabled control explains itself) and for `noSelection` (the
    /// control is not rendered, so a hint would be copy for an unreachable state — the
    /// mistake ADR-028 had to undo, at ~75 translators a time).
    var hint: LocalizedStringResource? {
        switch self {
        case .noSelection, .ready: nil
        case .running: .stageExportHintRunning
        case .notRun: .stageExportHintNotRun
        case .tooFewStitches: .stageExportTooFewStitches
        case .nothingEmbroiderable: .stageExportNothingEmbroiderable
        case .nameEmpty: .stageExportHintNameEmpty
        case .nameInvalid: .stageExportHintNameInvalid
        case let .failed(error): error.message
        }
    }

    /// The sentence shown *visibly* under the stage, for the reasons a sighted user would
    /// otherwise have no way to learn.
    ///
    /// Deliberately narrower than `hint`. The states a user can resolve by looking — nothing
    /// selected, not yet run, still running, an unfinished name — are already explained by
    /// the screen: the empty states, the transport button's own title, and the field's own
    /// error line. Repeating them here would be four redundant lines competing for the space
    /// the canvas gives up first. What is left is what nothing else on screen says.
    ///
    /// Where a notice exists it is the **same catalog entry** as the hint, so the two cannot
    /// drift — the argument `StageTransportRow` already makes for the transport title being
    /// its own accessibility label.
    var notice: LocalizedStringResource? {
        switch self {
        case .tooFewStitches, .nothingEmbroiderable, .failed: hint
        case .noSelection, .running, .notRun, .nameEmpty, .nameInvalid, .ready: nil
        }
    }
}
