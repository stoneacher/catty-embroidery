import Samples

/// Read-only questions about the current selection.
///
/// Moved out of `AppModel.swift` unchanged in US-409, when that file reached SwiftLint's length
/// limit; `samples` followed in M5 for the same reason. `isSelected(_:)` went in project
/// management slice 10: a picked sample is a draft, not a row, so no view asked it any more.
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

    /// What the list's examples section shows (project management slice 7 made it a section
    /// of the project list, not the picker). Built once: the DEBUG synthetic is a 50 000-stitch
    /// program, and the list reads this on every render.
    var samples: [SampleProgram] {
        Self.listedSamples
    }

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
        // Last, so it can never displace a shipping sample from the top of the list and
        // every existing screenshot keeps its meaning (`SyntheticHarnessTests`).
        private static let listedSamples = SampleLibrary.all + [
            SampleProgram(id: .us309Synthetic, program: makeUS309SyntheticProgram())
        ]
    #else
        private static let listedSamples = SampleLibrary.all
    #endif
}
