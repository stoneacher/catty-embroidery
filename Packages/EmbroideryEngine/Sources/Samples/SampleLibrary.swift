import ProgramModel

/// The bundled sample programs.
///
/// `all` is in **presentation order** — US-304's picker renders exactly this
/// sequence, so reordering here reorders the UI.
public enum SampleLibrary {
    public static let all: [SampleProgram] = [
        SampleProgram(id: .octagonRosette, program: makeOctagonRosetteProgram()),
        SampleProgram(id: .squareCoil, program: makeSquareCoilProgram())
    ]

    /// The sample with this id.
    ///
    /// **Total over `SampleID.shipping`, which in Release is every case and in DEBUG is
    /// not.** US-309 added `SampleID.us309Synthetic` behind `#if DEBUG`; it is built by
    /// `AppModel` and deliberately absent from `all`, so in a debug build this subscript is
    /// partial and the `preconditionFailure` below is reachable in principle. It is not
    /// reachable today — no call site passes the synthetic id here — but the comment that
    /// called it unreachable by construction was the trap, not the code.
    public static subscript(id: SampleID) -> SampleProgram {
        guard let sample = all.first(where: { $0.id == id }) else {
            preconditionFailure(
                """
                SampleLibrary.all is missing \(id.rawValue); it is not a shipping sample, \
                or the totality test should have caught this
                """
            )
        }
        return sample
    }
}
