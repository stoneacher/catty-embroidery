import EditorCore
import Testing

/// US-409's test-first items 1 and 6, the package half: which kinds the palette offers, in
/// which groups and in which order.
///
/// The parity target is Catroid's Embroidery category (`CategoryBricksFactory.kt:1039-1056`)
/// and its peripheral motion list (`:1080-1095`) minus `Arc` and `GoThrough`, which are not
/// bricks here; then Control (`Wait`, `Forever`, `Repeat`) and Data, in Catroid's order
/// (decided 2026-10-01).
@Suite("Palette")
struct PaletteTests {
    private static var allPaletteKinds: [BrickKind] {
        PaletteGroup.allCases.flatMap(\.kinds)
    }

    @Test("the groups are Embroidery, Motion, then Control and Data")
    func groupOrder() {
        #expect(PaletteGroup.allCases == [.embroidery, .motion, .controlAndData])
    }

    @Test("Embroidery offers Catroid's eight embroidery bricks, in Catroid's order")
    func embroideryGroup() {
        #expect(PaletteGroup.embroidery.kinds == [
            .stitch, .setThreadColor, .runningStitch, .zigZagStitch, .tripleStitch, .sewUp,
            .stopRunningStitch, .writeEmbroideryToFile
        ])
    }

    @Test("Motion offers Catroid's peripheral motion bricks that exist here, in Catroid's order")
    func motionGroup() {
        #expect(PaletteGroup.motion.kinds == [
            .placeAt, .setX, .setY, .changeXBy, .changeYBy, .moveNSteps, .turnLeft, .turnRight,
            .pointInDirection
        ])
    }

    @Test("Control and Data offers wait, both loops and both variable bricks, in Catroid's order")
    func controlAndDataGroup() {
        #expect(PaletteGroup.controlAndData.kinds == [
            .wait, .forever, .repeatLoop, .setVariable, .changeVariableBy
        ])
    }

    /// "A new brick case cannot be silently missing": a kind added to `BrickKind` and not to a
    /// group fails here. `.loopEnd` is the one exclusion, and it is named.
    @Test("every kind except loopEnd is in the palette")
    func completeness() {
        #expect(Set(Self.allPaletteKinds) == Set(BrickKind.allCases).subtracting([.loopEnd]))
    }

    @Test("no kind appears twice")
    func noDuplicates() {
        #expect(Self.allPaletteKinds.count == Set(Self.allPaletteKinds).count)
    }

    /// Item 6, asserted against the list itself, so adding `.loopEnd` to any group fails —
    /// ADR-035: a bare `loopEnd` is the only way an action could unbalance a script.
    @Test("loopEnd is not in the palette")
    func loopEndIsAbsent() {
        #expect(!Self.allPaletteKinds.contains(.loopEnd))
    }
}
