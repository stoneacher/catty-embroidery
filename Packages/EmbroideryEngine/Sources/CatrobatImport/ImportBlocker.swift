/// One reason a `code.xml` cannot be imported (language-test runner brief, D7).
///
/// The importer collects every blocker it meets rather than stopping at the first,
/// so the runner can say what a test needs. Cases are added slice by slice.
package enum ImportBlocker: Error, Hashable, Sendable {
    /// The data is not well-formed XML.
    case malformed
    /// An XStream `reference=` path that leads nowhere, or to another reference.
    case unresolvedReference(String)
}
