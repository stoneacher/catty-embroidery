import Foundation
#if canImport(FoundationXML)
    import FoundationXML
#endif

/// A `code.xml` read into a small immutable value tree (language-test runner
/// brief, D10), so the importer can resolve XStream references by position
/// before it decides what to keep.
///
/// `package` for the tests; the import's consumer API is `ProgramImport.program(fromCodeXML:)`,
/// the `Imported*` types, `ImportBlocker` and `CatrobatImportError`.
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

    /// The deepest element nesting the parser admits; deeper documents are
    /// `malformed`. The tree is freed recursively (`Element` holds `[Element]`), and
    /// at ~4000 levels that overflowed a 512 KB cooperative-pool stack. Catroid's
    /// files nest at most 28 deep in the corpus.
    package static let maximumDepth = 512

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
    /// Mirrors XStream's `XPATH_RELATIVE_REFERENCES` (`Path`,
    /// `ReferenceByXPathUnmarshaller`, `AbstractReferenceUnmarshaller`):
    /// - the path is decoded with the name coder and evaluated from the
    ///   referencing element itself: `..` is its parent, `.` is skipped;
    /// - `name[n]` is the n-th child called `name`, counting only children of
    ///   that name, written as a plain positive decimal; `name` alone is `name[1]`;
    /// - the target must already be unmarshalled when the reference is read: an
    ///   element completed earlier in document order, or an ancestor.
    ///
    /// Anything else throws `unresolvedReference` naming the path: a path leading
    /// outside the tree, forward, or to an element that is itself a reference. An
    /// address outside the tree throws it with an empty path.
    package func dereference(_ address: Address) throws(ImportBlocker) -> Address {
        guard let source = self[address] else { throw .unresolvedReference("") }
        guard let path = source.attributes["reference"] else { return address }
        let unresolved = ImportBlocker.unresolvedReference(path)
        guard !path.isEmpty else { throw unresolved }

        var current = address
        for segment in XStreamName.decode(path).split(separator: "/", omittingEmptySubsequences: false) {
            switch segment {
            case "..":
                guard let parent = current.parent else { throw unresolved }
                current = parent
            case ".":
                continue
            default:
                guard let (name, ordinal) = Self.parse(segment: segment),
                      let element = self[current]
                else { throw unresolved }
                let matches = element.children.indices.filter { element.children[$0].name == name }
                guard ordinal <= matches.count else { throw unresolved }
                current = current.child(matches[ordinal - 1])
            }
        }
        guard let target = self[current], target.attributes["reference"] == nil,
              current.isAncestor(of: address) || current.precedes(address)
        else { throw unresolved }
        return current
    }

    /// `name` or `name[n]` with n a positive decimal without sign or leading zero,
    /// as XStream writes it; anything else is not a path segment. Digits only and
    /// no leading zero make n ≥ 1, so the caller's `n - 1` cannot overflow (an
    /// unguarded `Int(_:)` accepted `-9223372036854775808` and trapped there); a
    /// value past `Int.max` makes `Int(_:)` return nil.
    private static func parse(segment: Substring) -> (name: Substring, ordinal: Int)? {
        guard let open = segment.firstIndex(of: "[") else {
            return segment.isEmpty ? nil : (segment, 1)
        }
        let name = segment[..<open]
        guard !name.isEmpty, segment.last == "]" else { return nil }
        let digits = segment[segment.index(after: open) ..< segment.index(before: segment.endIndex)]
        guard digits.first != "0",
              digits.allSatisfy({ ("0" ... "9").contains($0) }),
              let ordinal = Int(digits)
        else { return nil }
        return (name, ordinal)
    }
}

extension XMLTree.Address {
    func isAncestor(of other: Self) -> Bool {
        path.count < other.path.count && other.path.starts(with: path)
    }

    /// Strictly earlier in document order and not an ancestor: the element was
    /// completed before `other` started.
    func precedes(_ other: Self) -> Bool {
        !isAncestor(of: other) && path.lexicographicallyPrecedes(other.path)
    }
}

/// XStream's `XmlFriendlyNameCoder`, decoding direction: `__` is `_`, `_-` is `$`,
/// and `_.` followed by four hex digits is that UTF-16 code unit. Any other `_`
/// stands for itself.
enum XStreamName {
    static func decode(_ name: String) -> String {
        guard name.contains("_") else { return name }
        var result = ""
        var rest = Substring(name)
        while let first = rest.first {
            if rest.hasPrefix("__") {
                result.append("_")
                rest = rest.dropFirst(2)
            } else if rest.hasPrefix("_-") {
                result.append("$")
                rest = rest.dropFirst(2)
            } else if let scalar = hexEscape(rest) {
                result.unicodeScalars.append(scalar)
                rest = rest.dropFirst(6)
            } else {
                result.append(first)
                rest = rest.dropFirst()
            }
        }
        return result
    }

    /// `_.` and four hex digits at the start of `text`, as the scalar they name.
    private static func hexEscape(_ text: Substring) -> Unicode.Scalar? {
        guard text.hasPrefix("_.") else { return nil }
        let digits = text.dropFirst(2).prefix(4)
        guard digits.count == 4, digits.allSatisfy(\.isHexDigit), let unit = UInt16(digits, radix: 16) else {
            return nil
        }
        return Unicode.Scalar(unit)
    }
}

/// The SAX delegate. Used on one thread for one parse and then discarded.
private final class TreeBuilder: NSObject, XMLParserDelegate {
    private var stack: [XMLTree.Element] = []
    private(set) var root: XMLTree.Element?
    private(set) var failed = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes: [String: String]
    ) {
        guard stack.count < XMLTree.maximumDepth else {
            failed = true
            parser.abortParsing()
            return
        }
        stack.append(XMLTree.Element(
            name: XStreamName.decode(elementName), attributes: attributes, children: [], text: ""
        ))
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
