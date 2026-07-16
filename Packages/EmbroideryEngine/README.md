# EmbroideryEngine

A platform-independent Swift package for translating programmatic needle movements into machine-readable Tajima DST embroidery files. The engine turns stitch commands into byte-verified DST exports as in-memory `Data`, with no dependencies and strict concurrency compliance.

EmbroideryEngine powers the embroidery functionality of the Catrobat iOS app, porting the byte-level semantics of Catroid's `org.catrobat.catroid.embroidery` module while maintaining compatibility with the Catty reference fixtures. It is deliberately synchronous, uses only Sendable value types, and runs Swift 6 strict concurrency—the app layer controls async boundaries and actor placement.

## Quick Start

```swift
import EmbroideryEngine

// Set up a manager to record stitch commands across layers and actors
var manager = EmbroideryPatternManager()

// Add stitches (actor 0 on layer 0)
let actor = ActorID(0)
manager.addStitch(at: StagePoint(x: 10, y: 20), layer: 0, actor: actor)
manager.addStitch(at: StagePoint(x: 50, y: 60), layer: 0, actor: actor)

// Assemble all layers into a stream (in z-order)
let stream = manager.assembled()

// Export to a machine-readable DST file
let file = DSTFile(stream: stream, name: "MyDesign")

// Write to disk or compare bytes
try file.write(to: designURL)
// Or inspect: let bytes = file.data
```

## Public API

### Geometry: Coordinate Spaces

**StagePoint** — A point in stage space (center origin, y-up, 500×500 pt virtual stage; 1 pt = 0.2 mm). Used throughout for pattern generation and needle updates.
```swift
let point = StagePoint(x: 10.5, y: 20.5)
```

**EmbroideryPoint** — A point in embroidery units (0.1 mm, the DST coordinate grid). Created by converting stage points with a factor of 2.0 and Java rounding per ADR-012. Read-only in normal use; appear in emitted stitches.
```swift
let embroideryPoint = EmbroideryPoint(converting: stagePoint)
```

See [ADR-007](../../docs/DECISIONS.md) for the coordinate space design.

### Stitch Domain

**ThreadColor** — An RGB thread color, platform-independent stand-in for UIColor. Includes hex parsing (UTF-16 code-unit based, matching Java semantics) for the Set Thread Color brick.
```swift
let black = ThreadColor.black
let red = ThreadColor(red: 255, green: 0, blue: 0)
let parsed = ThreadColor(hexString: "#FF0000")  // Returns nil if malformed
```

**Stitch** — One needle penetration, carrying position, color, and DST record flags.
```swift
let stitch = Stitch(
    position: EmbroideryPoint(x: 100, y: 200),
    color: .black,
    isJump: false,
    isColorChange: false
)
```

**NeedleUpdate** — Needle state (position and heading) passed to patterns once per movement tick.
```swift
let update = NeedleUpdate(position: StagePoint(x: 10, y: 20), heading: 45)
```

**ActorID** — Identifies the sprite/actor whose stitch command produced a record (used for workspace dedup and actor-change tie-offs).
```swift
let actor = ActorID(42)
```

### Stitch Patterns

**StitchPattern** protocol — A pure state machine for stitch generation. Patterns return stage-space positions; the stream owns unit conversion, interpolation, and flags.
```swift
public protocol StitchPattern: Sendable {
    mutating func setStartPosition(_ position: StagePoint)
    mutating func update(_ needle: NeedleUpdate) -> [StagePoint]
}
```

**RunningStitchPattern** — Emits a stitch every `length` stage units along the needle's path (port of Catroid `SimpleRunningStitch`).
```swift
let pattern = RunningStitchPattern(length: 10.0, start: StagePoint(x: 0, y: 0))
```

**ZigzagStitchPattern** — Alternate perpendicular stitches offset ±width/2, spaced `length` apart along the heading (port of Catroid `ZigZagRunningStitch`).
```swift
let pattern = ZigzagStitchPattern(length: 10.0, width: 5.0, start: StagePoint(x: 0, y: 0))
```

**TripleStitchPattern** — Reinforced stitches: forward, back, forward on every segment (port of Catroid `TripleRunningStitch`).
```swift
let pattern = TripleStitchPattern(length: 10.0, start: StagePoint(x: 0, y: 0))
```

**RunningStitch** — Lifecycle wrapper around a pattern (one per stitching actor). Supports pattern switching at runtime.
```swift
var stitcher = RunningStitch()
stitcher.activate(RunningStitchPattern(length: 10.0, start: start))
let points = stitcher.update(needleUpdate)
stitcher.setStartPosition(newAnchor)
```

**SewUp** — A five-point bar-tack lock (center, ahead, center, behind, center; port of Catroid `SewUpAction`). Returns points to feed the stream; pauses and resumes the running stitch.
```swift
let points = SewUp.perform(at: center, heading: 45.0, runningStitch: &stitcher)
```

See [ADR-014](../../docs/DECISIONS.md) for pattern arithmetic and tolerances.

### Pattern Management & Assembly

**EmbroideryPatternManager** — Records stitch commands across layers and actors, applies workspace dedup and layer-switch rules, then assembles all layers into a single stream.

```swift
var manager = EmbroideryPatternManager()

// Set actor color (if different, arms a DST color change on next stitch)
manager.setThreadColor(ThreadColor(red: 255, green: 0, blue: 0), for: actor0)
manager.setThreadColor(hexString: "#FF0000", for: actor0)  // Also supports hex

// Record commands (workspace position, layer, actor)
manager.addStitch(at: stagePoint, layer: 0, actor: actor0)

// Check for validity (more than one point)
if manager.hasValidPattern { /* safe to assemble */ }

// Assemble layers in ascending z-order with boundary color changes and jumps
let stream = manager.assembled()
```

Key semantics:
- **Workspace dedup**: identical consecutive commands from the same actor at the same position emit nothing.
- **Color changes**: setting a color arms a DST change on the actor's next surviving stitch; the first set of a color (before any emission) silently chooses the starting color.
- **Layer switches**: insert color-change records and re-emit boundary points per Catroid's clauses (ADR-012 and ADR-015).

See [ADR-015](../../docs/DECISIONS.md) for color emission semantics and clause-boundary rules.

### Stitch Stream & DST Export

**EmbroideryStream** — Ordered stitch collection shared by pattern generators and the DST writer. A value type with pending jump/color-change flags consumed per stitch.

```swift
var stream = EmbroideryStream()
stream.addJump()                           // Arm a jump flag
stream.addColorChange()                    // Arm a color change
stream.addStitch(at: point, color: .black) // Append, consuming flags

// Query the stream
let count = stream.count
let bounds = stream.boundingBox
let first = stream.firstStitchPosition
```

Long moves (exceeding ±121 embroidery units on either axis) are automatically interpolated into jump stitches per US-105. Dedup removes stitches at the last recorded stage position.

See [ADR-012](../../docs/DECISIONS.md) for interpolation, rounding, and byte-level semantics.

**DSTFile** — The complete, serialized Tajima DST file (512-byte header + 3-byte records + 0x00 0x00 0xF3 terminator).

```swift
let file = DSTFile(stream: stream, name: "MyDesign")

// Primary API: compare or persist directly
let bytes: Data = file.data

// Convenience: write atomically to a URL
try file.write(to: url)
```

The file name is sanitized to ASCII and truncated to 15 characters (Catroid's limit). Building a file does no I/O.

**DSTHeader** — The 512-byte DST file header, derived from stream metadata. Public for introspection; normally used only by `DSTFile`.

```swift
let header = DSTHeader(stream: stream, name: "Design")
let headerBytes = header.bytes
```

Fields include: design name (LA), stitch count (ST), color blocks (CO), extent magnitudes (+X, −X, +Y, −Y), net displacement from first to last stitch (AX, AY), and padding.

**DSTStitchRecord** — One 3-byte Tajima DST record: a relative movement up to ±121 units per axis, plus jump / color-change flags.

```swift
let record = DSTStitchRecord(dx: 50, dy: 100, isJump: false, isColorChange: false)
let bytes = record.bytes  // 3 bytes
```

The conversion table (balanced ternary bit patterns) is ported verbatim from Catroid per AGPL-3.0 provenance. Deltas outside ±121 are programmer errors and trigger a precondition failure.

## Design Constraints

### Synchronous, Sendable Value Types
The engine is deliberately **synchronous** — no async/await — so the app layer decides all async boundaries and actor placement. Every public type is a **Sendable value type** to ensure thread safety without runtime locks. This allows:
- Platform-independent testing with `swift test` (no simulator needed).
- The app layer to wrap the engine in an actor if needed for actor isolation.
- Deterministic behavior unaffected by scheduling.

### No Implicit I/O
The engine performs no I/O of its own — `DSTFile.data` is the primary export, and building a file touches no file system. The single exception is the explicit `DSTFile.write(to:)` convenience, a thin wrapper around `Data.write(to:options:)` provided for the app layer.

### No Dependencies
The package depends only on Foundation (for `Data`, `URL`). It is usable from any Swift platform (iOS 17+, macOS 14+).

### Strict Concurrency
Compiled with `swiftLanguageModes: [.v6]`, enforcing Swift 6 data-race safety at compile time.

## Running Tests

Tests use Swift Testing (`@Test`, `#expect`) and are run with `swift test` inside the package directory—no simulator required:

```bash
cd Packages/EmbroideryEngine
swift test
```

Tests are organized by concern (stitch domain, patterns, streams, DST encoding, round-trip byte verification against Catty fixtures) and run in parallel. Fixture files are kept byte-identical for golden testing.

## Provenance

EmbroideryEngine ports concepts from two AGPL-3.0 references:

- **Catroid** (`org.catrobat.catroid.embroidery`): The canonical Android embroidery implementation. Byte-level semantics (header fields, record bit layout, interpolation rules, rounding) are ported from this source.
- **Catty** (`src/Catty/Embroidery/`): The existing iOS implementation. Golden test fixtures (`stitch.dst`, `color_change.dst`) are byte-verified against files generated by Catty and validated in an embroidery viewer before trust.

The DST conversion table (`DSTStitchRecord.conversionTable`) is ported verbatim from Catroid's `DSTFileConstants.CONVERSION_TABLE` and is attributed in the source code.

## Architecture Decisions

The following Architecture Decision Records document the engine's design rationale and are the authority on byte-level semantics and edge cases:

- **[ADR-007](../../docs/DECISIONS.md#adr-007--stage-coordinate-space-and-physical-units-2026-07-06)** — Stage space definition (center origin, y-up, 500×500 pt).
- **[ADR-012](../../docs/DECISIONS.md#adr-012--dst-semantics-catroid-is-authoritative-known-catty-divergences-are-not-ported-2026-07-06)** — DST byte-level semantics, interpolation, rounding, and Catroid authority.
- **[ADR-013](../../docs/DECISIONS.md#adr-013--color-change-flag-placement-on-interpolated-moves-follows-catroid-the-color_change-golden-is-compared-through-a-documented-flag-transposition-2026-07-09)** — Color-change flag placement on long moves.
- **[ADR-014](../../docs/DECISIONS.md#adr-014--pattern-layer-arithmetic-is-double-sub-resolution-divergence-from-catroids-float-is-accepted-2026-07-13)** — Pattern arithmetic precision, degenerate input handling, and acceptable divergences.
- **[ADR-015](../../docs/DECISIONS.md#adr-015--set-thread-color-emission-semantics-silent-start-invalid-hex-no-op-clause-b-black-121-tie-off-2026-07-15)** — Thread-color emission rules, hex parsing, and boundary conditions.

When implementing features that touch stitch generation, DST encoding, or color changes, consult these ADRs before consulting the reference code.
