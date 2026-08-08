/// Stable identity of a bundled sample program.
///
/// The raw value is a **persistence token**: M5 copies a sample's JSON into
/// Documents to create a real project and keys it by this string, so a case may
/// be added or deprecated but a raw value must never be renamed.
///
/// A closed enum rather than a `String` or a `RawRepresentable` struct, because
/// sample content ships *inside* this target: an open id type would buy
/// extensibility no caller can use, while the enum lets consumers switch
/// exhaustively and have the compiler flag the gap when a sample is added.
public enum SampleID: String, Sendable, Hashable, CaseIterable, Codable {
    /// Catroid's `DefaultExampleProject`, transcribed verbatim (US-301) — eight
    /// octagons fanned around a shared corner, in zigzag stitch.
    case octagonRosette

    /// Our own content: a two-colour square coil in triple stitch, its side
    /// length grown by a variable each turn.
    case squareCoil

    /// Base name of the sample's checked-in JSON resource, and the stem M5 will
    /// use when copying it into Documents. Kept here so the file naming has
    /// exactly one definition.
    public var resourceName: String {
        switch self {
        case .octagonRosette: "OctagonRosette"
        case .squareCoil: "SquareCoil"
        }
    }
}
