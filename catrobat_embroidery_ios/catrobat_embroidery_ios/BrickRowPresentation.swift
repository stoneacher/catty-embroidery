import EditorCore
import EmbroideryEngine
import Foundation
import ProgramModel

/// One row of the script list (US-407).
nonisolated struct BrickRowPresentation: Equatable, Identifiable {
    let id: Int
    let kind: BrickKind
    let depth: Int
    let text: String
    let accessibilityLabel: String
    let openerIndex: Int?
    let threadColor: ThreadColor?

    static func rows(for program: Program, locale: Locale = .current) -> [BrickRowPresentation] {
        []
    }
}
