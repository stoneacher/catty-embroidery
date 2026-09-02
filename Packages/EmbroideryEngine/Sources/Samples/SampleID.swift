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

    #if DEBUG
    /// US-309's measurement fixture: a 50 000-stitch hatch, reachable in the
    /// picker so the exit criterion can be captured and screenshotted in the
    /// real app rather than in a harness that is not the real app.
    ///
    /// **A case here but deliberately not a member of `SampleLibrary.all`.**
    /// ROADMAP M3 requires the bundled samples to be visually appealing designs
    /// "not test shapes", and five `SamplesTests` suites iterate `all` to assert
    /// properties of shipping content — a checked-in JSON encoding, a DST
    /// golden, an ADR-019 threshold screen — that a measurement fixture has no
    /// business satisfying. `SampleID.shipping` is what those suites and the
    /// library's totality check compare against; this case is what the *app*
    /// appends, in debug builds only.
    ///
    /// Compiled out of Release, so it cannot reach a user. The measurement build
    /// is a Release build with `DEBUG` defined on the command line, which is what
    /// keeps the optimiser on while leaving this reachable (ADR-029).
    ///
    /// **It is not, however, safe from M5 by construction, and the earlier
    /// wording here ("cannot be persisted by M5") overstated it.** This enum is
    /// `Codable` over a `String` raw value that the doc above calls a persistence
    /// token, so the moment M5 writes a selected id anywhere durable, a token
    /// written by a debug build becomes **undecodable in Release** — a decode
    /// failure on a user's own stored state, produced by a case that build cannot
    /// see. What makes it harmless today is only that the app persists nothing at
    /// all (no `AppStorage`, `SceneStorage`, `UserDefaults` or `JSONEncoder` in
    /// the app target), which is a property of today's app rather than an
    /// enforced invariant. **M5 must decode this token defensively — an unknown
    /// raw value falling back to a shipping sample rather than throwing.**
    case us309Synthetic
    #endif

    /// The cases that ship — every case in a Release build, and everything but
    /// US-309's fixture in a debug one.
    ///
    /// **Not `allCases`, and the difference is the point.** `allCases` answers
    /// "what can this enum be"; this answers "what is in the library", which is
    /// what the totality check and the per-sample suites actually mean. Before
    /// this existed they used `allCases` and were the same question by accident.
    public static var shipping: [SampleID] {
        #if DEBUG
        allCases.filter { $0 != .us309Synthetic }
        #else
        allCases
        #endif
    }

    /// Base name of the sample's checked-in JSON resource, and the stem M5 will
    /// use when copying it into Documents. Kept here so the file naming has
    /// exactly one definition.
    public var resourceName: String {
        switch self {
        case .octagonRosette: "OctagonRosette"
        case .squareCoil: "SquareCoil"
        #if DEBUG
        // 14 ASCII characters, inside the DST `LA` field's 15 (ADR-012), so the
        // seeded export name is valid and the export gate opens in the
        // screenshots this story owes.
        case .us309Synthetic: "US309Synthetic"
        #endif
        }
    }
}
