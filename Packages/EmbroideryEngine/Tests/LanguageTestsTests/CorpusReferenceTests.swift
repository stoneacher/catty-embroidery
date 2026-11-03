import CatrobatImport
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

    /// Pins every reference's source and target tag across the corpus (1120 in all).
    /// It guards the parameterised test above against an empty corpus, and is the
    /// resolver's identity oracle: one that lands on a sibling of the wrong kind
    /// changes this table. The cross-kind pairs all belong to user-defined bricks
    /// and clones, which are out of scope (ADR-001).
    @Test func referenceKindsAcrossTheCorpus() throws {
        var pairs: [String: Int] = [:]
        for entry in try LanguageTestCatalog.manifest().tests {
            let tree = try XMLTree(parsing: LanguageTestCatalog.codeXML(for: entry.path))
            for address in tree.addresses(where: { $0.attributes["reference"] != nil }) {
                let source = try #require(tree[address]).name
                let target = try #require(tree[tree.dereference(address)]).name
                pairs["\(source) → \(target)", default: 0] += 1
            }
        }
        #expect(pairs == [
            "input → input": 20,
            "look → look": 7,
            "object → objectToClone": 4,
            "objectToClone → objectToClone": 2,
            "userData → userData": 6,
            "userData → userList": 10,
            "userDefinedBrickDataList → userDefinedBrickDataList": 14,
            "userList → userData": 5,
            "userList → userList": 336,
            "userVariable → userData": 6,
            "userVariable → userVariable": 710
        ])
        #expect(pairs.values.reduce(0, +) == 1120)
    }
}
