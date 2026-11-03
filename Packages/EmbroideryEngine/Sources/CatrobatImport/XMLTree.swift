import Foundation
#if canImport(FoundationXML)
    import FoundationXML
#endif

/// A `code.xml` read into a small immutable value tree (language-test runner
/// brief, D10), so the importer can resolve XStream references by position
/// before it decides what to keep.
///
/// Foundation's `XMLDocument` is macOS-only, so the tree is built from an
/// `XMLParser` SAX pass. Text is kept exactly as parsed, entities and CDATA
/// decoded; trimming is a per-field decision left to the importer.
package struct XMLTree: Sendable, Equatable {
    package struct Element: Sendable, Equatable {
        package var name: String
        package var attributes: [String: String]
        package var children: [Element]
        package var text: String

        package var trimmedText: String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// An element's position as child indices from the root; `[]` is the root.
    package struct Address: Hashable, Sendable {
        package var path: [Int]

        package init(path: [Int]) {
            self.path = path
        }

        var parent: Address? {
            path.isEmpty ? nil : Address(path: Array(path.dropLast()))
        }

        func child(_ index: Int) -> Address {
            Address(path: path + [index])
        }
    }

    package let root: Element

    package init(parsing data: Data) throws(ImportBlocker) {
        let builder = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse(), !builder.failed, let root = builder.root else {
            throw .malformed
        }
        self.root = root
    }

    package subscript(address: Address) -> Element? {
        var element = root
        for index in address.path {
            guard element.children.indices.contains(index) else { return nil }
            element = element.children[index]
        }
        return element
    }

    /// Every element the predicate accepts, in document order.
    package func addresses(where predicate: (Element) -> Bool) -> [Address] {
        var found: [Address] = []
        func visit(_ element: Element, at address: Address) {
            if predicate(element) {
                found.append(address)
            }
            for (index, child) in element.children.enumerated() {
                visit(child, at: address.child(index))
            }
        }
        visit(root, at: Address(path: []))
        return found
    }

    /// The element a `reference=` attribute points at, or the address itself when
    /// the element carries none.
    ///
    /// XStream's relative paths are evaluated from the referencing element itself:
    /// `..` is its parent, and `name[n]` is the n-th child called `name`, 1-based,
    /// counting only children of that name (`name` alone is `name[1]`). A path
    /// leading outside the tree, or to an element that is itself a reference,
    /// throws `unresolvedReference` naming the path.
    package func dereference(_ address: Address) throws(ImportBlocker) -> Address {
        guard let path = self[address]?.attributes["reference"] else { return address }
        let unresolved = ImportBlocker.unresolvedReference(path)
        guard !path.isEmpty else { throw unresolved }

        var current = address
        for segment in path.split(separator: "/", omittingEmptySubsequences: false) {
            if segment == ".." {
                guard let parent = current.parent else { throw unresolved }
                current = parent
                continue
            }
            guard let (name, ordinal) = Self.parse(segment: segment),
                  let element = self[current]
            else { throw unresolved }
            let matches = element.children.indices.filter { element.children[$0].name == name }
            guard matches.indices.contains(ordinal - 1) else { throw unresolved }
            current = current.child(matches[ordinal - 1])
        }
        guard let target = self[current], target.attributes["reference"] == nil else { throw unresolved }
        return current
    }

    /// `name` or `name[n]`; anything else is not a path segment. An ordinal below 1
    /// parses, and is rejected by the caller's range check like one past the end.
    private static func parse(segment: Substring) -> (name: Substring, ordinal: Int)? {
        guard let open = segment.firstIndex(of: "[") else {
            return segment.isEmpty ? nil : (segment, 1)
        }
        let name = segment[..<open]
        guard !name.isEmpty, segment.last == "]",
              let ordinal = Int(segment[segment.index(after: open) ..< segment.index(before: segment.endIndex)])
        else { return nil }
        return (name, ordinal)
    }
}

/// The SAX delegate. Used on one thread for one parse and then discarded.
private final class TreeBuilder: NSObject, XMLParserDelegate {
    private var stack: [XMLTree.Element] = []
    private(set) var root: XMLTree.Element?
    private(set) var failed = false

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes: [String: String]
    ) {
        stack.append(XMLTree.Element(name: elementName, attributes: attributes, children: [], text: ""))
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard !stack.isEmpty, let string = String(data: CDATABlock, encoding: .utf8) else {
            failed = true
            parser.abortParsing()
            return
        }
        stack[stack.count - 1].text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement _: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        guard let element = stack.popLast() else {
            failed = true
            parser.abortParsing()
            return
        }
        if stack.isEmpty {
            root = element
        } else {
            stack[stack.count - 1].children.append(element)
        }
    }

    func parser(_: XMLParser, parseErrorOccurred _: any Error) {
        failed = true
    }
}
