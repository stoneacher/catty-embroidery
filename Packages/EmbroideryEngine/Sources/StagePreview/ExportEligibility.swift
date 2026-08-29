import EmbroideryEngine

/// Whether the run on the stage can be written to a `.dst` file, and if not, why not
/// (US-308).
///
/// **The gate is `exportModel.count > 1` on the post-replay assembled stream** — not
/// `hasValidPattern`, which counts recorded *ops* the replay may reject, and not the
/// display-list count, which is op-derived and carries the same defect. That closes the
/// divergence ADR-020 left "for whoever wires up export to decide", and it matches
/// Catroid's `validPatternExists()`, which counts points in the *built* streams.
///
/// Five cases rather than a `Bool`, because the app must say *why* the share affordance is
/// dimmed — the story's definition of done requires a localised hint carrying the reason,
/// and Catroid's single predicate for both gating and rendering cannot supply one.
public enum ExportEligibility: Hashable, Sendable {
    /// No run has terminated, so there is nothing to export **yet**.
    ///
    /// Covers three situations the app words identically and ADR-026 distinguishes: never
    /// run, discarded by `reset()`, and — the one that surprises — **mid-run**.
    /// `PreviewRunState.exportModel` is written only from the terminal update, so this is
    /// the verdict at every frame of a running run, and the share affordance is therefore
    /// disabled for the whole of every run. "Export the design you can see, right now" is
    /// not something M3 offers.
    case notRun

    /// A run ended having produced no stitches at all — nothing drawn, nothing to sew.
    case nothingStitched

    /// Stitches were drawn but **every one was refused at replay** (ADR-020): finite
    /// coordinates the DST format cannot represent, so `emitStitches` drew them and
    /// `addStitch` silently declined them.
    ///
    /// This is the case where the export gate and the render empty-state legitimately
    /// disagree, and it is why they are two predicates rather than one. The app says
    /// "nothing in this design can be embroidered" instead of shipping the header-only
    /// file Catty ships (515 bytes, valid-looking, zero stitches).
    ///
    /// Worth knowing what the user is actually looking at: the rejected coordinate is
    /// *finite*, so the display list accepts it, and a pure-rejection design draws as a
    /// degenerate point at an absurd offset — visually near-empty rather than the "you can
    /// see your design, it just cannot be sewn" the story's wording implies.
    case nothingEmbroiderable

    /// Exactly one stitch survived replay. A point, not a design.
    ///
    /// **Deliberately not split by what the display shows**, unlike the zero case above.
    /// The asymmetry has a reason rather than being an oversight: at zero the two
    /// situations need different sentences, because one of them has nothing on screen and
    /// "nothing here can be embroidered" would be baffling. At one, both have something on
    /// screen and the sentence is the same either way — a design needs at least two points.
    case singleStitch

    /// Two or more stitches: exportable.
    case ready
}

public extension PreviewRunState {
    /// The export verdict for this run.
    ///
    /// A computed property on the run state rather than a free function, because both
    /// inputs — the export model and the display list — are already here, and because it
    /// puts the verdict under `swift test` rather than behind a simulator boot. The app
    /// layer combines it with the things the package cannot know (is a design selected, is
    /// the typed name valid) in its own pure mapping.
    var exportEligibility: ExportEligibility {
        guard let model = exportModel else {
            return .notRun
        }
        switch model.count {
        case 0:
            // The one place the display list is consulted, and only to choose between two
            // sentences — never to decide whether export is possible.
            return display.isEmpty ? .nothingStitched : .nothingEmbroiderable
        case 1:
            return .singleStitch
        default:
            return .ready
        }
    }

    /// The gate itself. Kept beside the reason so no caller has to re-derive
    /// "`.ready` means yes" and get it subtly wrong.
    var isExportable: Bool {
        exportEligibility == .ready
    }
}
