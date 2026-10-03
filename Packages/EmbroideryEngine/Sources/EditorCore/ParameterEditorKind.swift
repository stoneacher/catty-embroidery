import ProgramModel

/// Which editor a parameter value gets (US-410): **editable where M4 has a
/// control, read-only where it does not** (decided at planning, 2026-09-19).
///
/// M4 has a number pad and a variable menu; the model has a formula tree. A
/// `.binary` or `.unaryMinus` formula — and a shipping sample holds several —
/// is shown but not edited until M6's formula editor exists, because the only
/// alternative, seeding the pad with its evaluated value and overwriting,
/// destroys a working program the first time someone looks at it.
public enum ParameterEditorKind: Sendable, Equatable {
    /// A literal: the number field, the stepper, and the switch to a variable.
    case number(Double)
    /// A variable reference: the variable menu, and the switch to a number.
    case variableReference(String)
    /// Shown, never written. The formula travels with it so the view renders
    /// exactly what is stored.
    case readOnlyFormula(Formula, reason: ReadOnlyFormulaReason)
    /// A `setVariable`/`changeVariableBy` target.
    case variableName(String)
    /// The curated thread palette (ADR-040).
    case threadColor(hex: String)
    /// `writeEmbroideryToFile`'s name.
    case fileName(String)

    public init(_ value: ParameterValue) {
        switch value {
        case let .formula(.number(number)):
            self = .number(number)
        case let .formula(.variable(name)):
            self = .variableReference(name)
        case let .formula(formula) where formula.isBinary:
            self = .readOnlyFormula(formula, reason: .binary)
        case let .formula(formula):
            // Every `.unaryMinus`, `.unaryMinus(.number(5))` included: the pad
            // writes `.number(-5)`, a different tree, so one rule — anything
            // the pad cannot write back byte-identically is read-only.
            self = .readOnlyFormula(formula, reason: .unaryMinus)
        case let .variableName(name):
            self = .variableName(name)
        case let .threadColor(hex):
            self = .threadColor(hex: hex)
        case let .fileName(name):
            self = .fileName(name)
        }
    }
}

/// Why a formula cannot be edited in M4 — the case the editor's localized
/// reason is chosen by.
public enum ReadOnlyFormulaReason: Sendable, Equatable {
    case binary
    case unaryMinus
}

private extension Formula {
    var isBinary: Bool {
        if case .binary = self {
            true
        } else {
            false
        }
    }
}
