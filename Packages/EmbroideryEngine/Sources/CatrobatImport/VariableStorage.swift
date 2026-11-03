import ProgramModel

/// How Catroid's SetVariable stores a value, decided by the formula's root
/// (`SetVariableAction.kt:45-64`). Every read normalises a `Boolean` to 1.0/0.0 and
/// parses a numeric string, so the imported `Formula` value is right either way;
/// the kind matters only where Catroid tests for a `Double` (ChangeVariable,
/// ForVariableFromTo), which the program import checks (Codex slice 3, findings 1–2).
package enum VariableStorage: Hashable, Sendable {
    case double
    /// A logical root: `FormulaElement.isBoolean` (`:940-982`).
    case boolean
    /// A root STRING with a value, kept as written (`isFirstLevelStringTree`).
    case string
    /// A root USER_VARIABLE: a `Boolean` iff that variable holds one when read; a
    /// numeric string held there is converted.
    case copied(from: String)
}

extension FormulaImport {
    private static let logicalOperators: Set = [
        "LOGICAL_AND", "LOGICAL_OR", "EQUAL", "NOT_EQUAL", "SMALLER_OR_EQUAL",
        "GREATER_OR_EQUAL", "SMALLER_THAN", "GREATER_THAN", "LOGICAL_NOT"
    ]

    /// What a SetVariable of `element` stores. Only the root's own type counts:
    /// a BRACKET root is never boolean and never first-level STRING.
    package static func storage(ofVariableValue element: XMLTree.Element) -> VariableStorage {
        let value = element.child("value")
        switch element.child("type")?.text {
        case "STRING":
            return value == nil ? .double : .string
        case "USER_VARIABLE":
            return .copied(from: value?.text ?? "")
        case "OPERATOR":
            return logicalOperators.contains(value?.text ?? "") ? .boolean : .double
        case "FUNCTION":
            let name = value?.text
            return name == "TRUE" || name == "FALSE" ? .boolean : .double
        default:
            return .double
        }
    }
}
