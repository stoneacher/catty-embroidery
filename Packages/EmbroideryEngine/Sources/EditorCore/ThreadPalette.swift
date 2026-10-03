/// The curated thread palette (US-410, ADR-040).
public enum ThreadSwatch: Sendable, Hashable, CaseIterable {
    case red

    public var hex: String {
        ""
    }

    public init?(hex _: String) {
        nil
    }
}
