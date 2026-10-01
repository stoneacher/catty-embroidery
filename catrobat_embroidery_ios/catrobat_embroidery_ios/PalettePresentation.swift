import EditorCore
import EmbroideryEngine
import Foundation

/// One group of the brick palette (US-409).
nonisolated struct PaletteSection: Equatable, Identifiable {
    let id: PaletteGroup
    let title: String
    let rows: [PaletteRowPresentation]

    /// The palette, in the order it shows.
    static func sections(locale _: Locale = .current) -> [PaletteSection] {
        []
    }
}

/// One brick the palette offers (US-409).
nonisolated struct PaletteRowPresentation: Equatable, Identifiable {
    let id: BrickKind
    /// The brick as it will appear in the script.
    let text: String
    /// What the brick does.
    let description: String
    let accessibilityLabel: String
    let threadColor: ThreadColor?
}

/// What the script list scrolls to after a palette tap (US-409).
struct PaletteInsertion: Equatable {
    let index: Int
    let serial: Int
}
