import Samples

/// Read-only questions about the current selection.
///
/// Moved out of `AppModel.swift` unchanged in US-409, when that file reached SwiftLint's length
/// limit; `samples` followed in M5 for the same reason. None of them needs the class's private
/// state.
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

    /// What the picker lists.
    ///
    /// A pass-through today, and the single seam M5 replaces when the real
    /// project list arrives (create/rename/duplicate/delete). Routing the view
    /// through it rather than letting the view read `SampleLibrary.all` directly
    /// is the entire reason M5 is an edit here instead of an edit to the view.
    var samples: [SampleProgram] {
        #if DEBUG
            // **Appended here rather than added to `SampleLibrary.all`**, and appended *last*.
            //
            // US-309 needs a 50 000-stitch design reachable in the running app — the frame
            // capture and the screenshots are of the real screen, not of a harness. It needs to
            // be a real `SampleProgram` because the stage's title, its accessibility label and
            // `ExportControl.readiness` all key off a selected sample; a launch-argument path
            // that ran the program without selecting anything would screenshot a
            // half-configured screen.
            //
            // It stays out of the library because five `SamplesTests` suites iterate
            // `SampleLibrary.all` to assert properties of *shipping* content — a checked-in JSON
            // encoding, a DST golden, an ADR-019 threshold screen — and because ROADMAP M3
            // requires the bundled samples to be visually appealing designs "not test shapes".
            //
            // Last, so it can never displace a shipping sample from the top of the picker and
            // every existing screenshot keeps its meaning.
            SampleLibrary.all + [
                SampleProgram(id: .us309Synthetic, program: makeUS309SyntheticProgram())
            ]
        #else
            SampleLibrary.all
        #endif
    }
}
