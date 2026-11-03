@testable import CatrobatImport
import Foundation
import Testing

/// Slice 2 over the real corpus: every one of the 215 `code.xml` files parses, and
/// every `reference=` in it resolves to an element that is not itself a reference.
/// A `userVariable` reference lands on a `userVariable`: the declaration lists
/// (brief D7) depend on that.
struct CorpusReferenceTests {
    @Test(arguments: LanguageTestCatalog.entries)
    func everyReferenceResolves(_ entry: LanguageTestManifest.Entry) throws {
        let tree = try XMLTree(parsing: LanguageTestCatalog.codeXML(for: entry.path))
        let references = tree.addresses { $0.attributes["reference"] != nil }
        for address in references {
            let source = try #require(tree[address])
            let target = try tree.dereference(address)
            let element = try #require(tree[target])
            #expect(element.attributes["reference"] == nil)
            if source.name == "userVariable" {
                // A declaration may also point at a `userData`: the loop variable of
                // a ForEach over a user-defined brick's input (`testForEachBrick`,
                // `testSetTransparency`, …), all out of scope (ADR-001).
                #expect(["userVariable", "userData"].contains(element.name), "\(source.attributes["reference"] ?? "")")
            }
        }
    }

    /// Guards the parameterised test above against running over an empty corpus,
    /// and pins how many references it actually exercised.
    @Test func theCorpusHas1120References() throws {
        var count = 0
        for entry in try LanguageTestCatalog.manifest().tests {
            let tree = try XMLTree(parsing: LanguageTestCatalog.codeXML(for: entry.path))
            count += tree.addresses { $0.attributes["reference"] != nil }.count
        }
        #expect(count == 1120)
    }
}
