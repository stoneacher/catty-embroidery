import EmbroideryEngine
import Testing

/// US-308 test item 2 — the name of the file on disk, which is **not** the header label.
///
/// They are unrelated fields in the format, and this suite's job is to keep them
/// unrelated. The label's rules come from the fixed-width `LA` field (15 characters,
/// ASCII); these come from the filesystem, and all four were measured against a real
/// write rather than assumed:
///
/// | input | result |
/// |---|---|
/// | `a/b.dst` | `/` is a path separator — `lastPathComponent` becomes `b.dst`, write fails NSError 4 |
/// | `.dst` (empty stem) | collapses to the directory, write fails NSError 512 |
/// | `a\0b.dst` | fails NSError 4, with the path truncated at the NUL (the error names a file "T") |
/// | 264 characters | fails NSError 514, "file name is invalid" — there is a 255-byte `NAME_MAX` |
///
/// Measured as *legal*, and therefore deliberately accepted: `Ünïcödé.dst`, `con:x.dst`,
/// `a\u{7F}b.dst` and `a\nb.dst` all write fine. The non-ASCII row is the important one —
/// **the file name may keep characters the header label cannot**, which is the
/// independence US-308 asks for, and Catroid's `sanitizeFileName` does not have.
@Suite("DST file name sanitisation")
struct DSTFileNameTests {
    // MARK: - Independence from the header label

    /// The criterion's own example: a 15-character label alongside a longer file name is
    /// legal. Nothing here consults `DesignName`, which is the point.
    @Test("a file name longer than the 15-character label limit is legal")
    func longerThanTheLabelLimit() throws {
        let name = try DSTFileName.validating(String(repeating: "a", count: 60)).get()
        #expect(name.stem.count == 60)
        #expect(name.value == String(repeating: "a", count: 60) + ".dst")
    }

    /// Non-ASCII is legal in a file name and illegal in a label. If this test ever turns
    /// red because someone applied the label's ASCII rule here, the two fields have been
    /// coupled and the criterion is broken.
    @Test("non-ASCII is accepted, unlike in the header label")
    func nonASCIIIsAccepted() throws {
        #expect(try DSTFileName.validating("Ünïcödé").get().value == "Ünïcödé.dst")
    }

    /// `/` is rejected here and accepted by the label — `DSTHeader` was measured writing
    /// `a/b:c` into `LA` untouched. The same character, two different verdicts, which is
    /// what "unrelated fields" means concretely.
    @Test("rejects the path separator that the label accepts")
    func pathSeparatorIsRejected() {
        #expect(throws: DSTFileNameProblem.prohibitedCharacter("/")) {
            try DSTFileName.validating("a/b").get()
        }
    }

    // MARK: - Empty (Catroid's bug)

    /// Catroid's `sanitizeFileName` has no empty check and produces a file literally
    /// named `.dst` — a hidden file on every Unix-like system, and a write that fails
    /// outright here (NSError 512, measured).
    @Test("rejects an empty stem rather than producing a file named .dst")
    func emptyStemIsRejected() {
        #expect(throws: DSTFileNameProblem.empty) {
            try DSTFileName.validating("").get()
        }
    }

    /// Trimming is shared with `DesignName` — that is a sensible rule applied twice, not
    /// a dependency between the two types — so an all-whitespace stem is `.empty` rather
    /// than a file named `"   .dst"`.
    @Test("an all-whitespace stem is empty")
    func allWhitespaceStemIsEmpty() {
        #expect(throws: DSTFileNameProblem.empty) {
            try DSTFileName.validating("  \t ").get()
        }
    }

    @Test("trims leading and trailing whitespace")
    func whitespaceIsTrimmed() throws {
        #expect(try DSTFileName.validating("  Rose  ").get().value == "Rose.dst")
    }

    // MARK: - NUL

    /// The fourth failure mode, found at planning by probing rather than by reading. NUL
    /// terminates the C string the filesystem actually receives, so the path is truncated
    /// somewhere unpredictable — the probe's error named a file called "T".
    @Test("rejects NUL, which truncates the path rather than failing cleanly")
    func nulIsRejected() {
        #expect(throws: DSTFileNameProblem.prohibitedCharacter("\0")) {
            try DSTFileName.validating("a\0b").get()
        }
    }

    // MARK: - NAME_MAX

    /// 255 **bytes** including the extension, so the longest legal stem is 251 ASCII
    /// characters.
    @Test("accepts a stem that brings the whole name to exactly 255 bytes")
    func exactlyAtTheLimit() throws {
        let name = try DSTFileName.validating(String(repeating: "a", count: 251)).get()
        #expect(name.value.utf8.count == 255)
        #expect(DSTFileName.maximumByteLength == 255)
    }

    @Test("rejects one byte over, surfacing the byte count")
    func oneByteOverTheLimit() {
        #expect(throws: DSTFileNameProblem.tooLongForFilesystem(byteCount: 256, limit: 255)) {
            try DSTFileName.validating(String(repeating: "a", count: 252)).get()
        }
    }

    /// **The limit is bytes, not characters**, and this is the test that tells the two
    /// apart. 126 `ü` is 126 characters — comfortably under any character-based cap — and
    /// 252 UTF-8 bytes, so with `.dst` it is 256 and must be rejected. A
    /// character-counting implementation passes every other test in this suite and fails
    /// this one.
    @Test("counts UTF-8 bytes rather than characters")
    func multiByteCharactersCountAsBytes() {
        #expect(throws: DSTFileNameProblem.tooLongForFilesystem(byteCount: 256, limit: 255)) {
            try DSTFileName.validating(String(repeating: "ü", count: 126)).get()
        }
    }

    /// The other side of the same boundary, so the test above cannot be satisfied by
    /// rejecting all multi-byte input.
    @Test("a multi-byte stem just inside the limit is accepted")
    func multiByteJustInsideTheLimit() throws {
        let name = try DSTFileName.validating(String(repeating: "ü", count: 125)).get()
        #expect(name.value.utf8.count == 254)
    }

    // MARK: - The extension

    /// The stem is used **verbatim**, so a stem that already ends in `.dst` yields
    /// `Rose.dst.dst`. Pinned as a decision rather than left to be discovered: the app
    /// derives the stem from a validated `DesignName`, never from a file name, so the
    /// case is reachable only if a user types the extension themselves — and doubling it
    /// is unambiguous, where stripping it would silently rename `Rose.dst` to `Rose`.
    @Test("a stem ending in .dst is not special-cased")
    func stemEndingInTheExtension() throws {
        #expect(try DSTFileName.validating("Rose.dst").get().value == "Rose.dst.dst")
    }

    @Test("the extension is lowercase dst")
    func extensionIsLowercase() {
        #expect(DSTFileName.fileExtension == "dst")
    }

    // MARK: - Deriving a file name from a design name

    /// **The independence bites when you try to use one as the other**, which is how this
    /// method was found: `DesignName` accepts `/` (the `LA` field carries it untouched) and
    /// `DSTFileName` rejects it, so `validating(designName.value)` can fail for a name the
    /// user was told was fine. Deriving needs a *sanitising* path — Catroid's
    /// `sanitizeFileName`, which is the one thing that method gets right — while
    /// `validating(_:)` stays the strict check for input that is a file name to begin with.
    @Test("a design name containing a path separator still yields a usable file name")
    func derivingReplacesTheSeparatorTheLabelKeeps() throws {
        let label = try DesignName.validating("a/b").get()
        #expect(label.value == "a/b", "the label keeps it")
        #expect(DSTFileName.sanitising(label).value == "a_b.dst", "the file name does not")
    }

    /// **Total by construction, and the argument type is what makes it so.** It takes a
    /// `DesignName` rather than a `String` precisely so the result needs no `Result`: a
    /// validated design name is non-empty, ASCII and at most 15 characters, so after
    /// substitution the stem is still non-empty and still at most 15 bytes — both bounds
    /// this suite pins elsewhere. A `String` overload could be handed 300 bytes of emoji and
    /// would have to fail.
    @Test("every valid design name yields a valid file name", arguments: [
        "a/b", "Rose", "a b", "...", "----", "0", "123456789012345", "a/b/c/d"
    ])
    func derivingIsTotalOverValidDesignNames(raw: String) throws {
        let label = try DesignName.validating(raw).get()
        let derived = DSTFileName.sanitising(label)

        // The round trip: whatever sanitising produced must itself pass the strict check.
        #expect(throws: Never.self) {
            try DSTFileName.validating(derived.stem).get()
        }
        #expect(derived.value.utf8.count <= DSTFileName.maximumByteLength)
        #expect(derived.stem.isEmpty == false)
    }

    /// A name that is nothing but separators would sanitise to nothing but underscores —
    /// still a usable name, and specifically **not** empty, which is the case Catroid ships
    /// as a file called `.dst`.
    @Test("a name of nothing but separators becomes underscores rather than nothing")
    func allSeparatorsBecomeUnderscores() throws {
        let label = try DesignName.validating("///").get()
        #expect(DSTFileName.sanitising(label).value == "___.dst")
    }

    /// Ordinary names pass through unchanged — without this, an implementation that
    /// replaced every character would satisfy every other test here.
    @Test("an ordinary design name is used verbatim")
    func ordinaryNamesAreUnchanged() throws {
        let label = try DesignName.validating("Octagon Rose").get()
        #expect(DSTFileName.sanitising(label).value == "Octagon Rose.dst")
    }
}
