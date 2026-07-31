import EmbroideryEngine
import Foundation
import Interpreter
import ProgramModel
import Testing

/// US-209 support: reading DST header fields back out of emitted file bytes, plus
/// the golden-program fixture loader and the finalize-name extractor.
///
/// The field table is **hard-coded literals, deliberately not derived from
/// `DSTHeader`** — same discipline as `EmbroideryEngineTests/DSTFileReader`, whose
/// header says an independent oracle must not reuse the writer's definitions. If
/// `appendField`'s layout changes, these offsets must be re-derived by hand and
/// the change noticed, rather than silently tracking it.
///
/// The precise claim, since a looser one would be false: this is independent of the
/// writer's *code*, not of its ADR-012-pinned *layout*. The widths below are
/// transcribed from the same Tajima field sizes `DSTHeader` writes, so the reader
/// cannot discriminate a wrong width *choice* — only a wrong value or a shifted
/// layout (verified: `CO` width 2 → 3 shifts the extents and takes
/// `displacedSquareWritesExtentsRelativeToItsFirstStitch` red).
///
/// Offsets follow from the Tajima layout: each field is `TAG:` + value +
/// padding-to-width + `\n` + 0x1A, i.e. tag 3 + width + 2 bytes. LA is 15 wide
/// (3+15+2 = 20), ST 6 (11), CO 2 (7), the four extents 4 each (9), AX/AY 5 (10).
enum DSTHeaderField {
    case label
    case stitchCount
    case colorBlocks
    case extentPlusX
    case extentMinusX
    case extentPlusY
    case extentMinusY
    case endOffsetX
    case endOffsetY

    var tag: String {
        switch self {
        case .label: "LA"
        case .stitchCount: "ST"
        case .colorBlocks: "CO"
        case .extentPlusX: "+X"
        case .extentMinusX: "-X"
        case .extentPlusY: "+Y"
        case .extentMinusY: "-Y"
        case .endOffsetX: "AX"
        case .endOffsetY: "AY"
        }
    }

    /// The field's value width, per the Tajima header layout.
    var width: Int {
        switch self {
        case .label: 15
        case .stitchCount: 6
        case .colorBlocks: 2
        case .extentPlusX, .extentMinusX, .extentPlusY, .extentMinusY: 4
        case .endOffsetX, .endOffsetY: 5
        }
    }

    /// The pad byte: the label is space-padded, numeric fields NUL-padded.
    var pad: UInt8 {
        self == .label ? 0x20 : 0x00
    }

    /// The fields in file order.
    static let fileOrder: [DSTHeaderField] = [
        .label, .stitchCount, .colorBlocks,
        .extentPlusX, .extentMinusX, .extentPlusY, .extentMinusY,
        .endOffsetX, .endOffsetY
    ]

    /// Byte offset of the field's tag from the start of the header: the sum of the
    /// preceding fields' whole widths (`TAG:` 3 + value width + `\n` 0x1A 2).
    var offset: Int {
        Self.fileOrder.prefix { $0 != self }.reduce(0) { $0 + 3 + $1.width + 2 }
    }
}

/// The three tag bytes (`"ST:"`) at the field's offset — asserted alongside the
/// value so a shifted layout is reported as a wrong tag, not a wrong number.
func dstHeaderTag(_ header: [UInt8], _ field: DSTHeaderField) -> String {
    asciiField(Array(header[field.offset ..< field.offset + 3]))
}

/// The field's value with its **trailing** padding stripped.
///
/// Trailing only, not every pad byte: the label pads with 0x20, so filtering all
/// pad bytes would silently eat the interior spaces of a name like
/// `"N_hen _ Quadrat"` and quietly compare something the file does not contain.
/// (Found by `designNameIsSanitizedAtTheHeaderNotByTheInterpreter` going red on a
/// first version of this reader that did exactly that.)
///
/// Still lossy at one edge, named so the doc is not read as fully faithful: a label
/// with *significant trailing spaces* is indistinguishable from its padding —
/// `writeEmbroideryToFile("square ")` is reachable and `DSTHeader.sanitized`
/// preserves that space. Inherent to a space-padded fixed-width field, not a
/// defect in this reader; a test needing that distinction must read the raw bytes.
func dstHeaderField(_ header: [UInt8], _ field: DSTHeaderField) -> String {
    let start = field.offset + 3
    var bytes = Array(header[start ..< start + field.width])
    while bytes.last == field.pad {
        bytes.removeLast()
    }
    return asciiField(bytes)
}

/// Header fields are ASCII by construction (`DSTHeader` sanitizes the label and
/// every other field is digits). A non-decodable field is a defect, so it
/// surfaces as a value no expectation matches rather than as a crash.
private func asciiField(_ bytes: [UInt8]) -> String {
    String(bytes: bytes, encoding: .utf8) ?? "<not utf8: \(bytes)>"
}

/// One run of a golden program, serialized. A struct rather than a tuple so the
/// members are named at every use site (and SwiftLint's `large_tuple` agrees).
struct GoldenProgramRun {
    let file: DSTFile
    let stream: EmbroideryStream
    let events: [InterpreterEvent]
}

/// Runs `program` to completion and serializes it under the name **the program
/// itself asked for** — never a restated literal, which is the join
/// `designNameInTheFileComesFromTheProgram` pins.
func runAndSerialize(_ program: Program, clock: InterpreterClock) throws -> GoldenProgramRun {
    var interpreter = Interpreter(program: program, clock: clock)
    let events = interpreter.run(maxTicks: 100)
    let stream = interpreter.assembledStream()
    let name = try #require(finalizedDesignName(events))
    return GoldenProgramRun(file: DSTFile(stream: stream, name: name), stream: stream, events: events)
}

/// The design name a run asked to be written under, from its own events.
func finalizedDesignName(_ events: [InterpreterEvent]) -> String? {
    events.compactMap { event -> String? in
        guard case let .finalizeRequested(name) = event else { return nil }
        return name
    }.last
}

/// US-209's committed golden, loaded from this test target's own resources
/// (SPM declares resources per target, so `EmbroideryEngineTests`' fixtures are
/// out of reach here — hence the `resources:` clause added in this story).
///
/// The filename is keyed off `GoldenSquare.designName`, so renaming the design
/// breaks the *load* rather than the *diff* — deliberate, since a rename that left
/// a stale fixture in place would be the worse failure, but it means a `#require`
/// failure here can mean "renamed", not only "missing".
func goldenSquareFixture() throws -> Data {
    let url = try #require(Bundle.module.url(
        forResource: GoldenSquare.designName,
        withExtension: "dst",
        subdirectory: "Resources/GoldenPrograms"
    ))
    return try Data(contentsOf: url)
}
