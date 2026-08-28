import EmbroideryEngine
import Testing

/// US-308 test item 1 — the design name the DST `LA` field can carry verbatim.
///
/// **`DesignName` is a rejecting layer in front of a mangling backstop that already
/// exists.** `DSTHeader.sanitized(_:)` silently maps non-ASCII to `_` and truncates to
/// 15, and it stays exactly as it is (`DSTHeaderTests.sanitisationBackstopIsUnchanged`
/// pins that). The division of labour: this type refuses input a *user* can see and fix,
/// naming what is wrong; the header normalises input no user typed, so that no caller
/// anywhere — M4/M5, a `.catrobat` importer, a future CLI — can emit a 16-byte or
/// non-ASCII `LA` field. Two layers on purpose, and ADR-026 records why they are not
/// collapsed into one.
///
/// Every test here asserts the **payload**, not merely that validation failed. A test
/// that only checked "is not valid" would pass against a validator that rejects
/// everything, which is this repo's named "test that could not fail" pattern.
///
/// `validating(_:)` returns a `Result`, so the app can render the problem rather than
/// catch it; these tests reach the two sides through `get()` and `#expect(throws:)`
/// rather than through hand-rolled `success`/`failure` accessors.
@Suite("Design name validation")
struct DesignNameTests {
    // MARK: - The limit

    /// 15 is Catroid's limit and the `LA` field's width, not Catty's 16 (ADR-012).
    @Test("accepts exactly 15 characters")
    func fifteenCharactersFit() throws {
        #expect(try DesignName.validating("123456789012345").get().value == "123456789012345")
        #expect(DesignName.maximumLength == 15)
    }

    /// The count is carried so that the field's live counter and the error can agree
    /// without recomputing it, and so this test can prove the count is the *name's*
    /// rather than a constant.
    @Test("rejects 16 characters, surfacing the count")
    func sixteenCharactersAreRejected() {
        #expect(throws: DesignNameProblem.tooLong(count: 16, limit: 15)) {
            try DesignName.validating("1234567890123456").get()
        }
    }

    /// A longer overrun must report *its own* count — 16 hard-coded would pass the test
    /// above and fail here.
    @Test("a much longer name reports its own count")
    func longerNameReportsItsOwnCount() {
        #expect(throws: DesignNameProblem.tooLong(count: 40, limit: 15)) {
            try DesignName.validating(String(repeating: "a", count: 40)).get()
        }
    }

    // MARK: - ASCII

    /// The offending character is named, because "invalid character" leaves a user
    /// hunting through a string whose problem may be invisible — a combining accent, a
    /// non-breaking space, a smart quote the keyboard substituted.
    @Test("rejects non-ASCII, naming the offending character")
    func nonASCIIIsRejected() {
        #expect(throws: DesignNameProblem.nonASCII(character: "ö")) {
            try DesignName.validating("Rösé").get()
        }
    }

    /// The *first* offending character in reading order, so the report is deterministic
    /// and a user fixing them left to right sees progress.
    @Test("names the first offending character, not any offending character")
    func firstOffenderIsNamed() {
        #expect(throws: DesignNameProblem.nonASCII(character: "ü")) {
            try DesignName.validating("aüb¿c").get()
        }
    }

    /// **ASCII is checked before length**, and the order is a UX decision rather than an
    /// accident. A 19-character name containing "ö" reports the "ö": the character can
    /// never be stored whatever the length, so reporting length first would have the user
    /// delete characters and fail again. Deterministic first-violation reporting is the
    /// same discipline ADR-025 pins for the header's fields.
    @Test("a name that is both too long and non-ASCII reports the character")
    func asciiIsCheckedBeforeLength() {
        #expect(throws: DesignNameProblem.nonASCII(character: "ö")) {
            try DesignName.validating("Rösé Röse Röse Röse").get()
        }
    }

    /// Printable ASCII punctuation is legal — the `LA` field is bytes, and `DSTHeader`
    /// was measured passing `/` and `:` through untouched. The *file name* rejects `/`;
    /// the label does not, and that is the independence US-308 asks for.
    @Test("printable ASCII punctuation is accepted, including / and :")
    func punctuationIsAccepted() throws {
        #expect(try DesignName.validating("a/b:c-d_e").get().value == "a/b:c-d_e")
    }

    // MARK: - Empty and whitespace (scope decision 2)

    @Test("rejects the empty string")
    func emptyIsRejected() {
        #expect(throws: DesignNameProblem.empty) {
            try DesignName.validating("").get()
        }
    }

    /// **Trim on input, then validate** — Sebastian's scope decision 2, forced by the
    /// engine: `DSTHeader` writes `"  pad"` into the `LA` field verbatim and never trims,
    /// so untrimmed input reaches the machine. Rejecting instead was declined because
    /// trailing spaces are invisible in a text field, making the error's cause unseeable.
    @Test("trims leading and trailing whitespace, then validates")
    func whitespaceIsTrimmed() throws {
        #expect(try DesignName.validating("  Rose  ").get().value == "Rose")
    }

    /// The consequence of trimming that has to be pinned: an all-whitespace name is
    /// `.empty`, not valid. In the `LA` field it would be indistinguishable from an empty
    /// one anyway.
    @Test("an all-whitespace name is empty rather than valid")
    func allWhitespaceIsEmpty() {
        #expect(throws: DesignNameProblem.empty) {
            try DesignName.validating("   ").get()
        }
        #expect(throws: DesignNameProblem.empty) {
            try DesignName.validating("\t\n ").get()
        }
    }

    /// Interior spaces are ordinary characters — only the edges are trimmed.
    @Test("interior spaces survive trimming")
    func interiorSpacesSurvive() throws {
        #expect(try DesignName.validating(" a b ").get().value == "a b")
    }

    /// Trimming happens *before* the length check, so 15 characters padded with spaces is
    /// valid rather than 17-and-too-long. Without this the user would be told to delete
    /// characters they cannot see.
    @Test("trimming precedes the length check")
    func trimmingPrecedesTheLengthCheck() throws {
        #expect(try DesignName.validating(" 123456789012345 ").get().value == "123456789012345")
    }

    // MARK: - The counter's input

    /// The live counter and the validator must count the *same* string, or the field can
    /// show "15/15" while reporting `.tooLong`. `normalised(_:)` is that one definition,
    /// exposed so the view cannot invent a second one.
    ///
    /// It counts the **trimmed** string deliberately: a trailing space is not going into
    /// the file, so it must not consume the user's budget.
    @Test("the counter counts the trimmed string")
    func counterCountsTheTrimmedString() {
        #expect(DesignName.normalised("  Rose  ") == "Rose")
        #expect(DesignName.normalised("  Rose  ").count == 4)
        #expect(DesignName.normalised("123456789012345 ").count == 15)
    }
}
