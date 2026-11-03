import ProgramModel

extension FormulaImport {
    // MARK: - Literals

    /// The text of a NUMBER or STRING with a `<value>`, seen through any BRACKETs:
    /// Catroid's BRACKET returns its child's value unchanged, string included.
    /// Not past a node whose shape `convert` would refuse (a non-empty
    /// `additionalChildren`, which Catroid's BRACKET would read instead, or an unknown
    /// child): such a node goes the long way and is refused there.
    static func literalText(of element: XMLTree.Element) -> String? {
        guard shapeIsClean(element) else { return nil }
        switch element.child("type")?.text {
        case "NUMBER", "STRING":
            return element.child("value")?.text
        case "BRACKET":
            return element.child("rightChild").flatMap(literalText(of:))
        default:
            return nil
        }
    }

    static func literal(_ text: String, at position: Position, blockers: inout [ImportBlocker]) -> Formula? {
        let refusal: StringContext?
        let parsed: Double?
        switch position {
        case .root(.number), .operand:
            refusal = nil
            parsed = JavaDouble.parse(text)
        case .root(.assertOperand):
            refusal = .assertOperand
            parsed = JavaDouble.parse(text)
        case .equalityOperand:
            refusal = .equality
            parsed = JavaDouble.parse(text)
        case .root(.variableValue):
            refusal = .variableValue
            parsed = JavaDouble.parseArgument(text)
        }
        guard let parsed else {
            if let refusal {
                blockers.append(.stringValue(refusal))
                return nil
            }
            return .number(.nan)
        }
        // An AssertEquals NaN matches only through the string test: Kotlin's
        // `Double ==` is IEEE, and a computed NaN prints as exactly "NaN"
        // (`AssertAction.kt:45-50`). Any other spelling of NaN matches nothing.
        if case .root(.assertOperand) = position, parsed.isNaN, text != "NaN" {
            blockers.append(.stringValue(.assertOperand))
            return nil
        }
        guard parsed.isFinite || parsed.isNaN else {
            blockers.append(.nonFiniteLiteral(text))
            return nil
        }
        return .number(parsed)
    }
}
