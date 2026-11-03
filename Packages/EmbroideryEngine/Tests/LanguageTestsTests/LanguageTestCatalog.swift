import Foundation
import Testing

/// The Catrobat Language Tests, as extracted from Catroid by
/// `scripts/extract-language-tests.sh` (language-test-runner brief, D11).
///
/// `manifest.json` is the single source of truth for which tests exist. Each
/// entry names a `code.xml` under `Resources/catrobatTests/<path>/`; the
/// provenance tests check that the two agree in both directions.
struct LanguageTestManifest: Decodable, Sendable {
    struct Entry: Decodable, Sendable, CustomTestStringConvertible {
        /// The test's path relative to Catroid's `catrobatTests/` directory,
        /// without the `.catrobat` extension, e.g. `bricks/control/testIfElse`.
        let path: String
        /// The original archive, relative to `catrobatTests/`.
        let zip: String
        let zipSHA256: String
        let codeXMLSHA256: String
        /// `<catrobatLanguageVersion>` exactly as written in the file.
        let languageVersion: String

        var testDescription: String {
            path
        }
    }

    let catroidCommit: String
    let assetsLastCommit: String
    let assetsPath: String
    let tests: [Entry]
}

enum LanguageTestCatalog {
    static let resourceRoot = "Resources/catrobatTests"

    static func rootURL() throws -> URL {
        let resources = try #require(Bundle.module.resourceURL)
        return resources.appending(path: resourceRoot, directoryHint: .isDirectory)
    }

    static func manifest() throws -> LanguageTestManifest {
        let url = try rootURL().appending(path: "manifest.json")
        return try JSONDecoder().decode(LanguageTestManifest.self, from: Data(contentsOf: url))
    }

    static func codeXMLURL(for path: String) throws -> URL {
        try rootURL().appending(path: path).appending(path: "code.xml")
    }

    static func codeXML(for path: String) throws -> Data {
        try Data(contentsOf: codeXMLURL(for: path))
    }

    /// The manifest's entries, or none if it cannot be read. For `@Test(arguments:)`,
    /// whose argument expression cannot throw; `FixtureProvenanceTests` asserts the
    /// count, so an unreadable manifest is a red test rather than a silent zero.
    static var entries: [LanguageTestManifest.Entry] {
        (try? manifest().tests) ?? []
    }
}
