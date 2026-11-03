import CatrobatImport
import Foundation
import Testing

/// Slice 2 of the language-test runner (brief D7): a `code.xml` becomes a small
/// value tree, and XStream's relative `reference=` paths resolve inside it.
struct XMLTreeTests {
    private func tree(_ xml: String) throws -> XMLTree {
        try XMLTree(parsing: Data(xml.utf8))
    }

    // MARK: - Parsing

    @Test func parsesElementsAttributesAndTextInDocumentOrder() throws {
        let tree = try tree("""
        <program version="1"><header><name>Demo</name></header><scenes><scene/><scene/></scenes></program>
        """)
        #expect(tree.root.name == "program")
        #expect(tree.root.attributes == ["version": "1"])
        #expect(tree.root.children.map(\.name) == ["header", "scenes"])
        #expect(tree.root.children[0].children[0].text == "Demo")
        #expect(tree.root.children[1].children.map(\.name) == ["scene", "scene"])
    }

    @Test func decodesEntitiesAndCDATA() throws {
        let tree = try tree("<a><b>1 &lt; 2 &amp; 3</b><c><![CDATA[x <y> z]]></c></a>")
        #expect(tree.root.children[0].text == "1 < 2 & 3")
        #expect(tree.root.children[1].text == "x <y> z")
    }

    /// Whitespace between child elements is kept raw; trimming is the importer's
    /// decision, per field, so the tree stays a faithful reading of the file.
    @Test func keepsTextRawAndOffersATrimmedView() throws {
        let tree = try tree("<a>\n  <b>  7 </b>\n</a>")
        #expect(tree.root.children[0].text == "  7 ")
        #expect(tree.root.children[0].trimmedText == "7")
        #expect(tree.root.text == "\n  \n")
    }

    /// Text on either side of a child element is concatenated. The importer only
    /// reads leaf text, but no later slice may come to rely on this by accident.
    @Test func mixedContentConcatenatesTheParentsText() throws {
        let tree = try tree("<a>x<b>inner</b>y</a>")
        #expect(tree.root.text == "xy")
        #expect(tree.root.children[0].text == "inner")
    }

    /// Catroid writes `<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>`;
    /// a byte-order mark in front of it must not make the file malformed.
    @Test func acceptsTheDeclarationCatroidWritesWithAndWithoutABOM() throws {
        let declaration = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>\n<program/>"
        #expect(try tree(declaration).root.name == "program")
        let withBOM = Data([0xEF, 0xBB, 0xBF]) + Data(declaration.utf8)
        #expect(try XMLTree(parsing: withBOM).root.name == "program")
    }

    /// XStream's `XmlFriendlyNameCoder` writes `_` as `__`, `$` as `_-` and other
    /// characters as `_.` plus four hex digits. Names are stored decoded, as
    /// XStream compares them.
    @Test func elementNamesAreDecodedFromXStreamsNameCoding() throws {
        let tree = try tree("<a><foo__bar/><foo_-bar/><x_.0041y/></a>")
        #expect(tree.root.children.map(\.name) == ["foo_bar", "foo$bar", "xAy"])
    }

    @Test(arguments: [
        "",
        "not xml",
        "<a><b></a>",
        "<a>",
        "<a></a><b></b>",
        "<a attr=\"unterminated></a>"
    ])
    func malformedInputThrowsInsteadOfTrapping(_ xml: String) {
        #expect(throws: ImportBlocker.malformed) {
            try XMLTree(parsing: Data(xml.utf8))
        }
    }

    @Test func addressesFindElementsInDocumentOrder() throws {
        let tree = try tree("<a><x id=\"1\"/><b><x id=\"2\"/></b><x id=\"3\"/></a>")
        let found = tree.addresses { $0.name == "x" }
        #expect(found.compactMap { tree[$0]?.attributes["id"] } == ["1", "2", "3"])
        #expect(tree[XMLTree.Address(path: [])]?.name == "a")
        #expect(tree[XMLTree.Address(path: [7])] == nil)
    }

    // MARK: - References

    // swiftlint:disable line_length
    // The cross-object reference path is one XML attribute and cannot be wrapped.
    /// A script with a fully qualified brick tag between ordinary `<brick>`s, the
    /// shape `brick/testDisabledBrickInLoopRegression` has. XStream's `brick[n]`
    /// counts only same-named siblings, 1-based, and the path is relative to the
    /// element carrying the `reference` attribute.
    private let script = """
    <program><scenes><scene><objectList>
      <object name="A"><scriptList><script><brickList>
        <brick type="SetVariableBrick"><userVariable type="UserVariable"><name>first</name></userVariable></brick>
        <org.catrobat.catroid.content.bricks.AssertEqualsBrick type="AssertEqualsBrick"/>
        <brick type="SetVariableBrick"><userVariable type="UserVariable"><name>second</name></userVariable></brick>
        <brick type="ChangeVariableBrick"><userVariable reference="../../brick[2]/userVariable"/></brick>
        <brick type="ChangeVariableBrick"><userVariable reference="../../brick/userVariable"/></brick>
        <brick type="ChangeVariableBrick"><userVariable reference="../../brick[1]/userVariable"/></brick>
      </brickList></script></scriptList></object>
      <object name="B"><scriptList><script><brickList>
        <brick type="ChangeVariableBrick"><userVariable reference="../../../../../../object/scriptList/script/brickList/brick[2]/userVariable"/></brick>
        <brick><userVariable reference="../../../../../../../../../../userVariable"/></brick>
        <brick><userVariable reference="../../brick[9]/userVariable"/></brick>
        <brick><userVariable reference="../../brick[4]/userVariable"/></brick>
        <brick><userVariable reference="../../brick[0]/userVariable"/></brick>
      </brickList></script></scriptList></object>
    </objectList></scene></scenes></program>
    """
    // swiftlint:enable line_length

    private func referencingVariables(in tree: XMLTree) -> [XMLTree.Address] {
        tree.addresses { $0.name == "userVariable" && $0.attributes["reference"] != nil }
    }

    private func name(of address: XMLTree.Address, in tree: XMLTree) -> String? {
        tree[address]?.children.first { $0.name == "name" }?.text
    }

    @Test func sameTagIndexIsOneBasedAndSkipsOtherTags() throws {
        let tree = try tree(script)
        let reference = referencingVariables(in: tree)[0]
        let target = try tree.dereference(reference)
        #expect(name(of: target, in: tree) == "second")
    }

    @Test func aSegmentWithoutAnIndexIsTheFirstOfItsName() throws {
        let tree = try tree(script)
        let target = try tree.dereference(referencingVariables(in: tree)[1])
        #expect(name(of: target, in: tree) == "first")
    }

    /// `brick[1]` is `brick`. Kills 0-based indexing and all-sibling counting
    /// together, which `brick[2]` alone does not: under both, `children[2]` is
    /// the "second" brick again.
    @Test func anExplicitFirstIndexIsTheUnindexedSegment() throws {
        let tree = try tree(script)
        let target = try tree.dereference(referencingVariables(in: tree)[2])
        #expect(name(of: target, in: tree) == "first")
    }

    @Test func parentChainsCrossObjects() throws {
        let tree = try tree(script)
        let target = try tree.dereference(referencingVariables(in: tree)[3])
        #expect(name(of: target, in: tree) == "second")
    }

    @Test func anElementWithoutAReferenceIsItsOwnTarget() throws {
        let tree = try tree(script)
        let plain = try #require(tree.addresses { $0.name == "userVariable" }.first)
        #expect(try tree.dereference(plain) == plain)
    }

    @Test(arguments: [
        (4, "../../../../../../../../../../userVariable"), // climbs above the root
        (5, "../../brick[9]/userVariable"), // index past the last sibling
        (6, "../../brick[4]/userVariable"), // the target is itself a reference
        (7, "../../brick[0]/userVariable") // XStream indices are 1-based
    ])
    func anUnresolvablePathThrowsNamingIt(index: Int, path: String) throws {
        let tree = try tree(script)
        let reference = referencingVariables(in: tree)[index]
        #expect(throws: ImportBlocker.unresolvedReference(path)) {
            try tree.dereference(reference)
        }
    }

    /// `<brick/>` precedes the reference, so each would resolve to it if the
    /// segment grammar were lenient (before it did not, and the forward-reference
    /// rule masked a lenient grammar; caught by mutation).
    /// XStream writes a plain positive decimal, and only `[1]` is normalised away.
    /// `Int.min` must not trap on `ordinal - 1`.
    @Test(arguments: [
        "", "brick[x]", "brick[1", "../../brick[-1]", "a//b", "../../brick[0]",
        "../../brick[01]", "../../brick[+1]", "../../brick[ 1]", "../../brick[-9223372036854775808]"
    ])
    func aSyntacticallyBrokenPathIsUnresolved(_ path: String) throws {
        let tree = try tree("<a><brick/><b><c reference=\"\(path)\"/></b></a>")
        let reference = try #require(tree.addresses { $0.name == "c" }.first)
        #expect(throws: ImportBlocker.unresolvedReference(path)) {
            try tree.dereference(reference)
        }
    }

    /// XStream's `Path` skips `.` segments.
    @Test func aDotSegmentIsSkipped() throws {
        let tree = try tree("<root><item id=\"t\"/><ref reference=\".././item\"/></root>")
        let reference = try #require(tree.addresses { $0.name == "ref" }.first)
        #expect(try tree[tree.dereference(reference)]?.attributes["id"] == "t")
    }

    /// The reference string is decoded with the same name coder before its
    /// segments are matched (XStream's `ReferenceByXPathUnmarshaller`).
    @Test(arguments: [("../foo_bar", "underscore"), ("../foo$bar", "dollar"), ("../foo__bar", "underscore")])
    func aReferenceMatchesDecodedNames(path: String, id: String) throws {
        let tree = try tree("""
        <root><foo__bar id="underscore"/><foo_-bar id="dollar"/><ref reference="\(path)"/></root>
        """)
        let reference = try #require(tree.addresses { $0.name == "ref" }.first)
        #expect(try tree[tree.dereference(reference)]?.attributes["id"] == id)
    }

    /// XStream resolves a reference against the objects unmarshalled so far: an
    /// element completed earlier in document order, or an ancestor still being
    /// built. A target that starts after the reference is invalid.
    @Test func aForwardReferenceIsUnresolved() throws {
        let tree = try tree("<root><item reference=\"../item[2]\"/><item id=\"later\"/></root>")
        let reference = try #require(tree.addresses { $0.name == "item" }.first)
        #expect(throws: ImportBlocker.unresolvedReference("../item[2]")) {
            try tree.dereference(reference)
        }
    }

    @Test func aReferenceToAnAncestorResolves() throws {
        let tree = try tree("<root><object id=\"self\"><objectToClone reference=\"..\"/></object></root>")
        let reference = try #require(tree.addresses { $0.name == "objectToClone" }.first)
        #expect(try tree[tree.dereference(reference)]?.attributes["id"] == "self")
    }

    @Test func anAddressOutsideTheTreeIsUnresolved() throws {
        let tree = try tree("<a/>")
        #expect(throws: ImportBlocker.unresolvedReference("")) {
            try tree.dereference(XMLTree.Address(path: [3]))
        }
    }
}
