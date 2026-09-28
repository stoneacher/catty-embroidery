import CoreGraphics

/// How far a script row is indented, and where its nesting guides are drawn (US-407).
///
/// **Indentation shows structure, not text size**, so the step is a fixed number of points
/// rather than a `@ScaledMetric` — but it stops growing at a cap, and the cap is lower at
/// accessibility text sizes. A brick label carrying two parameters is the longest string in the
/// app, and indentation narrows the row it has to reflow in; uncapped, a loop four deep at AX1
/// would leave the sentence a word per line.
///
/// Past the cap, the **guides** still show every level, packed evenly into the capped gutter,
/// so a sighted user can still count the depth. The spoken depth is exact regardless
/// (`BrickRowPresentation.accessibilityLabel`).
nonisolated enum ScriptRowLayout {
    static let step: CGFloat = 16
    static let regularCap = 6
    static let accessibilityCap = 3

    static func indent(forDepth depth: Int, isAccessibilitySize: Bool) -> CGFloat {
        CGFloat(min(max(depth, 0), cap(isAccessibilitySize))) * step
    }

    /// The leading offset of one vertical guide per level, each in the middle of its step while
    /// the depth fits under the cap, and spread evenly across the capped indent beyond it.
    static func guideOffsets(forDepth depth: Int, isAccessibilitySize: Bool) -> [CGFloat] {
        guard depth > 0 else { return [] }
        let spacing = indent(forDepth: depth, isAccessibilitySize: isAccessibilitySize) / CGFloat(depth)
        return (0 ..< depth).map { (CGFloat($0) + 0.5) * spacing }
    }

    private static func cap(_ isAccessibilitySize: Bool) -> Int {
        isAccessibilitySize ? accessibilityCap : regularCap
    }
}
