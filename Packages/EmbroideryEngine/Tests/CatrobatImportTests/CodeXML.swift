import CatrobatImport
import Foundation
import ProgramModel
import Testing

// The builders take their defaulted parameters first so calls read in document
// order (`program(version:…, objects:)`, `script(type, bricks)`).
// swiftlint:disable function_default_parameter_at_end
/// Catroid `code.xml` documents, built in the shapes the corpus uses (slice 4):
/// variables in XStream's `custom` form, bricks as `<brick type="…">` with a
/// `formulaList`, loops and Ifs with their nested brick lists.
enum CodeXML {
    static func program(
        version: String = "1.12",
        name: String = "Test",
        variables: [String] = [],
        objects: [String],
        scenes: Int = 1,
        extra: String = ""
    ) -> String {
        let scene = "<scene><name>Scene 1</name><objectList>\(objects.joined())</objectList></scene>"
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
        <program><header><catrobatLanguageVersion>\(version)</catrobatLanguageVersion>\
        <programName>\(name)</programName></header>\
        <settings/><scenes>\(String(repeating: scene, count: scenes))</scenes>\
        <programVariableList>\(variables.joined())</programVariableList>\
        <programListOfLists/><programMultiplayerVariableList/>\(extra)</program>
        """
    }

    static func object(_ name: String = "Sprite", variables: [String] = [], scripts: [String]) -> String {
        "<object type=\"Sprite\" name=\"\(name)\"><lookList/><soundList/>"
            + "<scriptList>\(scripts.joined())</scriptList><nfcTagList/>"
            + "<userVariables>\(variables.joined())</userVariables><userLists/></object>"
    }

    static func script(_ type: String = "StartScript", commentedOut: Bool = false, _ bricks: [String]) -> String {
        "<script type=\"\(type)\"><brickList>\(bricks.joined())</brickList>"
            + "<commentedOut>\(commentedOut)</commentedOut></script>"
    }

    static func script(_ bricks: [String]) -> String {
        script("StartScript", bricks)
    }

    /// A variable in XStream's custom form, as Catroid ≥ 0.99995 writes it.
    static func variable(_ name: String) -> String {
        "<userVariable type=\"UserVariable\" serialization=\"custom\"><userVariable><default>"
            + "<deviceValueKey>key-\(name)</deviceValueKey><name>\(name)</name></default></userVariable></userVariable>"
    }

    static func reference(_ path: String) -> String {
        "<userVariable reference=\"\(path)\"/>"
    }

    /// `formulas` are (category, `FormulaXML` node) pairs; `lists` are a nested
    /// brick list's tag and bricks, e.g. `("loopBricks", [...])`.
    static func brick(
        _ type: String,
        commentedOut: Bool = false,
        formulas: [(String, String)] = [],
        variable: String? = nil,
        lists: [(String, [String])] = [],
        extra: String = ""
    ) -> String {
        var xml = "<brick type=\"\(type)\"><brickId>id</brickId><commentedOut>\(commentedOut)</commentedOut>"
        if !formulas.isEmpty {
            xml += "<formulaList>"
            for (category, node) in formulas {
                xml += "<formula category=\"\(category)\">\(FormulaXML.inner(node))</formula>"
            }
            xml += "</formulaList>"
        }
        for (tag, bricks) in lists {
            xml += "<\(tag)>\(bricks.joined())</\(tag)>"
        }
        if let variable {
            xml += variable
        }
        return xml + extra + "</brick>"
    }

    static func number(_ value: String) -> String {
        FormulaXML.number(value)
    }

    static func finish() -> String {
        brick("FinishStageBrick")
    }

    /// A one-object, one-script program around `bricks`.
    static func run(_ bricks: [String], variables: [String] = [], objectVariables: [String] = []) -> String {
        let only = object(variables: objectVariables, scripts: [script(bricks)])
        return declaringUses(program(variables: variables, objects: [only]))
    }

    /// Writes variables the way Catroid does: inline at a variable's first use,
    /// every later use a reference back to it, and the object's `userVariables`
    /// referencing the first use (a forward reference is invalid). Uses of a
    /// name some list already declares are left alone.
    static func declaringUses(_ xml: String) -> String {
        guard let tree = try? XMLTree(parsing: Data(xml.utf8)) else { return xml }
        let declared = Set(tree.addresses { $0.name == "programVariableList" || $0.name == "userVariables" }
            .flatMap { list in (tree[list]?.children.indices ?? 0 ..< 0).map { list.path + [$0] } }
            .compactMap { try? tree.dereference(XMLTree.Address(path: $0)) }
            .compactMap { name(of: $0, in: tree) })
        var result = xml
        var cursor = result.startIndex
        for object in tree.addresses(where: { $0.name == "object" && $0.attributes["reference"] == nil }) {
            guard let element = tree[object],
                  let listIndex = element.children.firstIndex(where: { $0.name == "userVariables" }),
                  let scripts = element.children.firstIndex(where: { $0.name == "scriptList" })
            else { continue }
            let existing = element.children[listIndex].children.count
            var first: [String: [Int]] = [:]
            var order: [String] = []
            let uses = tree.addresses { use in use.name == "userVariable" && use.attributes["reference"] == nil }
                .filter { $0.path.starts(with: object.path + [scripts]) && isBrickChild($0, in: tree) }
            for use in uses {
                guard let name = name(of: use, in: tree), !declared.contains(name),
                      let use0 = tree[use]
                else { continue }
                let text = use0.children.isEmpty ? "<userVariable>\(name)</userVariable>" : variable(name)
                guard let range = result.range(of: text, range: cursor ..< result.endIndex) else {
                    Issue.record("declaringUses: no `\(text)` after the cursor; the fixture was not built by CodeXML")
                    continue
                }
                if let target = first[name] {
                    let path = relativePath(from: use.path, to: target, in: tree)
                    let reference = "<userVariable reference=\"\(path)\"/>"
                    result.replaceSubrange(range, with: reference)
                    cursor = result.index(range.lowerBound, offsetBy: reference.count)
                } else {
                    first[name] = use.path
                    order.append(name)
                    cursor = range.upperBound
                }
            }
            var references = ""
            for (offset, name) in order.enumerated() {
                let source = object.path + [listIndex, existing + offset]
                references += "<userVariable reference=\"\(relativePath(from: source, to: first[name]!, in: tree))\"/>"
            }
            guard let close = result.range(of: "</userVariables>", range: cursor ..< result.endIndex) else { break }
            result.replaceSubrange(close, with: references + "</userVariables>")
            cursor = result.index(close.lowerBound, offsetBy: references.count + "</userVariables>".count)
        }
        return result
    }

    private static func isBrickChild(_ address: XMLTree.Address, in tree: XMLTree) -> Bool {
        guard let parent = tree[XMLTree.Address(path: Array(address.path.dropLast()))] else { return false }
        return parent.name == "brick" || parent.name.hasSuffix("Brick")
    }

    private static func name(of address: XMLTree.Address, in tree: XMLTree) -> String? {
        guard let element = tree[address] else { return nil }
        if element.children.isEmpty { return element.text }
        let inner = element.children.first { $0.name == "userVariable" } ?? element
        return inner.children.first { $0.name == "default" }?.children.first { $0.name == "name" }?.text
    }

    /// XStream's relative path from `source` to `target`: `..` up to the common
    /// ancestor, then `name[n]` down, n counting same-named siblings from 1.
    private static func relativePath(from source: [Int], to target: [Int], in tree: XMLTree) -> String {
        var common = 0
        while common < min(source.count, target.count), source[common] == target[common] { common += 1 }
        var segments = Array(repeating: "..", count: source.count - common)
        for depth in common ..< target.count {
            guard let parent = tree[XMLTree.Address(path: Array(target[..<depth]))] else { break }
            let child = parent.children[target[depth]]
            let ordinal = parent.children[..<target[depth]].filter { $0.name == child.name }.count + 1
            segments.append(ordinal == 1 ? child.name : "\(child.name)[\(ordinal)]")
        }
        return segments.joined(separator: "/")
    }
}

// swiftlint:enable function_default_parameter_at_end

/// The program import, seen as a result or as its blockers.
protocol ProgramImportTesting {}

extension ProgramImportTesting {
    func imported(_ xml: String) throws -> ImportedProgram {
        try ProgramImport.program(fromCodeXML: Data(xml.utf8))
    }

    func blockers(_ xml: String) -> Set<ImportBlocker> {
        do {
            _ = try ProgramImport.program(fromCodeXML: Data(xml.utf8))
            Issue.record("expected the import to be refused")
            return []
        } catch {
            return error.blockers
        }
    }

    /// The steps of the only script of the only object.
    func steps(_ xml: String) throws -> [ImportedStep] {
        let program = try imported(xml)
        let object = try #require(program.objects.first)
        #expect(program.objects.count == 1)
        #expect(object.scripts.count == 1)
        return try #require(object.scripts.first).steps
    }
}
