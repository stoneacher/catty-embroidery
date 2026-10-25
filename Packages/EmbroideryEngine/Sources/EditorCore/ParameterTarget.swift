import ProgramModel

/// One side of a comparison, in reading order (Variables slice 7).
public enum ComparisonSide: Sendable, Hashable, CaseIterable {
    case first, second
}

/// What one control of the parameter editor edits: a whole slot, or one side of the comparison
/// a condition slot holds (Variables slice 7). The number and variable controls take a target,
/// so a comparison's sides reuse them rather than copies of them.
public enum ParameterTarget: Sendable, Hashable {
    case slot(ParameterSlot)
    case operand(ParameterSlot, ComparisonSide)

    /// The slot the target lives in.
    public var slot: ParameterSlot {
        switch self {
        case let .slot(slot), let .operand(slot, _): slot
        }
    }
}

/// An editable comparison: two plain values around a comparison operator (brief D16).
struct EditableComparison: Equatable {
    let lhs: Formula
    let relation: ComparisonOperator
    let rhs: Formula

    init?(_ formula: Formula) {
        guard case let .binary(operation, lhs, rhs) = formula,
              let relation = ComparisonOperator(operation),
              Self.isPlain(lhs), Self.isPlain(rhs)
        else { return nil }
        self.lhs = lhs
        self.relation = relation
        self.rhs = rhs
    }

    init(lhs: Formula, relation: ComparisonOperator, rhs: Formula) {
        self.lhs = lhs
        self.relation = relation
        self.rhs = rhs
    }

    var formula: Formula {
        .binary(relation.binaryOperator, lhs, rhs)
    }

    func side(_ side: ComparisonSide) -> Formula {
        side == .first ? lhs : rhs
    }

    func replacing(_ side: ComparisonSide, with operand: Formula) -> Self {
        side == .first
            ? Self(lhs: operand, relation: relation, rhs: rhs)
            : Self(lhs: lhs, relation: relation, rhs: operand)
    }

    /// A number or a variable reference: what the number and variable controls write.
    static func isPlain(_ formula: Formula) -> Bool {
        switch formula {
        case .number, .variable: true
        default: false
        }
    }
}

public extension Brick {
    /// The value a target addresses, or `nil` where the brick has no such slot — or, for a side,
    /// where the slot does not hold an editable comparison.
    func value(at target: ParameterTarget) -> ParameterValue? {
        let value = parameters.first { $0.slot == target.slot }?.value
        guard case let .operand(_, side) = target else { return value }
        guard case let .formula(formula)? = value, let comparison = EditableComparison(formula) else { return nil }
        return .formula(comparison.side(side))
    }

    /// The brick with one target replaced. A side takes only a number or a variable reference,
    /// and only in a slot that holds an editable comparison, so the comparison editor can never
    /// write a tree it would then lock, nor rewrite one that is locked. Same kind, always.
    func replacing(_ target: ParameterTarget, with value: ParameterValue) -> Brick? {
        guard case let .operand(slot, side) = target else { return replacing(target.slot, with: value) }
        guard case let .formula(operand) = value, EditableComparison.isPlain(operand),
              case let .formula(formula)? = self.value(at: .slot(slot)),
              let comparison = EditableComparison(formula)
        else { return nil }
        return replacing(slot, with: .formula(comparison.replacing(side, with: operand).formula))
    }

    /// The brick with its comparison's operator changed and both sides kept, or `nil` where the
    /// slot does not hold an editable comparison.
    func replacingComparisonOperator(in slot: ParameterSlot, with relation: ComparisonOperator) -> Brick? {
        guard case let .formula(formula)? = value(at: .slot(slot)),
              let comparison = EditableComparison(formula)
        else { return nil }
        let changed = EditableComparison(lhs: comparison.lhs, relation: relation, rhs: comparison.rhs)
        return replacing(slot, with: .formula(changed.formula))
    }
}
