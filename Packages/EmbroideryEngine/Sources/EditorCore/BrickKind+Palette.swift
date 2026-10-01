/// The palette's groups, in the order the palette shows them (US-409).
///
/// The curated set lives here rather than in the app so that "a new brick case cannot be
/// silently missing" is a package test over `BrickKind.allCases`. The group *titles* stay in
/// the app, since SwiftPM does not compile `.xcstrings` (ADR-039).
public enum PaletteGroup: Sendable, Hashable, CaseIterable {
    case embroidery
    case motion
    case controlAndData

    /// The kinds this group offers, in palette order.
    public var kinds: [BrickKind] {
        []
    }
}
