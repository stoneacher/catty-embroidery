import EditorCore
import Foundation

/// The parameter editor's localized copy (US-410).
nonisolated enum ParameterEditorText {
    static func message(for error: FormulaLiteralError) -> String {
        ""
    }

    static func message(for problem: VariableNameProblem) -> String {
        ""
    }

    static func message(for reason: ReadOnlyFormulaReason) -> String {
        ""
    }

    static func name(of swatch: ThreadSwatch) -> String {
        ""
    }
}
