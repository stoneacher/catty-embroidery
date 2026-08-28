@testable import catrobat_embroidery_ios
import Foundation
import Testing
import UniformTypeIdentifiers

/// US-308 test item 7 — the `Info.plist` declaration is really wired up.
///
/// **The whole point of this suite is that the obvious test cannot work.**
/// `UTType(exportedAs:)` *declares* a type your app owns; it does not look one up, so it
/// neither validates the plist nor fails when the declaration is missing. An earlier draft
/// of the story asserted it "traps at runtime if the identifier is not declared" and
/// proposed it as the canary; that was retracted (Codex round 3), and planning then found
/// the trap is **broader** than the retraction said — see `theExportedAsTrap` below.
///
/// So the canary is the **failable lookup** `UTType(_:)`, which resolves against declared
/// types. Two things were established by experiment before this file was written, and both
/// constrain it:
///
/// - **It is capable of failing.** With the declaration present, thirteen probe assertions
///   passed on `iPhone 17` / iOS 26.5; with `Info.plist` emptied back to `<dict/>` and
///   re-run on the same simulator, six flipped to failing, including the lookup. No stale
///   LaunchServices false pass, even immediately after the same bundle ID had been
///   installed *with* the declaration.
/// - **It can only ever be a hosted app test.** The same probe run as a bare macOS
///   executable, and again from inside a hand-built `.app` carrying the declaration in its
///   own `Info.plist`, returned `nil` both times: the declaration resolves only once
///   LaunchServices has *registered* the bundle, which simulator installation does and a
///   direct exec does not. This target is hosted (`TEST_HOST`/`BUNDLE_LOADER`), so it
///   works — but it could never be moved to the package for speed, and that is worth
///   knowing before someone tries.
@Suite("Exported UTType declaration")
struct UTTypeDeclarationTests {
    /// Sanity check on the premise, so a failure below cannot be misread as a plist
    /// problem when it is really a hosting problem: these tests run *inside* the app.
    @Test("the tests run in the app process that carries the declaration")
    func sAreHostedByTheApp() {
        #expect(Bundle.main.bundleIdentifier == "org.catrobat.embroiderydesigner")
    }

    // MARK: - The lookup canary

    /// The identifier is `org.catrobat.embroiderydesigner.dst` (scope decision 1): reverse
    /// DNS under a domain we control, matching `PRODUCT_BUNDLE_IDENTIFIER` and Catty's
    /// house style. **Not** prefixed `public`, `dyn` or `com.apple` — Apple reserves all
    /// three.
    @Test("the identifier resolves against the type database")
    func identifierResolves() throws {
        _ = try #require(
            UTType(DSTDesign.contentTypeIdentifier),
            "the UTExportedTypeDeclarations entry is missing or malformed"
        )
    }

    /// **Both conformances, and `public.content` is not decoration.** `public.data` is what
    /// lets Finder and the Files app represent a stored item at all; `public.content` is
    /// what Apple documents as the conformance that allows sharing over AirDrop — and this
    /// story exists to share the file, so omitting it would break the headline use case on
    /// the most likely destination.
    ///
    /// What this test proves is that both conformances *resolve*. That AirDrop then works
    /// is Apple's documented behaviour, not something a simulator test can show; it needs
    /// two devices and belongs to the manual pass.
    @Test("the resolved type conforms to public.data and public.content")
    func conformances() throws {
        let type = try #require(UTType(DSTDesign.contentTypeIdentifier))
        #expect(type.conforms(to: .data))
        #expect(type.conforms(to: .content))
    }

    /// A type that failed to resolve comes back *dynamic* — `dyn.…` — rather than nil in
    /// some code paths, so this pins the declaration as the source rather than a
    /// system-invented placeholder.
    @Test("the type is declared rather than dynamically invented")
    func isNotDynamic() throws {
        let type = try #require(UTType(DSTDesign.contentTypeIdentifier))
        #expect(type.isDynamic == false)
        #expect(type.isDeclared)
    }

    @Test("the type claims the dst filename extension")
    func claimsTheExtension() throws {
        let type = try #require(UTType(DSTDesign.contentTypeIdentifier))
        #expect(type.preferredFilenameExtension == "dst")
    }

    /// The reverse direction, which is what the Files app and a share sheet actually do:
    /// given a file called `something.dst`, they ask the database what it is. A declaration
    /// that resolved by identifier but claimed no extension would pass every test above
    /// and fail this one.
    @Test("a .dst file resolves back to our type")
    func extensionResolvesToOurType() throws {
        let type = try #require(UTType(filenameExtension: "dst"))
        #expect(type.identifier == DSTDesign.contentTypeIdentifier)
    }

    /// The uppercase tag, which exists because embroidery software and machines write both
    /// cases. Asserted separately from the lowercase one, since a declaration listing only
    /// `dst` passes `claimsTheExtension`.
    @Test("the uppercase DST extension also resolves to our type")
    func uppercaseExtensionResolves() throws {
        let type = try #require(UTType(filenameExtension: "DST"))
        #expect(type.identifier == DSTDesign.contentTypeIdentifier)
    }

    /// The description is localised through `InfoPlist.xcstrings`, so it must resolve to
    /// real text rather than to the key — the same `≠ key` check `AppStringsTests` makes,
    /// and for the same reason: a missing entry renders as its own key and looks like text
    /// to a screenshot.
    @Test("the localised description resolves rather than falling back to its key")
    func localisedDescriptionResolves() throws {
        let type = try #require(UTType(DSTDesign.contentTypeIdentifier))
        let description = try #require(type.localizedDescription)
        #expect(description != "uttype.dst.description")
        #expect(description.isEmpty == false)
    }

    // MARK: - The structural canary

    /// A second canary that **does not consult the type database at all**, so it survives
    /// any future change in how LaunchServices resolves and localises. Belt and braces for
    /// a handful of lines, and it was verified to fail correctly in the negative run.
    @Test("the plist entry itself has the expected structure")
    func plistStructure() throws {
        let declarations = try #require(
            Bundle.main.infoDictionary?["UTExportedTypeDeclarations"] as? [[String: Any]],
            "UTExportedTypeDeclarations is absent from the built Info.plist"
        )
        let entry = try #require(
            declarations.first { $0["UTTypeIdentifier"] as? String == DSTDesign.contentTypeIdentifier }
        )

        let conformsTo = try #require(entry["UTTypeConformsTo"] as? [String])
        #expect(conformsTo.contains("public.data"))
        #expect(conformsTo.contains("public.content"))

        let tags = try #require(entry["UTTypeTagSpecification"] as? [String: Any])
        let extensions = try #require(tags["public.filename-extension"] as? [String])
        #expect(extensions == ["dst", "DST"])

        // ADR-011: we open nothing, so we claim no handler rank.
        #expect(entry["LSHandlerRank"] == nil)
    }

    // MARK: - The trap, pinned

    /// **Characterisation, not a red-phase test** — this is already true and always was.
    /// It exists so nobody re-invents the canary that cannot work.
    ///
    /// `UTType(exportedAs:)` builds a type *from* an identifier without consulting the
    /// declaration. Planning measured that `isDeclared` is `true` even for a completely
    /// undeclared identifier, which is broader than the story's retraction stated: **any**
    /// assertion built on `UTType(exportedAs:)`, `isDeclared` included, passes with the
    /// plist entry missing entirely. The conformance check is the one thing that does not
    /// survive, which is why the real canary asserts conformances too.
    @Test("UTType(exportedAs:) cannot detect a missing declaration")
    func theExportedAsTrap() {
        let undeclared = UTType(exportedAs: "org.catrobat.embroiderydesigner.notathing")
        #expect(undeclared.isDeclared, "the trap: this is true for an undeclared identifier")
        #expect(undeclared.conforms(to: .data) == false)
    }
}
