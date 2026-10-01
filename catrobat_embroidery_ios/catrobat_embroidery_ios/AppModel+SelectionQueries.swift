import Samples

/// Read-only questions about the current selection.
///
/// Moved out of `AppModel.swift` unchanged in US-409, when that file reached SwiftLint's length
/// limit. Both read only `selection`, so nothing here needs the class's private state.
extension AppModel {
    /// Whether the stage draws US-309's frame-time readout: only for the measurement fixture,
    /// and only while it is still that fixture.
    ///
    /// Here rather than at `RootView`'s call site because `SampleID.us309Synthetic` exists only
    /// under `#if DEBUG` — comparing against it unguarded broke the Release build, which
    /// neither the commit gate nor CI compiles (`swift-code-reviewer`, US-405). An edit clears
    /// `provenance` and so hides the readout; it is a measurement harness, not a design.
    var showsFrameTimeReadout: Bool {
        #if DEBUG
            selection?.provenance == .us309Synthetic
        #else
            false
        #endif
    }

    /// Whether `sample` is the current selection — the row highlight and the
    /// `.isSelected` VoiceOver trait.
    ///
    /// Compares ids, not samples. `SampleProgram`'s synthesized `==` drags the
    /// whole `Program` tree along, and this runs for every row on every body
    /// evaluation.
    func isSelected(_ sample: SampleProgram) -> Bool {
        selection?.provenance == sample.id
    }
}
