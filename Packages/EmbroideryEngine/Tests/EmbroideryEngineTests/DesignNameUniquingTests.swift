import EmbroideryEngine
import Testing

/// Project management slice 1 (brief D4): a generated name — a duplicate's, a new draft's, a
/// sample opened as a project — is made unique as `"<base> N"`, and still fits the DST `LA`
/// field. User renames are not uniqued; only names the app makes up.
///
/// Domain: a validated `DesignName`. Rules: N from 2; an existing suffix (a terminal ASCII space
/// and decimal integer) stripped first; the base truncated by the suffix's length, trailing
/// spaces removed; ASCII-only case folding.
@Suite("Design name uniquing")
struct DesignNameUniquingTests {
    private static func name(_ raw: String) throws -> DesignName {
        try DesignName.validating(raw).get()
    }

    private static func uniqued(_ raw: String, avoiding taken: [String]) throws -> String {
        try name(raw).uniqued(avoiding: taken).value
    }

    @Test("a free name is kept as it is")
    func free() throws {
        #expect(try Self.uniqued("Flower", avoiding: ["Star", "Coil"]) == "Flower")
    }

    @Test("a taken name gets the next free number, from 2")
    func numbered() throws {
        #expect(try Self.uniqued("Flower", avoiding: ["Flower"]) == "Flower 2")
        #expect(try Self.uniqued("Flower", avoiding: ["Flower", "Flower 2", "Flower 3"]) == "Flower 4")
    }

    @Test("an existing number is replaced, not appended to")
    func existingSuffix() throws {
        #expect(try Self.uniqued("Flower 2", avoiding: ["Flower", "Flower 2"]) == "Flower 3")
        #expect(try Self.uniqued("Area 51", avoiding: ["Area 51"]) == "Area 2")
    }

    @Test("the base is shortened so the number fits the 15-character field")
    func truncation() throws {
        #expect(try Self.uniqued("Octagon Rosette", avoiding: ["Octagon Rosette"]) == "Octagon Roset 2")
        let taken = ["ABCDEFGHIJKLMNO"] + (2 ... 9).map { "ABCDEFGHIJKLM \($0)" }
        #expect(try Self.uniqued("ABCDEFGHIJKLMNO", avoiding: taken) == "ABCDEFGHIJKL 10")
        let hundred = ["ABCDEFGHIJKLMNO"] + (2 ... 9).map { "ABCDEFGHIJKLM \($0)" }
            + (10 ... 99).map { "ABCDEFGHIJKL \($0)" }
        #expect(try Self.uniqued("ABCDEFGHIJKLMNO", avoiding: hundred) == "ABCDEFGHIJK 100")
    }

    @Test("spaces left at the cut are removed")
    func trailingSpaces() throws {
        // Spaces inside the base stay; only those the cut leaves at its end go.
        #expect(try Self.uniqued("Big     Flower", avoiding: ["Big     Flower"]) == "Big     Flowe 2")
        #expect(try Self.uniqued("Ab           Cd", avoiding: ["Ab           Cd"]) == "Ab 2")
    }

    /// A suffix needs a word before it: a bare number is a base, and a one-character base keeps
    /// its character. (A base cut to nothing would need a 14-digit number, so it cannot occur.)
    @Test("short and number-only names")
    func shortNames() throws {
        #expect(try Self.uniqued("7", avoiding: ["7"]) == "7 2")
        #expect(try Self.uniqued("A 1", avoiding: ["A 1", "A 2"]) == "A 3")
        #expect(try Self.uniqued("1 5", avoiding: ["1 5"]) == "1 2")
    }

    @Test("names compare without regard to ASCII case")
    func caseInsensitive() throws {
        #expect(try Self.uniqued("Flower", avoiding: ["FLOWER"]) == "Flower 2")
        #expect(try Self.uniqued("Flower", avoiding: ["flower", "FLOWER 2"]) == "Flower 3")
        // Folding is ASCII only: a name read from a refused file may hold anything.
        #expect(try Self.uniqued("Flower", avoiding: ["FLÖWER"]) == "Flower")
        // The Kelvin sign lowercases to an ASCII k under Unicode folding; it is not the
        // letter K, and the names do not collide in the field (found by mutation).
        #expect(try Self.uniqued("kite", avoiding: ["\u{212A}ite"]) == "kite")
    }

    @Test("taken names are compared as the field stores them, trimmed")
    func trimmedComparison() throws {
        #expect(try Self.uniqued("Flower", avoiding: ["  Flower  "]) == "Flower 2")
    }

    /// Every generated name is a valid `DesignName` and free, over bases of every length and
    /// taken sets that crowd the suffixes.
    @Test("every result is valid and unique", arguments: 1 ... 15)
    func property(length: Int) throws {
        let base = String("Abc De Fghij Kl".prefix(length))
        guard case .success = DesignName.validating(base) else { return }
        var taken: [String] = []
        for _ in 0 ..< 120 {
            let next = try Self.uniqued(base, avoiding: taken)
            #expect(DesignName.validating(next) == .success(try Self.name(next)))
            #expect(next.count <= DesignName.maximumLength)
            #expect(!taken.contains { $0.lowercased() == next.lowercased() }, "\(next) reused")
            taken.append(next)
        }
    }
}
