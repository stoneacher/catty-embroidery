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
    /// Arc's left/right choice: one discrete edit, nothing to coalesce.
    case arcDirection(ArcDirection)
    /// A condition that is one comparison of two plain values (a number or a variable each):
    /// the operator picker and a number/variable control per side (Variables slice 7, D16).
    case comparison(lhs: Formula, relation: ComparisonOperator, rhs: Formula)

    /// The editor for a parameter. Only a condition slot offers the comparison editor (D16): the
    /// same `1 < 2` in Move's steps is a calculation's operand and stays locked.
    public init(_ parameter: BrickParameter) {
        if parameter.slot == .condition, case let .formula(formula) = parameter.value,
           let comparison = EditableComparison(formula) {
            self = .comparison(lhs: comparison.lhs, relation: comparison.relation, rhs: comparison.rhs)
        } else {
            self.init(parameter.value)
        }
    }

    public init(_ value: ParameterValue) {
        switch value {
        case let .formula(formula):
            // Exhaustive over `Formula` with no `default:`, so M6's next case
            // is a compile error here rather than a silently mislabelled lock.
            switch formula {
            case let .number(number):
                self = .number(number)
            case let .variable(name):
                self = .variableReference(name)
            case let .binary(operation, _, _):
                // The root decides (brief D16): a sum of comparisons is a calculation.
                self = .readOnlyFormula(formula, reason: operation.isArithmetic ? .binary : .logic)
            case .unaryMinus:
                // Every `.unaryMinus`, `.unaryMinus(.number(5))` included: the
                // pad writes `.number(-5)`, a different tree, so one rule —
                // anything the pad cannot write back byte-identically is
                // read-only.
                self = .readOnlyFormula(formula, reason: .unaryMinus)
            case .logicalNot, .constant(.true), .constant(.false):
                self = .readOnlyFormula(formula, reason: .logic)
            case .unaryFunction, .binaryFunction, .constant(.pi):
                // No UI path writes a call yet (brief D9).
                self = .readOnlyFormula(formula, reason: .function)
            case .sensor:
                self = .readOnlyFormula(formula, reason: .sensor)
            }
        case let .variableName(name):
            self = .variableName(name)
        case let .threadColor(hex):
            self = .threadColor(hex: hex)
        case let .fileName(name):
            self = .fileName(name)
        case let .arcDirection(direction):
            self = .arcDirection(direction)
        }
    }
}

/// Why a formula cannot be edited in M4 — the case the editor's localized
/// reason is chosen by.
public enum ReadOnlyFormulaReason: Sendable, Equatable {
    case binary
    case unaryMinus
    /// A math function call or `pi` (Brick backend, ADR-040 amendment).
    case function
    /// A value read from the object, such as its x position.
    case sensor
    /// A condition the comparison editor cannot show: `and`, `or`, `not`, `true` or `false` at
    /// the root, a comparison of anything but two plain values, or a comparison outside a
    /// condition slot (Variables brief D16, slice 7).
    case logic
}
