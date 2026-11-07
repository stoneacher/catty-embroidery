@testable import catrobat_embroidery_ios
import Foundation
import Testing

/// What App Store review reads from the bundle (Release readiness D6, ADR-011 amendment): a
/// privacy manifest that declares no tracking, no collected data and exactly the
/// required-reason APIs the release code uses, and the export-compliance key.
///
/// The tests are hosted, so `Bundle.main` is the app bundle as it ships. The parts that can
/// genuinely fail are that the manifest *reaches* the bundle (a new file in the synchronized
/// folder is assumed to be copied as a resource; this test is the proof) and that the keys
/// exist. The content assertions compare the file with the decision. `/release` item 3
/// re-greps the code so the decision itself stays true.
@MainActor
@Suite("Release metadata")
struct ReleaseMetadataTests {
    @Test("the privacy manifest ships in the app bundle")
    func privacyManifestShipsInTheBundle() {
        #expect(Self.manifestURL != nil)
    }

    @Test("the manifest declares no tracking, no tracking domains and no collected data")
    func manifestDeclaresNoTrackingAndNoCollection() throws {
        let manifest = try Self.manifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    }

    /// `UserDefaults` holds the last opened project (CA92.1: the app's own data). File
    /// metadata dates the project list's rows: files in the app container (C617.1), shown to
    /// the user (DDA9.1). Nothing else in release code is a required-reason API.
    @Test("the manifest declares exactly the required-reason APIs the app uses")
    func manifestDeclaresExactlyTheRequiredReasonCategoriesUsed() throws {
        let entries = try #require(try Self.manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var declared: [String: Set<String>] = [:]
        for entry in entries {
            let category = try #require(entry["NSPrivacyAccessedAPIType"] as? String)
            let reasons = try #require(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
            declared[category, default: []].formUnion(reasons)
        }
        #expect(declared == [
            "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1", "DDA9.1"]
        ])
    }

    @Test("Info.plist declares no non-exempt encryption")
    func infoPlistDeclaresNoNonExemptEncryption() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool == false)
    }

    /// The home-screen label (Sebastian, 2026-11-07). Without a display name iOS falls back to the
    /// bundle name and shows "catrobat_embro…". Catroid's flavor is "Embroidery Designer", which
    /// iOS cuts off at about 12 characters, so the label is the short form and the store listing
    /// keeps the full name.
    ///
    /// Both values are checked, because they are separate files: the `Info.plist` key, and the
    /// `InfoPlist.xcstrings` entry a translated home screen reads. A catalog value of
    /// "Embroidered" beside an unchanged `Info.plist` turns this red.
    @Test("the home-screen label is \"Embroidery\", in Info.plist and in its localized form")
    func displayNameIsEmbroidery() {
        #expect(Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String == "Embroidery")
        #expect(Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String == "Embroidery")
    }

    // MARK: Helpers

    private static var manifestURL: URL? {
        Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
    }

    private static func manifest() throws -> [String: Any] {
        let url = try #require(manifestURL, "PrivacyInfo.xcprivacy is not in the app bundle")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(plist as? [String: Any])
    }
}
