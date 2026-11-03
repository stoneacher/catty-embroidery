#if canImport(CryptoKit)
    import CryptoKit
#endif
import Foundation
import Testing

/// Slice 1 of the language-test runner (brief D11): the 215 extracted `code.xml`
/// fixtures are present, unaltered and exactly the set the manifest names, and
/// the manifest pins the Catroid commit they came from.
struct FixtureProvenanceTests {
    /// Catroid `develop` at extraction time, and the last commit touching the
    /// test assets (brief, "Decisions taken at planning").
    static let pinnedCatroidCommit = "9035dc7cbd0b708e46733e4a66c515a25951c945"
    static let pinnedAssetsCommit = "e993a6a529228f988d77cfba5618212a4741e9e4"

    @Test func manifestPinsTheCatroidCommit() throws {
        let manifest = try LanguageTestCatalog.manifest()
        #expect(manifest.catroidCommit == Self.pinnedCatroidCommit)
        #expect(manifest.assetsLastCommit == Self.pinnedAssetsCommit)
        #expect(manifest.assetsPath == "catroid/src/androidTest/assets/catrobatTests")
    }

    @Test func catalogHasAll215TestsOnce() throws {
        let paths = try LanguageTestCatalog.manifest().tests.map(\.path)
        #expect(paths.count == 215)
        #expect(Set(paths).count == paths.count, "duplicate manifest entries")
        #expect(paths == paths.sorted(), "manifest is sorted, so extraction is deterministic")
    }

    @Test func everyManifestEntryNamesItsArchive() throws {
        for entry in try LanguageTestCatalog.manifest().tests {
            #expect(entry.zip == entry.path + ".catrobat", "\(entry.path)")
            #expect(entry.zipSHA256.count == 64 && entry.zipSHA256.allSatisfy(\.isHexDigit), "\(entry.path)")
        }
    }

    /// The other direction of the bijection: every `code.xml` in the tree has an
    /// entry. A fixture left behind by a removed test would otherwise go unnoticed.
    @Test func everyFixtureOnDiskIsInTheManifest() throws {
        let root = try LanguageTestCatalog.rootURL().standardizedFileURL
        let listed = try Set(LanguageTestCatalog.manifest().tests.map(\.path))
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var onDisk: Set<String> = []
        for case let url as URL in enumerator where url.lastPathComponent == "code.xml" {
            let directory = url.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false)
            let rootPath = root.path(percentEncoded: false)
            onDisk.insert(String(directory.dropFirst(rootPath.count)).trimmingCharacters(in: ["/"]))
        }
        #expect(onDisk.subtracting(listed).isEmpty, "fixtures without an entry: \(onDisk.subtracting(listed).sorted())")
        #expect(listed.subtracting(onDisk).isEmpty, "entries without a fixture: \(listed.subtracting(onDisk).sorted())")
    }

    @Test(arguments: LanguageTestCatalog.entries)
    func fixtureMatchesItsManifestHash(_ entry: LanguageTestManifest.Entry) throws {
        let data = try LanguageTestCatalog.codeXML(for: entry.path)
        #if canImport(CryptoKit)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(digest == entry.codeXMLSHA256)
        #else
            Issue.record("no SHA-256 implementation on this platform; the fixture hash is unchecked")
        #endif
    }

    /// Brief D1: the importer accepts 0.99995 ≤ version ≤ 1.14. Today every test in
    /// the corpus lies inside it (0.99995 … 1.13), so none is unsupported for its
    /// version alone. A re-extraction that brings in an older test turns this red
    /// rather than surfacing later as an unexplained refusal. Slice 4 points this
    /// at the importer's own constants.
    @Test(arguments: LanguageTestCatalog.entries)
    func fixtureVersionIsInsideTheImportWindow(_ entry: LanguageTestManifest.Entry) throws {
        let version = try #require(Double(entry.languageVersion), "\(entry.languageVersion) is not a number")
        #expect((0.99995 ... 1.14).contains(version))
    }

    @Test(arguments: LanguageTestCatalog.entries)
    func manifestVersionIsTheFixturesOwn(_ entry: LanguageTestManifest.Entry) throws {
        let xml = try #require(String(data: LanguageTestCatalog.codeXML(for: entry.path), encoding: .utf8))
        let open = "<catrobatLanguageVersion>"
        let start = try #require(xml.range(of: open)).upperBound
        let end = try #require(xml.range(of: "</catrobatLanguageVersion>", range: start ..< xml.endIndex)).lowerBound
        #expect(String(xml[start ..< end]) == entry.languageVersion)
    }
}
