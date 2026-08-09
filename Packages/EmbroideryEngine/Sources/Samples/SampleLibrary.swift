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

    /// The sample with this id. Total by construction — `all` covers every
    /// `SampleID`, and `SampleLibraryTests` pins that it does.
    public static subscript(id: SampleID) -> SampleProgram {
        guard let sample = all.first(where: { $0.id == id }) else {
            preconditionFailure(
                "SampleLibrary.all is missing \(id.rawValue); the totality test should have caught this"
            )
        }
        return sample
    }
}
