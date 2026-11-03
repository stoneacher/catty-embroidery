import Foundation
import ProgramModel

/// Catroid `code.xml` to `ImportedProgram` (language-test runner brief, slice 4).
package enum ProgramImport {
    /// Brief D1: the 1.14 shape, which every version from 0.99995 on shares for
    /// the supported bricks.
    package static let supportedVersions: ClosedRange<Double> = 0.99995 ... 1.14

    package static func program(fromCodeXML data: Data) throws(CatrobatImportError) -> ImportedProgram {
        let tree: XMLTree
        do {
            tree = try XMLTree(parsing: data)
        } catch {
            throw CatrobatImportError(blockers: [.malformed])
        }
        var importer = ProgramImporter(tree: tree)
        let program = importer.run()
        guard importer.blockers.isEmpty, let program else {
            throw CatrobatImportError(blockers: Set(importer.blockers))
        }
        return program
    }
}

// MARK: - The importer

/// One pass over one tree, collecting blockers as it goes.
struct ProgramImporter {
    typealias Address = XMLTree.Address

    let tree: XMLTree
    var blockers: [ImportBlocker] = []
    /// Variables by identity: the element a `userVariable` dereferences to.
    /// Catroid binds a brick's variable by identity and reads by name (D7).
    var names: [Address: String] = [:]
    var projectScope: [String: Address] = [:]
    var objectScope: [String: Address] = [:]
    /// For the D4 storage rule, by identity: what each SetVariable stores (and,
    /// for a copy, from which variable), and which variables a ChangeVariable or
    /// ForVariableFromTo touches.
    var stored: [Stored] = []

    struct Stored {
        var identity: Address
        var storage: VariableStorage
        /// For a copy, the variable copied.
        var source: Address?
    }
    var changed: Set<Address> = []

    mutating func run() -> ImportedProgram? {
        let root = Address(path: [])
        guard tree.root.name == "program" else {
            blockers.append(.malformed)
            return nil
        }
        checkVersion()
        if let multiplayer = tree.root.child("programMultiplayerVariableList"), !multiplayer.children.isEmpty {
            blockers.append(.element("programMultiplayerVariableList"))
        }
        let scenes = children(of: root, named: "scenes").flatMap { children(of: $0, named: "scene") }
        guard let scene = scenes.first else {
            blockers.append(.malformed)
            return nil
        }
        if scenes.count > 1 {
            blockers.append(.multipleScenes)
        }

        let project = declarations(in: children(of: root, named: "programVariableList").first)
        projectScope = scope(of: project)
        let objects = children(of: scene, named: "objectList")
            .flatMap { children(of: $0, named: "object") }
            .map { importObject(at: $0) }
        checkStorage()
        return ImportedProgram(
            objects: objects,
            name: tree.root.child("header")?.child("programName")?.text ?? "",
            sceneName: tree[scene]?.child("name")?.text ?? "",
            variables: project.map { Variable(name: $0.name) }
        )
    }

    private mutating func checkVersion() {
        let text = tree.root.child("header")?.child("catrobatLanguageVersion")?.text ?? ""
        guard let version = Double(text), ProgramImport.supportedVersions.contains(version) else {
            blockers.append(.version(text))
            return
        }
    }

    private mutating func importObject(at address: Address) -> ImportedObject {
        let variables = declarations(in: children(of: address, named: "userVariables").first)
        objectScope = scope(of: variables)
        for name in Set(variables.map(\.name)) where projectScope[name] != nil {
            blockers.append(.variableShadowing(name))
        }
        let scripts = children(of: address, named: "scriptList")
            .flatMap { children(of: $0, named: "script") }
            .compactMap { importScript(at: $0) }
        return ImportedObject(
            name: tree[address]?.attributes["name"] ?? "",
            scripts: scripts,
            variables: variables.map { Variable(name: $0.name) }
        )
    }

    /// A commented-out script and an EmptyScript are skipped before anything in
    /// them is read (`content/Script.java:101`, brief D9).
    private mutating func importScript(at address: Address) -> ImportedScript? {
        guard let script = tree[address], !isCommentedOut(script) else { return nil }
        switch script.attributes["type"] ?? "" {
        case "StartScript":
            return ImportedScript(steps: flatten(children(of: address, named: "brickList").first))
        case "EmptyScript":
            return nil
        case let type:
            blockers.append(.script(type))
            return nil
        }
    }

    // MARK: Bricks

    private enum Work {
        case brick(Address)
        case marker(Brick)
    }

    /// The bricks under `list`, with nested lists flattened into ADR-008's paired
    /// form. Iterative, so nesting depth never reaches the call stack.
    private mutating func flatten(_ list: Address?) -> [ImportedStep] {
        var steps: [ImportedStep] = []
        var work = bricks(in: list).reversed().map(Work.brick)
        while let item = work.popLast() {
            switch item {
            case let .marker(brick):
                steps.append(.brick(brick))
            case let .brick(address):
                guard let element = tree[address], !isCommentedOut(element) else { continue }
                let (step, body) = importBrick(element, at: address)
                if let step {
                    steps.append(step)
                }
                work += body.reversed()
            }
        }
        return steps
    }

    /// The brick elements of a brick list, whatever their tag (a fully qualified
    /// tag is the same brick; its `type` attribute names it).
    private func bricks(in list: Address?) -> [Address] {
        guard let list, let element = tree[list] else { return [] }
        return element.children.indices.map { list.child($0) }
    }

    /// The brick's own step, if it has one, and the work its nested lists add.
    private mutating func importBrick(_ element: XMLTree.Element, at address: Address) -> (ImportedStep?, [Work]) {
        let type = element.attributes["type"] ?? String(element.name.split(separator: ".").last ?? "")
        var reader = BrickReader(element: element, type: type)
        defer {
            reader.refuseUnreadCategories()
            reader.refuseUnknownChildren()
            blockers += reader.blockers
        }
        switch type {
        case "NoteBrick":
            _ = reader.formulaElement("NOTE")
            return (nil, [])
        case "AssertEqualsBrick":
            let actual = reader.formula("ASSERT_EQUALS_ACTUAL", slot: .assertOperand)
            let expected = reader.formula("ASSERT_EQUALS_EXPECTED", slot: .assertOperand)
            guard let actual, let expected else { return (nil, []) }
            return (.assertEquals(actual: actual, expected: expected), [])
        case "FinishStageBrick": return (.finishStage, [])
        case "ExitStageBrick": return (.exitStage, [])
        case "WaitTillIdleBrick": return (.waitTillIdle, [])
        case "RepeatBrick", "ForeverBrick", "RepeatUntilBrick", "ForVariableFromToBrick",
             "IfLogicBeginBrick", "IfThenLogicBeginBrick":
            return controlBrick(type, at: address, reader: &reader)
        case "SetVariableBrick", "ChangeVariableBrick":
            return (dataBrick(type, at: address, reader: &reader).map(ImportedStep.brick), [])
        default:
            return (reader.leaf().map(ImportedStep.brick), [])
        }
    }

    /// Loops and Ifs: the opener, then its nested lists with ADR-008's markers.
    private mutating func controlBrick(
        _ type: String, at address: Address, reader: inout BrickReader
    ) -> (ImportedStep?, [Work]) {
        func body(_ tag: String) -> [Work] {
            bricks(in: children(of: address, named: tag).first).map(Work.brick)
        }
        func loop(_ opener: Brick?) -> (ImportedStep?, [Work]) {
            (opener.map(ImportedStep.brick), body("loopBricks") + [.marker(.loopEnd)])
        }
        switch type {
        case "RepeatBrick":
            return loop(reader.formula("TIMES_TO_REPEAT").map { .repeatLoop(times: $0) })
        case "ForeverBrick":
            return loop(.forever)
        case "RepeatUntilBrick":
            return loop(reader.formula("REPEAT_UNTIL_CONDITION").map { .repeatUntil(condition: $0) })
        case "ForVariableFromToBrick":
            let variable = variable(of: address, reader: &reader)
            let from = reader.formula("FOR_LOOP_FROM")
            let to = reader.formula("FOR_LOOP_TO")
            if let variable {
                changed.insert(variable.identity)
            }
            guard let variable, let from, let to else { return loop(nil) }
            return loop(.forVariableFromTo(name: variable.name, from: from, to: to))
        case "IfLogicBeginBrick":
            let opener = reader.formula("IF_CONDITION").map { ImportedStep.brick(.ifElse(condition: $0)) }
            let branches = body("ifBranchBricks") + [.marker(.elseBranch)] + body("elseBranchBricks")
            return (opener, branches + [.marker(.ifEnd)])
        default: // IfThenLogicBeginBrick
            let opener = reader.formula("IF_CONDITION").map { ImportedStep.brick(.ifThen(condition: $0)) }
            return (opener, body("ifBranchBricks") + [.marker(.ifEnd)])
        }
    }

    /// SetVariable and ChangeVariable, recording what the D4 storage rule needs.
    private mutating func dataBrick(_ type: String, at address: Address, reader: inout BrickReader) -> Brick? {
        let variable = variable(of: address, reader: &reader)
        if type == "SetVariableBrick" {
            if let variable, let value = reader.formulaElement("VARIABLE") {
                let storage = FormulaImport.storage(ofVariableValue: value)
                var source: Address?
                if case let .copied(from: name) = storage {
                    source = objectScope[name] ?? projectScope[name]
                }
                stored.append(Stored(identity: variable.identity, storage: storage, source: source))
            }
            let value = reader.formula("VARIABLE", slot: .variableValue)
            guard let variable, let value else { return nil }
            return .setVariable(name: variable.name, to: value)
        }
        let value = reader.formula("VARIABLE_CHANGE")
        if let variable {
            changed.insert(variable.identity)
        }
        guard let variable, let value else { return nil }
        return .changeVariableBy(name: variable.name, value: value)
    }

    // MARK: Helpers

    func children(of address: Address, named name: String) -> [Address] {
        guard let element = tree[address] else { return [] }
        return element.children.indices.filter { element.children[$0].name == name }.map { address.child($0) }
    }

    private func isCommentedOut(_ element: XMLTree.Element) -> Bool {
        // XStream's Boolean converter ignores case (Codex slice 4, finding 3).
        element.child("commentedOut")?.text.lowercased() == "true"
    }
}
