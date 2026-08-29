import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Hands a prepared `.dst` file to the system share sheet (US-308, ADR-026).
///
/// **The closure builds nothing.** Export is eager — `ExportViewModel.prepare()` writes the
/// file when a run terminates and when a name is committed — so by the time a `DSTDesign`
/// exists there is a file at `url` and all that is left is to name it. Planning correction
/// 14 records the two independent reasons: a `ShareLink` needs its item at *construction*
/// time, and a write happening only in here would report failure to the system's own share
/// UI, leaving `ExportError`'s localised sentences with no consumer. It also keeps the
/// representation testable at our deployment target — `Transferable.exported(as:)` is
/// iOS 18.2+, so a closure that did real work could not be driven by a test on iOS 17.
extension DSTDesign: Transferable {
    /// `nonisolated`, and required rather than tidy: the project sets
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, while this is a **nonisolated static**
    /// protocol requirement. `DSTDesign` itself is declared `nonisolated` for the same
    /// reason; spelling it again here is what keeps the extension from picking the file's
    /// default back up.
    nonisolated static var transferRepresentation: some TransferRepresentation {
        // `UTType(exportedAs:)` is correct *here* — this is a declaration of a type we own,
        // matching the `UTExportedTypeDeclarations` entry in `Info.plist`. It is emphatically
        // not a lookup: `UTTypeDeclarationTests` pins that `UTType(exportedAs:)` reports
        // `isDeclared == true` even for an identifier no bundle declares, which is why the
        // plist canary uses the failable `UTType(_:)` instead. Do not swap one for the other.
        FileRepresentation(exportedContentType: UTType(exportedAs: DSTDesign.contentTypeIdentifier)) { design in
            // `allowAccessingOriginalFile: false` is deliberate rather than conservative: the
            // system takes its own copy, so our temp directory can be cleared on the next
            // `prepare()` or on reset without breaking a share already in flight. Catty never
            // cleaned up at all; this is the property that lets us.
            SentTransferredFile(design.url, allowAccessingOriginalFile: false)
        }
    }
}
