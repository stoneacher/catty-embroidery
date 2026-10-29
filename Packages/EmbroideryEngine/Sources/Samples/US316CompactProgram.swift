#if DEBUG
    import ProgramModel

    /// Fifteen times closer than the original's 1.5, so the stitches span 24.5 stage points of
    /// height instead of 373.5 (pinned in `CompactSyntheticDesignTests`).
    ///
    /// **Not chosen by the original's half-stitch argument**, which does not carry over: the
    /// next row is measured diagonally from the previous row's anchor, about √(400² + 0.1²) away,
    /// close to the boundary at 400 lengths. Its margin is measured instead, over every needle
    /// update (`CompactSyntheticSampleTests`). 0.25 was rejected because it shrinks the height
    /// only six times.
    private let compactRowSpacing = 0.1

    /// The exact number of stitch events this program emits: the original's, by construction.
    public let us316CompactStitchCount = 50001

    /// US-316's overlap-density fixture: US-309's hatch with its rows fifteen times closer, in
    /// the same five colour bands.
    ///
    /// DEBUG-only and outside `SampleLibrary.all` for the same reasons as `us309Synthetic`
    /// (its file explains both). It exists to be captured on device beside the original, so the
    /// two differ in exactly one parameter of one shared builder.
    ///
    /// **What changing the spacing does and does not hold** (feature brief D1):
    /// - **Held**: the stitch count, the colour runs and their lengths, the stroke widths, the
    ///   fit transform, and the live plan's segment, dot and corner counts.
    /// - **Varied**: the covered area, by fifteen.
    /// - **Varied too, uncontrolled**: the running stitch rounds every stitch to whole stage
    ///   points, so the rows fold onto 26 heights instead of 375 (about ten to a height); each
    ///   row starts diagonally from where the previous one ended; dot overlap and antialiased
    ///   edges change with both.
    public func makeUS316CompactProgram() -> Program {
        makeSyntheticHatch(name: "US316 Compact", rowSpacing: compactRowSpacing)
    }
#endif
