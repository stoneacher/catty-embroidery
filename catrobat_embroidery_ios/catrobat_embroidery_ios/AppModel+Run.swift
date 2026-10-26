import StagePreview

/// Starting a run (US-306).
///
/// Moved out of `AppModel.swift` unchanged in M5, when that file reached SwiftLint's length
/// limit again. It needs none of the class's private state.
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
}
