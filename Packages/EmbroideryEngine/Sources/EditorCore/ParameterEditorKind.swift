import ProgramModel

/// Which editor a parameter value gets (US-410).
public enum ParameterEditorKind: Sendable, Equatable {
    case number(Double)
    case variableReference(String)
    case readOnlyFormula(Formula, reason: ReadOnlyFormulaReason)
    case variableName(String)
    case threadColor(hex: String)
    case fileName(String)

    public init(_: ParameterValue) {
        self = .number(0)
    }
}

/// Why a formula cannot be edited in M4.
public enum ReadOnlyFormulaReason: Sendable, Equatable {
    case binary
    case unaryMinus
}
