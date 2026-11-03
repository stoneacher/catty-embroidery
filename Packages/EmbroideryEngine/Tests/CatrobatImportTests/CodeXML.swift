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
        program(variables: variables, objects: [object(variables: objectVariables, scripts: [script(bricks)])])
    }
}

// swiftlint:enable function_default_parameter_at_end

/// The program import, seen as a result or as its blockers.
protocol ProgramImportTesting {}

extension ProgramImportTesting {
    func imported(_ xml: String) throws -> ImportedProgram {
        try CatrobatImport.program(fromCodeXML: Data(xml.utf8))
    }

    func blockers(_ xml: String) -> Set<ImportBlocker> {
        do {
            _ = try CatrobatImport.program(fromCodeXML: Data(xml.utf8))
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
