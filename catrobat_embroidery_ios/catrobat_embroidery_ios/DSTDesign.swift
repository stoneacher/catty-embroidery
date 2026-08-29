import Foundation

/// A prepared `.dst` file, and the exported content type this app declares for it.
///
/// The `Transferable` conformance a `ShareLink` hands to the system lives in
/// `DSTDesign+Transferable.swift`.
///
/// **`nonisolated`, and that is required rather than tidy.** The project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so everything here is main-actor isolated
/// by default, while `Transferable.transferRepresentation` is a **nonisolated static**
/// requirement. A probe written during planning failed to compile — *"main actor-isolated
/// let 'dstID' can not be referenced from a nonisolated context"* — until both the type and
/// the identifier were marked `nonisolated`. Keep it that way.
nonisolated struct DSTDesign {
    /// The exported type identifier, declared in `Info.plist` under
    /// `UTExportedTypeDeclarations` (ADR-026, scope decision 1).
    ///
    /// Reverse DNS under a domain we control, matching `PRODUCT_BUNDLE_IDENTIFIER` and
    /// Catty's house style (`org.catrobat.pocketcode.catrobat`). **Not** prefixed `public`,
    /// `dyn` or `com.apple` — Apple reserves all three.
    ///
    /// It is *effectively permanent* once files exist in the wild, and the domain belongs
    /// to Catrobat rather than to this project, which is why it was a decision taken
    /// explicitly rather than a default.
    ///
    /// **Declared here and asserted against the plist**, not read from it. Reading it from
    /// `Bundle.main` would make `UTTypeDeclarationTests` tautological — the test would
    /// compare the plist against itself and pass with any identifier, including a
    /// misspelt one.
    static let contentTypeIdentifier = "org.catrobat.embroiderydesigner.dst"

    /// The file, **already written** — `ExportViewModel.prepare()` puts it on disk when a
    /// run terminates or a name is committed, long before this value is constructed.
    ///
    /// So this type carries a location and never a recipe: the `FileRepresentation` closure
    /// has nothing to build, which is exactly what planning correction 14 bought. A closure
    /// that wrote the file would report its failures to the *system* share UI instead of to
    /// us, and `ExportError`'s localised messages would be unreachable.
    let url: URL
}
