import Foundation
import ProgramModel

/// One bundled sample: a stable identity, the localized strings it is presented
/// under, and the program itself.
///
/// The strings live in this target's own resource bundle rather than in the app
/// (US-301). That keeps the samples self-describing — anything linking the
/// `Samples` product gets real text, including M5's project creation — and it is
/// what lets this package *test* that they resolve, which a bare key handed to a
/// catalog somewhere else cannot.
public struct SampleProgram: Sendable, Hashable, Identifiable {
    public let id: SampleID

    /// The program. A **stored value**, not a builder closure: a sample is a
    /// dozen bricks of pure value types, so constructing all of them when the
    /// library is first touched costs nothing measurable, while storing them
    /// keeps `SampleProgram` `Hashable` (US-304's `List(selection:)` needs it)
    /// and makes `decoded == sample.program` a single expectation. A closure
    /// would forfeit both and leave "decode equals the builder" ambiguous about
    /// *which* invocation it means.
    public let program: Program

    public init(id: SampleID, program: Program) {
        self.id = id
        self.program = program
    }

    /// Hashed on `id` alone, while `==` (synthesized) compares the program too.
    ///
    /// That is the correct pairing, not a shortcut: `Hashable` requires equal
    /// values to hash equally, which hashing a subset of the compared fields
    /// always satisfies. It is also the only option available — `Program` is
    /// deliberately `Equatable` but not `Hashable`, because its `==` is NaN-aware
    /// (ADR-006 reflexivity) and no consistent `hash(into:)` exists for a type
    /// whose equality treats NaN as equal to itself.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Localization key for the display name. Derived from `id` rather than
    /// stored, so a key and an id can never drift apart.
    public var nameKey: String {
        "sample.\(id.rawValue).name"
    }

    /// Localization key for the one-line description.
    public var descriptionKey: String {
        "sample.\(id.rawValue).description"
    }

    /// The sample's display name, resolved from this target's resource bundle.
    public var displayName: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(nameKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    /// A one-line description of what the design looks like.
    public var summary: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(descriptionKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    /// URL of the checked-in JSON encoding of `program`, shipped as a package
    /// resource (ADR-003).
    ///
    /// **M3 never reads this.** The Swift builder is the single source of truth
    /// and the app links it directly — there is no decode path and no error
    /// state to design for (US-304). The file exists so US-301's round-trip test
    /// can prove the encoding still matches the builder, and so M5 can copy it
    /// into Documents to create a real project instead of re-deriving ADR-003's
    /// format.
    ///
    /// Optional rather than force-unwrapped: a missing resource is a build
    /// misconfiguration, and this package does not trap on states a caller could
    /// report (the direction US-211/ADR-025 is taking the DST path).
    public var programJSONURL: URL? {
        Bundle.module.url(forResource: id.resourceName, withExtension: "json")
    }
}
