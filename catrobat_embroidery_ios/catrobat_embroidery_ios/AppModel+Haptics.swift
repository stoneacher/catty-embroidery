import EmbroideryEngine
import StagePreview

// The run-end half of the haptic map (Release readiness D3, ADR-052). The selection half sits
// with the edits it follows (`addFromPalette`, `dropRows`); the pulse itself is `pulse(_:)`.
extension AppModel {
    /// A run reached its end (ADR-026: the export is prepared now, because a `ShareLink` needs
    /// the file before it is tapped). Then at most one pulse (Release readiness D3):
    ///
    /// - **error** for a failed preparation, whatever ended the run;
    /// - **success** only for a run that finished on its own, with a prepared file the export
    ///   gate offers (ADR-026's `isExportable`). A user stop is deliberately partial and the
    ///   stitch limit is a protective truncation, so neither is a success, and a one-stitch
    ///   design is prepared but not offered.
    ///
    /// The pulse comes after `prepare`, so it describes an attempt that has happened.
    func runTerminated(_ completion: RunCompletion, exportModel: EmbroideryStream) {
        let state = exporter.prepare(exportModel: exportModel)
        if case .failed = state {
            pulse(.error)
        } else if completion == .programFinished, case .ready = state, runner.run.isExportable {
            pulse(.success)
        }
    }
}
