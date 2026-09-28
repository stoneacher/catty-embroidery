@testable import catrobat_embroidery_ios
import CoreGraphics
import Testing

/// US-407: rows reflow rather than truncate at AX1, and indentation is what narrows them.
///
/// The indent grows by a fixed step per level up to a cap — a lower cap at accessibility
/// sizes — so the text column keeps most of the row however deep the nesting. Past the cap the
/// **guides** still show every level, packed into the capped gutter, so depth stays visible to
/// a sighted user; the spoken depth is exact regardless (`BrickRowPresentationTests`).
struct ScriptRowLayoutTests {
    @Test("the indent grows one step per level", arguments: [false, true])
    func indentGrowsPerLevel(_ isAccessibilitySize: Bool) {
        let step = ScriptRowLayout.indent(forDepth: 1, isAccessibilitySize: isAccessibilitySize)

        #expect(ScriptRowLayout.indent(forDepth: 0, isAccessibilitySize: isAccessibilitySize) == 0)
        #expect(step > 0)
        #expect(ScriptRowLayout.indent(forDepth: 2, isAccessibilitySize: isAccessibilitySize) == 2 * step)
        #expect(ScriptRowLayout.indent(forDepth: 3, isAccessibilitySize: isAccessibilitySize) == 3 * step)
    }

    @Test("the indent stops growing at a cap, which is lower at accessibility sizes")
    func indentIsCapped() {
        let regularCap = ScriptRowLayout.indent(forDepth: 100, isAccessibilitySize: false)
        let accessibilityCap = ScriptRowLayout.indent(forDepth: 100, isAccessibilitySize: true)

        #expect(regularCap == ScriptRowLayout.indent(forDepth: 6, isAccessibilitySize: false))
        #expect(regularCap > ScriptRowLayout.indent(forDepth: 5, isAccessibilitySize: false))
        #expect(accessibilityCap == ScriptRowLayout.indent(forDepth: 3, isAccessibilitySize: true))
        #expect(accessibilityCap > ScriptRowLayout.indent(forDepth: 2, isAccessibilitySize: true))
        #expect(accessibilityCap < regularCap)
    }

    @Test("a negative depth is not indented")
    func negativeDepth() {
        #expect(ScriptRowLayout.indent(forDepth: -1, isAccessibilitySize: false) == 0)
        #expect(ScriptRowLayout.guideOffsets(forDepth: -1, isAccessibilitySize: false).isEmpty)
    }

    @Test("there is one guide per level at any depth, ascending and inside the indent",
          arguments: [0, 1, 2, 3, 6, 7, 12], [false, true])
    func oneGuidePerLevel(_ depth: Int, _ isAccessibilitySize: Bool) {
        let guides = ScriptRowLayout.guideOffsets(forDepth: depth, isAccessibilitySize: isAccessibilitySize)
        let indent = ScriptRowLayout.indent(forDepth: depth, isAccessibilitySize: isAccessibilitySize)

        #expect(guides.count == depth)
        #expect(guides == guides.sorted())
        #expect(Set(guides).count == guides.count, "two guides drawn on top of each other read as one level")
        #expect(guides.allSatisfy { $0 >= 0 && $0 < indent })
    }
}
