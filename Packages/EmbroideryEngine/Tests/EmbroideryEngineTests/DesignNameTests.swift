import EmbroideryEngine
import Testing

/// US-308 test item 1 — the design name the DST `LA` field can carry verbatim.
///
/// **`DesignName` is a rejecting layer in front of a mangling backstop.**
/// `DSTHeader.sanitized(_:)` silently maps everything outside printable ASCII to `_` and
/// truncates to 15 — pinned by `DSTHeaderTests.nameSanitization`, not by a
/// `sanitisationBackstopIsUnchanged` test, which an earlier version of this comment cited
/// and which never existed. The division of labour: this type refuses input a *user* can
/// see and fix, naming what is wrong; the header normalises input no user typed, so that no
/// caller anywhere — M4/M5, a `.catrobat` importer, a future CLI — can emit an over-long
/// `LA` field or one carrying a byte the format's own field terminators use. Two layers on
/// purpose, and ADR-026 records why they are not collapsed into one.
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

    // MARK: - The character rule

    /// The offending character is named, because "invalid character" leaves a user
    /// hunting through a string whose problem may be invisible — a combining accent, a
    /// non-breaking space, a smart quote the keyboard substituted.
    @Test("rejects non-ASCII, naming the offending character")
    func nonASCIIIsRejected() {
        #expect(throws: DesignNameProblem.unsupportedCharacter( "ö")) {
            try DesignName.validating("Rösé").get()
        }
    }

    /// The *first* offending character in reading order, so the report is deterministic
    /// and a user fixing them left to right sees progress.
    @Test("names the first offending character, not any offending character")
    func firstOffenderIsNamed() {
        #expect(throws: DesignNameProblem.unsupportedCharacter( "ü")) {
            try DesignName.validating("aüb¿c").get()
        }
    }

    /// **The character rule is checked before length**, and the order is a UX decision rather than an
    /// accident. A 19-character name containing "ö" reports the "ö": the character can
    /// never be stored whatever the length, so reporting length first would have the user
    /// delete characters and fail again. Deterministic first-violation reporting is the
    /// same discipline ADR-025 pins for the header's fields.
    @Test("a name that is both too long and non-ASCII reports the character")
    func asciiIsCheckedBeforeLength() {
        #expect(throws: DesignNameProblem.unsupportedCharacter( "ö")) {
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

    /// **The defect an in-loop review found, and the reason this rule is "printable ASCII"
    /// rather than `Character.isASCII`.** `Character.isASCII` is `asciiValue != nil`, and
    /// `asciiValue` special-cases the `"\r\n"` grapheme cluster to `0x0A` — so `isASCII`
    /// reports CRLF as **one ASCII character**. Under that rule this name validated as 15
    /// characters and measured **28 bytes**, the header truncated it to 15 *scalars*, and
    /// the "carried verbatim" promise was false in exactly the silent-truncation way this
    /// story exists to replace.
    @Test("a CRLF cluster is refused, though Character.isASCII calls it ASCII")
    func crlfIsRefused() {
        let name = "a" + String(repeating: "\r\n", count: 13) + "b"
        #expect(name.count == 15, "the trap: fifteen Characters…")
        #expect(name.utf8.count == 28, "…and twenty-eight bytes")
        #expect(throws: DesignNameProblem.unsupportedCharacter("\r\n")) {
            try DesignName.validating(name).get()
        }
    }

    /// **Two of these are the header's own field terminators.** `appendField` closes every
    /// field with `0x0A 0x1A`, so a label containing either would corrupt the structure a
    /// reader scans for; `0x00` truncates any C string the value reaches. All of them are
    /// ASCII, which is why the case is not called `nonASCII`.
    @Test("ASCII control characters are refused", arguments: [
        "\u{00}", "\u{0A}", "\u{1A}", "\u{7F}", "\u{09}"
    ] as [Character])
    func controlCharactersAreRefused(offender: Character) {
        #expect(offender.isASCII, "the trap: every one of these is ASCII")
        #expect(throws: DesignNameProblem.unsupportedCharacter(offender)) {
            try DesignName.validating("a\(offender)b").get()
        }
    }

    /// The control: the whole printable range is accepted, so the rule above cannot be
    /// satisfied by a validator that refuses everything unusual.
    @Test("every printable ASCII character is accepted")
    func everyPrintableCharacterIsAccepted() {
        for value in 0x20 ... 0x7E {
            let character = Character(UnicodeScalar(UInt8(value)))
            #expect(throws: Never.self) { try DesignName.validating("a\(character)b").get() }
        }
    }

    /// **Fifteen characters are now genuinely fifteen bytes**, the invariant the CRLF defect
    /// falsified and the reason `maximumLength` can be called both a character and a byte
    /// bound.
    @Test("an accepted name's character count equals its byte count")
    func acceptedNamesAreOneBytePerCharacter() throws {
        for raw in ["Rose", "a/b:c-d_e", "123456789012345", "~!@#$%^&*()"] {
            let name = try DesignName.validating(raw).get()
            #expect(name.value.count == name.value.utf8.count, "\(raw)")
        }
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
