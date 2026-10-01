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
    ///
    /// - **Embroidery**: Catroid's Embroidery category (`CategoryBricksFactory.kt:1039-1056`),
    ///   in its order.
    /// - **Motion**: Catroid's peripheral motion list (`:1080-1095`), in its order, without
    ///   `Arc` and `GoThrough`, which are not bricks here.
    /// - **Control and Data**: what the flavor leaves visible in Catroid's Control and Data
    ///   categories that the interpreter executes, in Catroid's order (decided 2026-10-01).
    ///   Without the two loops the editor could build neither bundled sample.
    ///
    /// **`.loopEnd` is in no group** (ADR-035): a bare `loopEnd` is the one brick that could
    /// unbalance a script, and inserting a loop already brings its own.
    public var kinds: [BrickKind] {
        switch self {
        case .embroidery:
            [.stitch, .setThreadColor, .runningStitch, .zigZagStitch, .tripleStitch, .sewUp,
             .stopRunningStitch, .writeEmbroideryToFile]
        case .motion:
            [.placeAt, .setX, .setY, .changeXBy, .changeYBy, .moveNSteps, .turnLeft, .turnRight,
             .pointInDirection]
        case .controlAndData:
            [.wait, .forever, .repeatLoop, .setVariable, .changeVariableBy]
        }
    }
}
