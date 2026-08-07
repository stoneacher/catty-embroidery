import ProgramModel

/// The bundled sample programs.
///
/// `all` is in **presentation order** — US-304's picker renders exactly this
/// sequence, so reordering here reorders the UI.
public enum SampleLibrary {
    public static let all: [SampleProgram] = [
        // US-301 red phase: identities and the target are wired, the programs are
        // not. Both entries carry an empty Program so the story's tests fail on
        // their assertions rather than on a missing symbol.
        SampleProgram(id: .octagonRosette, program: Program()),
        SampleProgram(id: .squareCoil, program: Program())
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
