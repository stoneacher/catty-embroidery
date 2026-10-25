import ProgramModel

/// The comparison editor's operator picker (Variables slice 7, brief D16): the six comparisons
/// of `BinaryOperator`, in Catroid's order (`Operators.java`), and nothing else, so the picker
/// can never write an arithmetic or logical root.
public enum ComparisonOperator: Sendable, Hashable, CaseIterable {
    case equal, notEqual, smallerThan, smallerOrEqual, greaterThan, greaterOrEqual

    /// The comparison a formula operator is, or `nil` for arithmetic and `and`/`or`.
    public init?(_ operation: BinaryOperator) {
        switch operation {
        case .equal: self = .equal
        case .notEqual: self = .notEqual
        case .smallerThan: self = .smallerThan
        case .smallerOrEqual: self = .smallerOrEqual
        case .greaterThan: self = .greaterThan
        case .greaterOrEqual: self = .greaterOrEqual
        case .plus, .minus, .mult, .divide, .pow, .logicalAnd, .logicalOr: return nil
        }
    }

    /// The formula operator this comparison writes into a condition's root. The inverse of
    /// `init?(_:)` over the six comparisons.
    public var binaryOperator: BinaryOperator {
        switch self {
        case .equal: .equal
        case .notEqual: .notEqual
        case .smallerThan: .smallerThan
        case .smallerOrEqual: .smallerOrEqual
        case .greaterThan: .greaterThan
        case .greaterOrEqual: .greaterOrEqual
        }
    }
}
