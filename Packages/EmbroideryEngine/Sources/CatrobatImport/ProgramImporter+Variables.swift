import ProgramModel

/// Variables by identity (brief D7) and the SetVariable storage rule (D4).
extension ProgramImporter {
    /// The brick's `userVariable`, which may be a reference. It must be a variable
    /// declared where the brick's object can see it: its own list or the project's.
    /// Otherwise Catroid writes a `UserVariable` no name lookup reaches.
    mutating func variable(of brick: Address, reader: inout BrickReader) -> Declared? {
        let before = blockers.count
        guard let reference = children(of: brick, named: "userVariable").first,
              let variable = declared(at: reference)
        else {
            // A missing variable is the brick's shape; an unresolved one has
            // already been reported as itself.
            if blockers.count == before { reader.refuse() }
            return nil
        }
        guard objectScope[variable.name] == variable.identity || projectScope[variable.name] == variable.identity else {
            blockers.append(.undeclaredVariable(variable.name))
            return nil
        }
        return variable
    }

    // MARK: Variables

    struct Declared {
        var name: String
        var identity: Address
    }

    /// A declaration list: each entry an inline variable or a reference to one,
    /// resolved over the whole tree, commented-out bricks included (D7).
    mutating func declarations(in list: Address?) -> [Declared] {
        guard let list, let element = tree[list] else { return [] }
        return element.children.indices.compactMap { index in
            guard let variable = declared(at: list.child(index)) else {
                blockers.append(.element("userVariable"))
                return nil
            }
            return variable
        }
    }

    /// One list's names, refusing a name two of its variables share: a name read
    /// would only ever reach the first (`UserDataWrapper.java:40`).
    mutating func scope(of variables: [Declared]) -> [String: Address] {
        var scope: [String: Address] = [:]
        var repeated: Set<String> = []
        for variable in variables {
            if let existing = scope[variable.name], existing != variable.identity {
                repeated.insert(variable.name)
            } else {
                scope[variable.name] = variable.identity
            }
        }
        for name in repeated.sorted() {
            blockers.append(.variableShadowing(name))
        }
        return scope
    }

    /// XStream's custom form (`userVariable/userVariable/default/name`), its inner
    /// form (`userVariable/default/name`) or the text form (`<userVariable>x</userVariable>`).
    mutating func declared(at address: Address) -> Declared? {
        let target: Address
        do {
            target = try tree.dereference(address)
        } catch {
            blockers.append(error)
            return nil
        }
        guard let element = tree[target] else { return nil }
        let name: String?
        if element.children.isEmpty {
            name = element.text
        } else {
            name = (element.child("userVariable") ?? element).child("default")?.child("name")?.text
        }
        guard let name else { return nil }
        names[target] = name
        return Declared(name: name, identity: target)
    }

    /// Brief D4: a variable some SetVariable stores as a Boolean or a string (a
    /// copy carries Boolean, not string) and that a ChangeVariable or
    /// ForVariableFromTo touches is refused, since both test for a `Double`.
    mutating func checkStorage() {
        var boolean = Set(stored.filter { $0.storage == .boolean }.map(\.identity))
        var grew = true
        while grew {
            let before = boolean.count
            for entry in stored {
                if let source = entry.source, boolean.contains(source) {
                    boolean.insert(entry.identity)
                }
            }
            grew = boolean.count > before
        }
        let string = Set(stored.filter { $0.storage == .string }.map(\.identity))
        let refused = boolean.union(string).intersection(changed).compactMap { names[$0] }
        for name in Set(refused).sorted() {
            blockers.append(.variableStorage(name))
        }
    }
}
