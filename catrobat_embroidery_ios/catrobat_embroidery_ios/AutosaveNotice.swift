import EditorCore
import Foundation

/// What the window says about the saved program (US-406): the launch refusal's alert and the
/// save-failure banner.
///
/// Pure, so the choice of words is testable without a view. Functions and computed statics
/// only: `LocalizedStringResource` is not `Sendable` before iOS 18, so a stored table of them
/// would be a concurrency warning (`AppStringsTests`).
///
/// **Six whole messages, not a reason and an outcome joined in code.** The outcome sentence
/// refers back to the design ("It's been kept safe"), and in a gendered language that pronoun
/// must agree with the noun the translator chose in the reason; languages also differ in how
/// sentences are joined. One entry per combination lets a translator get both right.
enum AutosaveNotice {
    /// Why a saved design was refused, in the three groups the copy distinguishes.
    enum Cause: Equatable, Sendable {
        /// Written by a later version of the app. Not broken.
        case newerApp
        /// Could not be read at all.
        case damaged
        /// Read, but its blocks do not form a program.
        case blocksDontFit
    }

    /// No `default`: a new `ProgramDocumentError` case must fail to compile here rather than
    /// fall silently into a group.
    ///
    /// `formulaTooDeep(limit:)` carries its limit so a message *could* state it; this one
    /// deliberately does not — a nesting depth means nothing to the young users this is for.
    static func cause(of reason: ProgramLoadError) -> Cause {
        switch reason {
        case .document(.unsupportedVersion):
            .newerApp
        case .document(.corrupt), .document(.encodingFailed), .unreadable:
            .damaged
        case .document(.unbalancedScript), .document(.formulaTooDeep):
            .blocksDontFit
        }
    }

    static var refusalTitle: LocalizedStringResource {
        .autosaveRefusalTitle
    }

    /// Every message also says a blank design was opened: the alert is the only place that
    /// does.
    static func message(for refusal: ProgramRefusal) -> LocalizedStringResource {
        switch (cause(of: refusal.reason), refusal.preserved) {
        case (.newerApp, true): .autosaveRefusalMessageNewerKept
        case (.newerApp, false): .autosaveRefusalMessageNewerPaused
        case (.damaged, true): .autosaveRefusalMessageDamagedKept
        case (.damaged, false): .autosaveRefusalMessageDamagedPaused
        case (.blocksDontFit, true): .autosaveRefusalMessageBlocksKept
        case (.blocksDontFit, false): .autosaveRefusalMessageBlocksPaused
        }
    }

    /// The paused banner explains itself because the failure is shared by every window, and a
    /// window that never showed the alert can still show the banner.
    static func banner(for failure: ProgramSaveFailure) -> LocalizedStringResource {
        switch failure {
        case .saveFailed: .autosaveFailureSave
        case .unpreservedDocument: .autosaveFailurePaused
        }
    }

    /// One glyph per meaning, as on the stage (`StageNotices`): neither reuses
    /// `exclamationmark.triangle` ("outside the hoop") or `stop.circle` (the stitch limit),
    /// which can be on screen at the same time.
    static func bannerSymbol(for failure: ProgramSaveFailure) -> String {
        switch failure {
        case .saveFailed: "exclamationmark.arrow.triangle.2.circlepath"
        case .unpreservedDocument: "pause.circle"
        }
    }
}
