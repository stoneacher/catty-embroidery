import Foundation
import ProgramModel

/// A `Formula` as the text a brick row shows (US-407).
///
/// **Every case renders**, through an exhaustive switch with no `default:`, so a fifth
/// `Formula` case is a compile error here rather than a placeholder on screen. Which of them are
/// *editable* is US-410's question; this type only reads.
///
/// **Operators come from the String Catalog as whole infix formats** (`formula.divide` is
/// `"%1$@ ÷ %2$@"`), not as glyphs concatenated between operands: German schools write division
/// as `:`, and a right-to-left language may order the operands differently.
///
/// **Parentheses are faithful to the tree, not minimal.** A pair is dropped only where the
/// conventional reading gives back the same tree:
/// - a left operand is bracketed when it binds more loosely than its parent;
/// - a right operand also when it binds *equally* loosely, since `+ − × ÷` associate left —
///   so `1 − (2 − 3)` keeps its parentheses. `^` associates right, and mirrors both rules;
/// - a negation or negative literal binds tighter than `+ − × ÷` and looser than `^`, so it is
///   bare as a left operand of the four (`−5 × 2`), bracketed as the base of a power
///   (`(−5) ^ 2`) and under another negation (`−(−a)`) — and **always** bracketed as a right
///   operand, `1 − (−5)`, because `1 − −5` reads as a typo to a child.
///
/// Numbers use the injected locale's decimal separator and **no grouping**: the plural brick
/// labels print their counts through `%lld`, which never groups, and one value spelled `1000`
/// in one row and `1,000` in the next would be two spellings on one screen. Up to six decimals
/// inside `[1e-6, 1e15)`, scientific outside it, so a non-zero value never reads as "0" and a
/// huge one is not a line of digits; `-0` reads as `0`.
nonisolated enum FormulaText {
    static func text(for formula: Formula, locale: Locale = .current) -> String {
        Renderer(locale: locale).render(formula)
    }

    /// Whole-number literals that a plural brick label may print through its `%lld` form.
    ///
    /// Non-negative only: `%lld` prints a hyphen-minus, where `FormulaText` prints U+2212, and
    /// the plural category of a negative count is not something every language defines.
    static func count(of formula: Formula) -> Int? {
        guard case let .number(value) = formula,
              value >= 0, value == value.rounded(), value < 1e15
        else { return nil }
        return Int(value)
    }
}

nonisolated private struct Renderer {
    let locale: Locale

    /// How tightly a node binds. Higher binds tighter.
    private enum Level: Int, Comparable {
        case additive = 1, multiplicative, negation, power, leaf

        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    func render(_ formula: Formula) -> String {
        switch formula {
        case var .number(value):
            // `-0.0 == 0`, so this turns negative zero into zero and leaves everything else alone.
            if value == 0 { value = 0 }
            if value < 0 {
                return resolve(.formulaNegate(number(-value)))
            }
            return number(value)
        case let .variable(name):
            return name.isEmpty ? resolve(.scriptVariablePlaceholder) : name
        case let .binary(operation, left, right):
            let parent = level(of: formula)
            let rightAssociative = operation == .pow
            let leftText = operand(left, bracketed: rightAssociative
                ? level(of: left) <= parent
                : level(of: left) < parent)
            let rightText = operand(right, bracketed: level(of: right) == .negation
                || (rightAssociative ? level(of: right) < parent : level(of: right) <= parent))
            return resolve(format(operation, leftText, rightText))
        case let .unaryMinus(operand):
            return resolve(.formulaNegate(self.operand(operand, bracketed: level(of: operand) < .leaf)))
        }
    }

    private func operand(_ formula: Formula, bracketed: Bool) -> String {
        bracketed ? resolve(.formulaGroup(render(formula))) : render(formula)
    }

    private func level(of formula: Formula) -> Level {
        switch formula {
        case let .number(value): value < 0 ? .negation : .leaf
        case .variable: .leaf
        case .unaryMinus: .negation
        case let .binary(operation, _, _):
            switch operation {
            case .plus, .minus: .additive
            case .mult, .divide: .multiplicative
            case .pow: .power
            }
        }
    }

    private func format(_ operation: BinaryOperator, _ left: String, _ right: String) -> LocalizedStringResource {
        switch operation {
        case .plus: .formulaPlus(left, right)
        case .minus: .formulaMinus(left, right)
        case .mult: .formulaMult(left, right)
        case .divide: .formulaDivide(left, right)
        case .pow: .formulaPow(left, right)
        }
    }

    /// `value` is never negative here: `render` has already taken the sign off.
    private func number(_ value: Double) -> String {
        let plain = FloatingPointFormatStyle<Double>.number.grouping(.never).locale(locale)
        if value != 0, value < 1e-6 || value >= 1e15 {
            return value.formatted(plain.notation(.scientific))
        }
        return value.formatted(plain.precision(.fractionLength(0 ... 6)))
    }

    private func resolve(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }
}
