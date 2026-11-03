import ProgramModel

/// What a brick does with a formula's root value, which decides how a string
/// literal at the root is read (brief D4).
package enum FormulaSlot: Sendable {
    /// Read as a number: `Formula.interpretDouble` and its narrowings.
    case number
    /// An AssertEquals operand, compared as text or number (`AssertAction.kt:45-50`).
    case assertOperand
    /// The value a SetVariable stores, kept as a string unless it parses
    /// (`SetVariableAction.kt:49-64`).
    case variableValue
}

/// Catroid's `FormulaElement` tree (`code.xml`'s `<formula>`) to a `Formula`
/// (language-test runner brief, D4 and slice 3).
///
/// Every `Formula` vocabulary case is reached from its Catroid name. A literal is
/// read by the position it sits in, mirroring the three different string
/// conversions Catroid applies there; where Catroid would keep a string as a
/// string, the import is refused, because `Formula` values are `Double` only
/// (ADR-048). Every blocker is collected, not just the first, across every
/// supported node; nothing below an unsupported function or element type is
/// visited, since that node already names what the formula needs.
///
/// `package` for the tests; the import's consumer API is `ProgramImport.program(fromCodeXML:)`,
/// the `Imported*` types, `ImportBlocker` and `CatrobatImportError`.
package enum FormulaImport {
    /// ADR-037's cap, in produced `Formula` nodes on the longest path (a literal is 1).
    package static let maximumDepth = 128

    /// The formula `element` describes, or `nil` with the reasons appended to
    /// `blockers`.
    package static func formula(
        from element: XMLTree.Element,
        slot: FormulaSlot,
        blockers: inout [ImportBlocker]
    ) -> Formula? {
        // Checked before any recursion, so no input depth reaches the recursive
        // path. Before the per-type split, 128 levels of `convert` overflowed a
        // 512 KB cooperative-pool stack in a debug build; now 240 pass (slice 3).
        guard nesting(of: element) <= maximumDepth else {
            blockers.append(.formulaTooDeep)
            return nil
        }
        var found: [ImportBlocker] = []
        let formula = convert(element, at: .root(slot), blockers: &found)
        blockers += found
        return found.isEmpty ? formula : nil
    }

    // MARK: - Positions

    /// Where a node sits, which decides how a literal there is read.
    enum Position {
        case root(FormulaSlot)
        /// An arithmetic, ordering or logic operand: `tryInterpretDoubleValue`
        /// (`FormulaElementOperations.kt:79-88`), NaN on failure.
        case operand
        /// An operand of `=`/`≠`: compared as strings when it does not parse
        /// (`FormulaElementOperations.kt:67-75`).
        case equalityOperand
    }

    // MARK: - Nodes

    /// Children that Catroid writes but that are always empty in the supported subset.
    static let emptyByContract: Set = ["additionalChildren", "textBlockFunctionProvider"]

    static let knownChildren: Set = [
        "leftChild", "rightChild", "additionalChildren", "type", "value", "textBlockFunctionProvider"
    ]

    /// Formula nodes on the longest path through `leftChild`/`rightChild`,
    /// brackets included, found without recursion; stops counting past the cap.
    /// Counting brackets makes this at least the produced depth ADR-037 caps, so
    /// it is stricter there, and it is what bounds `convert`'s recursion.
    static func nesting(of element: XMLTree.Element) -> Int {
        var deepest = 0
        var pending = [(element, 1)]
        while let (node, depth) = pending.popLast() {
            deepest = max(deepest, depth)
            guard depth <= maximumDepth else { break }
            for child in node.children where child.name == "leftChild" || child.name == "rightChild" {
                pending.append((child, depth + 1))
            }
        }
        return deepest
    }

    /// Dispatches on the element type. Kept small, because it is on every level
    /// of the recursion; each type's work is in its own function.
    private static func convert(
        _ element: XMLTree.Element,
        at position: Position,
        blockers: inout [ImportBlocker]
    ) -> Formula? {
        guard let type = element.child("type")?.text else {
            blockers.append(.formulaShape("no type"))
            return nil
        }
        if type == "FUNCTION", isUnsupportedFunction(element, blockers: &blockers) { return nil }
        guard shapeIsKnown(element, blockers: &blockers) else { return nil }
        if let text = literalText(of: element) {
            return literal(text, at: position, blockers: &blockers)
        }
        switch type {
        case "NUMBER", "STRING":
            // No `<value>` at all: Catroid's `return value` is null, which
            // `normalizeDegeneratedDoubleValues` turns into 0.0.
            return .number(0)
        case "BRACKET":
            return bracket(element, at: position, blockers: &blockers)
        case "OPERATOR":
            return op(element, blockers: &blockers)
        case "FUNCTION":
            return function(element, blockers: &blockers)
        default:
            return leaf(element, type: type, blockers: &blockers)
        }
    }

    /// An unsupported function is named as itself, before its shape: Catroid's
    /// ternary functions (COLOR_EQUALS_COLOR, IF_THEN_ELSE, JOIN3) are the only
    /// writers of a non-empty `additionalChildren`, and "needs IF_THEN_ELSE" is
    /// the useful answer.
    private static func isUnsupportedFunction(_ element: XMLTree.Element, blockers: inout [ImportBlocker]) -> Bool {
        let name = element.child("value")?.text ?? ""
        guard !CatroidNames.isFunction(name) else { return false }
        blockers.append(.function(name))
        return true
    }

    private static func bracket(
        _ element: XMLTree.Element,
        at position: Position,
        blockers: inout [ImportBlocker]
    ) -> Formula? {
        guard let inner = element.child("rightChild") else {
            blockers.append(.formulaShape("BRACKET"))
            return nil
        }
        return convert(inner, at: position, blockers: &blockers)
    }

    /// USER_VARIABLE, SENSOR, and every unsupported element type.
    private static func leaf(_ element: XMLTree.Element, type: String, blockers: inout [ImportBlocker]) -> Formula? {
        switch type {
        case "USER_VARIABLE":
            guard let name = element.child("value")?.text else {
                blockers.append(.formulaShape("USER_VARIABLE"))
                return nil
            }
            return .variable(name)
        case "SENSOR":
            let name = element.child("value")?.text ?? ""
            guard let sensor = CatroidNames.sensors[name] else {
                blockers.append(.sensor(name))
                return nil
            }
            return .sensor(sensor)
        default:
            blockers.append(.elementType(type))
            return nil
        }
    }

    /// Children Catroid's serialiser writes, with `additionalChildren` and
    /// `textBlockFunctionProvider` empty (they always are for the supported subset).
    /// `shapeIsKnown` without reporting: every child known, the contract ones empty.
    static func shapeIsClean(_ element: XMLTree.Element) -> Bool {
        element.children.allSatisfy { child in
            knownChildren.contains(child.name) && (!emptyByContract.contains(child.name) || child.children.isEmpty)
        }
    }

    private static func shapeIsKnown(_ element: XMLTree.Element, blockers: inout [ImportBlocker]) -> Bool {
        var known = true
        for child in element.children {
            if !knownChildren.contains(child.name) {
                blockers.append(.formulaShape(child.name))
                known = false
            } else if emptyByContract.contains(child.name), !child.children.isEmpty {
                blockers.append(.formulaShape(child.name))
                known = false
            }
        }
        return known
    }

    /// Binary when there is a left child, unary otherwise, as Catroid decides
    /// (`FormulaElement.java:791-797`).
    private static func op(_ element: XMLTree.Element, blockers: inout [ImportBlocker]) -> Formula? {
        let name = element.child("value")?.text ?? ""
        let binaryOperator = CatroidNames.binaryOperators[name]
        guard binaryOperator != nil || name == "LOGICAL_NOT" else {
            blockers.append(.operatorName(name))
            return nil
        }
        guard let right = element.child("rightChild") else {
            blockers.append(.formulaShape("OPERATOR " + name))
            return nil
        }
        guard let left = element.child("leftChild") else {
            // Catroid's unary operators are MINUS and LOGICAL_NOT; any other
            // returns 0. The editor never writes one, so it is refused.
            let wrap: (Formula) -> Formula
            switch name {
            case "MINUS": wrap = Formula.unaryMinus
            case "LOGICAL_NOT": wrap = Formula.logicalNot
            default:
                blockers.append(.formulaShape("OPERATOR " + name))
                return nil
            }
            return convert(right, at: .operand, blockers: &blockers).map(wrap)
        }
        // A LOGICAL_NOT with a left child takes Catroid's binary path and returns 0;
        // never written by the editor, so refused rather than mirrored.
        guard let binaryOperator else {
            blockers.append(.formulaShape("OPERATOR " + name))
            return nil
        }
        let position: Position = binaryOperator == .equal || binaryOperator == .notEqual
            ? .equalityOperand : .operand
        let first = convert(left, at: position, blockers: &blockers)
        let second = convert(right, at: position, blockers: &blockers)
        guard let first, let second else { return nil }
        return .binary(binaryOperator, first, second)
    }

    private static func function(_ element: XMLTree.Element, blockers: inout [ImportBlocker]) -> Formula? {
        let name = element.child("value")?.text ?? ""
        // Catroid evaluates both child positions before it dispatches
        // (`FormulaElement.java:445-451`), so a child whose value is then ignored
        // must still be one it can evaluate.
        if let constant = CatroidNames.constants[name] {
            let left = functionArgument(element.child("leftChild"), blockers: &blockers)
            let right = functionArgument(element.child("rightChild"), blockers: &blockers)
            return left.isBlocked || right.isBlocked ? nil : .constant(constant)
        }
        if let unary = CatroidNames.unaryFunctions[name] {
            let argument = functionArgument(element.child("leftChild"), blockers: &blockers)
            let ignored = functionArgument(element.child("rightChild"), blockers: &blockers)
            switch (argument, ignored.isBlocked) {
            case (.blocked, _), (_, true): return nil
            case let (.value(argument), false): return .unaryFunction(unary, argument)
            case (.null, false): return .number(0)
            }
        }
        if let binary = CatroidNames.binaryFunctions[name] {
            let first = functionArgument(element.child("leftChild"), blockers: &blockers)
            let second = functionArgument(element.child("rightChild"), blockers: &blockers)
            switch (first, second) {
            case let (.value(first), .value(second)):
                return .binaryFunction(binary, first, second)
            case (.blocked, _), (_, .blocked):
                return nil
            default:
                return .number(0)
            }
        }
        blockers.append(.function(name))
        return nil
    }

    private enum Argument {
        case value(Formula)
        /// Catroid passes null: the call returns 0.0 (`UnaryFunction.kt`, `BinaryFunction.kt`).
        case null
        case blocked

        var isBlocked: Bool {
            if case .blocked = self { true } else { false }
        }
    }

    /// A function argument: missing, or a literal `tryParseDouble` rejects, is null;
    /// anything else is converted as an operand (a Double in Catroid, never null).
    private static func functionArgument(
        _ element: XMLTree.Element?,
        blockers: inout [ImportBlocker]
    ) -> Argument {
        guard let element else { return .null }
        if let text = literalText(of: element) {
            guard let value = JavaDouble.parseArgument(text) else { return .null }
            guard value.isFinite || value.isNaN else {
                blockers.append(.nonFiniteLiteral(text))
                return .blocked
            }
            return .value(.number(value))
        }
        let before = blockers.count
        guard let formula = convert(element, at: .operand, blockers: &blockers) else {
            return blockers.count > before ? .blocked : .null
        }
        return .value(formula)
    }
}

extension XMLTree.Element {
    /// The first child element called `name`.
    func child(_ name: String) -> XMLTree.Element? {
        children.first { $0.name == name }
    }
}
