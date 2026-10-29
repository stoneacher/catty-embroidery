#if DEBUG
    import ProgramModel

    // US-316's overlap-density fixture: US-309's hatch with the rows packed fifteen times closer.
//
    // DEBUG-only and outside `SampleLibrary.all` for the same reasons as `us309Synthetic`
    // (its file explains both). It exists to be captured on device beside the original, so the
    // two differ in exactly one parameter of one shared builder.
//
    // **What changing the spacing does and does not hold** (feature brief D1). The stitch count,
    // the colour runs and their lengths, the stroke widths and the fit transform are the same. The
    // geometry is not: the running stitch rounds every stitch to whole stage points, so about ten
    // rows land on one `y`, and each row starts diagonally from where the previous one ended. The
    // covered area shrinks by fifteen; the coincident rows, the transition segments, dot overlap
    // and antialiased edges change with it, uncontrolled. `CompactSyntheticDesignTests` pins the
    // plan counts of both fixtures side by side.

    /// Fifteen times closer than the original's 1.5, so the 250 rows span 25 stage points
    /// instead of 375.
    ///
    /// **Not chosen by the original's half-stitch argument**, which does not carry over: the
    /// next row is measured diagonally from the previous row's anchor, about √(400² + 0.1²) away,
    /// close to the boundary at 400 lengths. Its margin is measured instead, over every needle
    /// update (`CompactSyntheticSampleTests`). 0.25 was rejected because it shrinks the height
    /// only six times.
    private let compactRowSpacing = 0.1

    /// The exact number of stitch events this program emits: the original's, by construction.
    public let us316CompactStitchCount = 50001

    /// US-309's hatch over a fifteenth of its height, in the same five colour bands.
    public func makeUS316CompactProgram() -> Program {
        makeSyntheticHatch(name: "US316 Compact", rowSpacing: compactRowSpacing)
    }
#endif
