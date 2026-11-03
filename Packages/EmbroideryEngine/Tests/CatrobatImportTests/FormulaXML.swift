import CatrobatImport
import Foundation
import ProgramModel
import Testing

/// Catroid `<formula>` XML, built for the formula import tests.
enum FormulaXML {
    /// A formula node as Catroid serialises it: children, `<additionalChildren/>`,
    /// `<type>`, then `<value>` (`nil` omits it).
    static func node(_ type: String, _ value: String? = nil, left: String? = nil, right: String? = nil) -> String {
        var xml = "<formula>"
        if let left { xml += "<leftChild>\(inner(left))</leftChild>" }
        if let right { xml += "<rightChild>\(inner(right))</rightChild>" }
        xml += "<additionalChildren/><type>\(type)</type>"
        if let value { xml += "<value>\(value)</value>" }
        return xml + "</formula>"
    }

    /// A node's content without its `<formula>` wrapper, to nest it as a child.
    static func inner(_ node: String) -> String {
        String(node.dropFirst("<formula>".count).dropLast("</formula>".count))
    }

    static func number(_ value: String) -> String { node("NUMBER", value) }
    static func string(_ value: String) -> String { node("STRING", value) }
    static func op(_ name: String, _ left: String?, _ right: String?) -> String {
        node("OPERATOR", name, left: left, right: right)
    }

    static func function(_ name: String, _ left: String? = nil, _ right: String? = nil) -> String {
        node("FUNCTION", name, left: left, right: right)
    }
}

/// The import entry point, seen three ways.
protocol FormulaImportTesting {}

extension FormulaImportTesting {
    func imported(_ xml: String, slot: FormulaSlot = .number) throws -> (Formula?, [ImportBlocker]) {
        let element = try XMLTree(parsing: Data(xml.utf8)).root
        var blockers: [ImportBlocker] = []
        let formula = FormulaImport.formula(from: element, slot: slot, blockers: &blockers)
        return (formula, blockers)
    }

    /// The formula, with an issue if anything blocked it.
    func formula(_ xml: String, slot: FormulaSlot = .number) throws -> Formula {
        let (formula, blockers) = try imported(xml, slot: slot)
        #expect(blockers.isEmpty, "unexpected blockers \(blockers)")
        return try #require(formula)
    }

    /// The blockers, with an issue if a formula was still produced.
    func blockers(_ xml: String, slot: FormulaSlot = .number) throws -> Set<ImportBlocker> {
        let (formula, blockers) = try imported(xml, slot: slot)
        #expect(formula == nil, "a blocked formula imports as nil")
        return Set(blockers)
    }

    func isNegativeZero(_ formula: Formula) -> Bool {
        if case let .number(value) = formula { value == 0 && value.sign == .minus } else { false }
    }
}
