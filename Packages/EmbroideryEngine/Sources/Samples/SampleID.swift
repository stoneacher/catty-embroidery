/// Stable identity of a bundled sample program.
///
/// The raw value is a stable token — a case may be added or deprecated, but a raw
/// value must never be renamed. **It is not persisted** (M5, ADR-050): a sample
/// opens as a draft holding a copy of its program, and the project file records
/// the program, never which sample it came from. *(Corrected 2026-10-26: this
/// comment used to say M5 would key projects by this string.)*
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

    /// Our own content (Brick backend): twelve circles fanned around the centre
    /// in a wave of sizes, with a curved stem — Arc, GoThrough, `sin` and a sensor.
    case arcFlower

    /// Our own content (Variables): thirty-six rays, long and short in turn, around a red
    /// circle — a For loop counts the rays, an If/Else alternates their length.
    case sunburst

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
    /// **Compiled out of any build without `DEBUG` — which is the real boundary,
    /// not the Release configuration.** An earlier version of this comment said
    /// "compiled out of Release" immediately before describing the
    /// Release-with-`DEBUG` build in which it is compiled *in* (Codex round 1). The
    /// distinction matters because that measurement build is a Release build: what
    /// keeps this away from users is the absence of the `DEBUG` condition in an
    /// ordinary distribution build, and the measurement build deliberately defines
    /// it on the command line to keep the optimiser on while leaving this
    /// reachable (ADR-029).
    ///
    /// **It is safe from persistence because no sample id is persisted** (M5,
    /// ADR-050): the app stores project IDs (scene storage, the last-opened
    /// default) and programs, never a `SampleID`, so a debug-only case cannot leave
    /// a token a Release build fails to decode. Were an id ever stored, it would
    /// have to be decoded defensively, an unknown raw value falling back rather than
    /// throwing. *(Corrected 2026-10-26: this comment used to rest the safety on
    /// "the app persists nothing", which M5 made false.)*
    case us309Synthetic

    /// US-316's overlap-density fixture: US-309's hatch with its rows fifteen times closer,
    /// so the same stitches cover a fifteenth of the area. Listed after `us309Synthetic`, and
    /// kept out of `shipping` and `SampleLibrary.all` for the same reasons.
    case us316Compact
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
        allCases.filter { $0 != .us309Synthetic && $0 != .us316Compact }
        #else
        allCases
        #endif
    }

    /// Base name of the sample's checked-in JSON resource. Kept here so the file
    /// naming has exactly one definition. *(No longer an export or project name:
    /// since M5 both are the program's own name, ADR-050.)*
    public var resourceName: String {
        switch self {
        case .octagonRosette: "OctagonRosette"
        case .squareCoil: "SquareCoil"
        case .arcFlower: "ArcFlower"
        case .sunburst: "Sunburst"
        #if DEBUG
        // 14 ASCII characters, inside the DST `LA` field's 15 (ADR-012), so the
        // seeded export name is valid and the export gate opens in the
        // screenshots this story owes.
        case .us309Synthetic: "US309Synthetic"
        // 12 ASCII characters, inside the `LA` field's 15, like the case above.
        case .us316Compact: "US316Compact"
        #endif
        }
    }
}
