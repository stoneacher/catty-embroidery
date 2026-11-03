@testable import CatrobatImport
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

    @Test func parentChainsCrossObjects() throws {
        let tree = try tree(script)
        let target = try tree.dereference(referencingVariables(in: tree)[2])
        #expect(name(of: target, in: tree) == "second")
    }

    @Test func anElementWithoutAReferenceIsItsOwnTarget() throws {
        let tree = try tree(script)
        let plain = try #require(tree.addresses { $0.name == "userVariable" }.first)
        #expect(try tree.dereference(plain) == plain)
    }

    @Test(arguments: [
        (3, "../../../../../../../../../../userVariable"), // climbs above the root
        (4, "../../brick[9]/userVariable"), // index past the last sibling
        (5, "../../brick[4]/userVariable"), // the target is itself a reference
        (6, "../../brick[0]/userVariable") // XStream indices are 1-based
    ])
    func anUnresolvablePathThrowsNamingIt(index: Int, path: String) throws {
        let tree = try tree(script)
        let reference = referencingVariables(in: tree)[index]
        #expect(throws: ImportBlocker.unresolvedReference(path)) {
            try tree.dereference(reference)
        }
    }

    @Test(arguments: ["", "brick[x]", "brick[1", "../brick[-1]", "a//b"])
    func aSyntacticallyBrokenPathIsUnresolved(_ path: String) throws {
        let tree = try tree("<a><b><c reference=\"\(path)\"/></b><brick/></a>")
        let reference = try #require(tree.addresses { $0.name == "c" }.first)
        #expect(throws: ImportBlocker.unresolvedReference(path)) {
            try tree.dereference(reference)
        }
    }
}
