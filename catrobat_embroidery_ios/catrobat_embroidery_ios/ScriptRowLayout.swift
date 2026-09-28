import CoreGraphics

/// How far a row is indented, and where its nesting guides are drawn (US-407).
nonisolated enum ScriptRowLayout {
    static func indent(forDepth depth: Int, isAccessibilitySize: Bool) -> CGFloat {
        0
    }

    static func guideOffsets(forDepth depth: Int, isAccessibilitySize: Bool) -> [CGFloat] {
        []
    }
}
