import StagePreview

/// Starting a run and re-preparing its export (US-306, US-308).
///
/// Moved out of `AppModel.swift` unchanged in M5, when that file reached SwiftLint's length
/// limit again. Neither needs the class's private state.
extension AppModel {
    /// Starts the selected design from the beginning, throwing away whatever the last run
    /// prepared.
    ///
    /// Round 1 of the cross-vendor review found Play Again leaving `exporter.state ==
    /// .ready(oldURL)` — that URL still holding the *previous* run — while the new run had
    /// already cleared the design. The discard lives on `RunViewModel.onRunDiscarded` rather
    /// than here, because round 2 pointed out that putting it in this method left the
    /// invariant as a convention: `runner.play(_:)` and `runner.reset()` are both reachable
    /// directly. This method now only checks that something is selected and runs the
    /// **working** program — `editor.program`, not the sample it was loaded from, which since
    /// US-405 the selection no longer carries.
    ///
    /// Since US-407 launch selects the blank program (ADR-039), so this guard no longer bites.
    func play() {
        guard selection != nil else { return }
        runner.play(editor.program)
    }

    /// Rewrites the file under the name the user has just committed.
    ///
    /// Called on submit and on focus loss, **never per keystroke**: the name goes into the
    /// `LA` bytes as well as the file name, so every commit genuinely invalidates the
    /// previous file and a per-keystroke call would write one file per character.
    ///
    /// A no-op before anything has run, which is not merely defensive — there is no design
    /// to serialise, and a file named after one that does not exist is a lie the share
    /// control would then offer.
    func commitName() {
        guard let model = runner.run.exportModel else { return }
        exporter.prepare(exportModel: model)
    }
}
