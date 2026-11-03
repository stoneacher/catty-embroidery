import Foundation
import ProgramModel

/// One step of an imported script: a `Brick`, or one of the language tests'
/// harness bricks, which never become `Brick` cases (brief D3), so they cannot
/// reach `BrickKind`, the palette or `ProgramDocument`.
package enum ImportedStep: Sendable, Equatable {
    case brick(Brick)
    /// Catroid `AssertEqualsBrick`; both operands read as assert operands (D4).
    case assertEquals(actual: Formula, expected: Formula)
    /// Catroid `FinishStageBrick`: the test passed.
    case finishStage
    /// Catroid `ExitStageBrick`: the stage ends without a result (D5).
    case exitStage
    /// Catroid `WaitTillIdleBrick` (D8).
    case waitTillIdle
}

/// A StartScript's steps. Every imported script starts when the program does.
package struct ImportedScript: Sendable, Equatable {
    package var steps: [ImportedStep]
}

package struct ImportedObject: Sendable, Equatable {
    package var name: String
    package var variables: [Variable]
    package var scripts: [ImportedScript]
}

/// A `code.xml`'s first and only scene, mirroring `Program` with harness steps.
package struct ImportedProgram: Sendable, Equatable {
    package var name: String
    package var sceneName: String
    package var variables: [Variable]
    package var objects: [ImportedObject]

    /// The program without harness steps, for an app import; one with any is
    /// refused. Every object starts at (0, 0) facing 90, where Catroid starts a
    /// look (`content/Look.java:88`), in list order.
    package func program() throws(CatrobatImportError) -> Program {
        var harness = false
        let objects = objects.enumerated().map { index, object in
            Object(
                name: object.name, startX: 0, startY: 0, startHeading: 90, zIndex: index,
                variables: object.variables,
                scripts: object.scripts.map { script in
                    Script(header: .whenStarted, bricks: script.steps.compactMap { step in
                        guard case let .brick(brick) = step else {
                            harness = true
                            return nil
                        }
                        return brick
                    })
                }
            )
        }
        guard !harness else { throw CatrobatImportError(blockers: [.harnessStep]) }
        return Program(name: name, scenes: [Scene(name: sceneName, objects: objects)], variables: variables)
    }
}

/// Every reason a `code.xml` could not be imported (brief D7: all of them, not
/// the first).
package struct CatrobatImportError: Error, Equatable {
    package var blockers: Set<ImportBlocker>

    package init(blockers: Set<ImportBlocker>) {
        self.blockers = blockers
    }
}

/// Catroid `code.xml` to `ImportedProgram` (language-test runner brief, slice 4).
package enum CatrobatImport {
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
    /// For the D4 storage rule: what each SetVariable stores, and which variables
    /// a ChangeVariable or ForVariableFromTo touches.
    var stored: [(name: String, storage: VariableStorage)] = []
    var changed: Set<String> = []

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

        let variables = declarations(in: children(of: root, named: "programVariableList").first)
        let projectNames = Set(variables.map(\.name))
        let objects = children(of: scene, named: "objectList")
            .flatMap { children(of: $0, named: "object") }
            .map { importObject(at: $0, projectNames: projectNames) }
        checkStorage()
        return ImportedProgram(
            name: tree.root.child("header")?.child("programName")?.text ?? "",
            sceneName: tree[scene]?.child("name")?.text ?? "",
            variables: variables,
            objects: objects
        )
    }

    private mutating func checkVersion() {
        let text = tree.root.child("header")?.child("catrobatLanguageVersion")?.text ?? ""
        guard let version = Double(text), CatrobatImport.supportedVersions.contains(version) else {
            blockers.append(.version(text))
            return
        }
    }

    private mutating func importObject(at address: Address, projectNames: Set<String>) -> ImportedObject {
        let variables = declarations(in: children(of: address, named: "userVariables").first)
        for variable in variables where projectNames.contains(variable.name) {
            blockers.append(.variableShadowing(variable.name))
        }
        let scripts = children(of: address, named: "scriptList")
            .flatMap { children(of: $0, named: "script") }
            .compactMap { importScript(at: $0) }
        return ImportedObject(name: tree[address]?.attributes["name"] ?? "", variables: variables, scripts: scripts)
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
        defer { blockers += reader.blockers }
        switch type {
        case "NoteBrick":
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
            let name = variableName(of: address, reader: &reader)
            let from = reader.formula("FOR_LOOP_FROM")
            let to = reader.formula("FOR_LOOP_TO")
            if let name {
                changed.insert(name)
            }
            guard let name, let from, let to else { return loop(nil) }
            return loop(.forVariableFromTo(name: name, from: from, to: to))
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
        let name = variableName(of: address, reader: &reader)
        if type == "SetVariableBrick" {
            if let name, let value = reader.formulaElement("VARIABLE") {
                stored.append((name, FormulaImport.storage(ofVariableValue: value)))
            }
            let value = reader.formula("VARIABLE", slot: .variableValue)
            guard let name, let value else { return nil }
            return .setVariable(name: name, to: value)
        }
        let value = reader.formula("VARIABLE_CHANGE")
        if let name {
            changed.insert(name)
        }
        guard let name, let value else { return nil }
        return .changeVariableBy(name: name, value: value)
    }

    /// The name of the brick's `userVariable`, which may be a reference.
    private mutating func variableName(of brick: Address, reader: inout BrickReader) -> String? {
        guard let variable = children(of: brick, named: "userVariable").first,
              let name = variableName(at: variable)
        else {
            reader.refuse()
            return nil
        }
        return name
    }

    // MARK: Variables

    /// A declaration list: each entry an inline variable or a reference to one,
    /// resolved over the whole tree, commented-out bricks included (D7).
    private mutating func declarations(in list: Address?) -> [Variable] {
        guard let list, let element = tree[list] else { return [] }
        return element.children.indices.compactMap { index in
            guard let name = variableName(at: list.child(index)) else {
                blockers.append(.element("userVariable"))
                return nil
            }
            return Variable(name: name)
        }
    }

    /// XStream's custom form (`userVariable/userVariable/default/name`), its inner
    /// form (`userVariable/default/name`) or the text form (`<userVariable>x</userVariable>`).
    private mutating func variableName(at address: Address) -> String? {
        let target: Address
        do {
            target = try tree.dereference(address)
        } catch {
            blockers.append(error)
            return nil
        }
        guard let element = tree[target] else { return nil }
        if element.children.isEmpty {
            return element.text
        }
        let inner = element.child("userVariable") ?? element
        return inner.child("default")?.child("name")?.text
    }

    /// Brief D4: a variable some SetVariable stores as a Boolean or a string (a
    /// copy carries Boolean, not string) and that a ChangeVariable or
    /// ForVariableFromTo touches is refused, since both test for a `Double`.
    private mutating func checkStorage() {
        var boolean = Set(stored.filter { $0.storage == .boolean }.map(\.name))
        var grew = true
        while grew {
            let before = boolean.count
            for (name, storage) in stored {
                if case let .copied(from: source) = storage, boolean.contains(source) {
                    boolean.insert(name)
                }
            }
            grew = boolean.count > before
        }
        let string = Set(stored.filter { $0.storage == .string }.map(\.name))
        for name in boolean.union(string).intersection(changed).sorted() {
            blockers.append(.variableStorage(name))
        }
    }

    // MARK: Helpers

    private func children(of address: Address, named name: String) -> [Address] {
        guard let element = tree[address] else { return [] }
        return element.children.indices.filter { element.children[$0].name == name }.map { address.child($0) }
    }

    private func isCommentedOut(_ element: XMLTree.Element) -> Bool {
        element.child("commentedOut")?.text == "true"
    }
}
