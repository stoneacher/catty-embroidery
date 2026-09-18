# EmbroideryEngine

A platform-independent Swift package architecture for embroidery-focused block programming: the program model, interpreter, stitch engine, and display-list primitives. Five library products work together to turn visual brick programs into byte-verified DST embroidery files and live stage previews.

## Products Overview

| Product | Role | Dependencies |
|---------|------|--------------|
| **EmbroideryEngine** | Stitch generation, pattern management, DST serialization. No I/O, no dependencies, strict concurrency. | — |
| **ProgramModel** | Pure value graph (Program/Scene/Object/Script/Brick/Formula). No engine types. | Foundation |
| **Interpreter** | Maps `Program` onto engine; executes bricks tick-by-tick; collects stitches. | ProgramModel, EmbroideryEngine |
| **Samples** | Bundled example programs for learning (octagon rosette, square coil). | ProgramModel |
| **StagePreview** | Display lists, zoom/pan math, run driver for live preview. Foundation-only. | Interpreter, EmbroideryEngine |

The dependency DAG is a straight line inward (ADR-016): `ProgramModel` is platform-independent and editor-safe; `Interpreter` is the only place model and engine meet; `Samples` depends on `ProgramModel` only; `StagePreview` depends on `Interpreter`.

EmbroideryEngine powers the embroidery functionality of the Catrobat iOS app, porting the byte-level semantics of Catroid's `org.catrobat.catroid.embroidery` module while maintaining compatibility with the Catty reference fixtures. It is deliberately synchronous, uses only Sendable value types, and runs Swift 6 strict concurrency—the app layer controls async boundaries and actor placement.

## Typical Workflow

The five products collaborate in this sequence:

1. **ProgramModel**: User creates a program via the app's block editor (scenes, objects, bricks, formulas).
2. **Interpreter**: The app runs the program headlessly, one tick at a time, converting program objects to engine actors and brick actions to stitch commands.
3. **StagePreview**: As the interpreter runs, stitch events feed a display list; the app renders it in real time and offers zoom/pan controls.
4. **EmbroideryEngine**: Stitches accumulate in the manager, which deduplicates, interpolates, and applies color changes.
5. **DST Export**: Once the run completes, the manager assembles the stream and builds a `DSTFile` for download or immediate sharing.

See [ADR-016](../../docs/DECISIONS.md) and [ADR-022](../../docs/DECISIONS.md) for the architectural rationale.

## Quick Start — EmbroideryEngine Directly

If you're building stitches directly (not from a program):

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
let file = try DSTFile(stream: stream, name: "MyDesign")

// Write to disk or compare bytes
let designURL = URL.temporaryDirectory.appending(path: "MyDesign.dst")
try file.write(to: designURL)
// Or inspect: let bytes = file.data
```

## Quick Start — Interpreter & StagePreview

If you're running a program with live preview:

```swift
import ProgramModel
import Interpreter
import StagePreview

// Build or load a program
var program = Program(name: "My Embroidery Design")
// ... add scenes, objects, scripts, bricks ...

// Create an interpreter
var interpreter = Interpreter(program: program, clock: InterpreterClock(tickDelta: 1.0 / 60.0))

// Run the interpreter with display updates
let driver = InterpreterDriver(pacing: DisplayRunPacing(), budget: .display)
let session = driver.start(interpreter)

// Consume updates in a task
Task {
    for await update in session.updates {
        // Update the UI with the preview state
        print("Stitches: \(update.batch.stitches.count), Needle: \(update.batch.needle)")
        
        // When terminal, export if complete
        if let termination = update.termination {
            if case .finished = termination.reason {
                let file = try DSTFile(stream: termination.exportModel.assembled(), name: "MyDesign")
                // Export file to disk or share...
            }
        }
    }
}
```

## Public API

### Geometry: Coordinate Spaces

**StagePoint** — A point in stage space (center origin, y-up, 500×500 pt virtual stage; 1 pt = 0.2 mm). Used throughout for pattern generation and needle updates.
```swift
let point = StagePoint(x: 10.5, y: 20.5)
```

**EmbroideryPoint** — A point in embroidery units (0.1 mm, the DST coordinate grid). Created by converting stage points with a factor of 2.0 and Java rounding per ADR-012. Read-only in normal use; appear in emitted stitches. The conversion is failable: a non-finite coordinate, or a finite one whose ×2 conversion leaves `Int` range, returns `nil` rather than trapping (ADR-020).
```swift
let embroideryPoint = EmbroideryPoint(converting: stagePoint) // EmbroideryPoint?
```

See [ADR-007](../../docs/DECISIONS.md) for the coordinate space design.

### Stitch Domain

**ThreadColor** — An RGB thread color, platform-independent stand-in for UIColor. Includes hex parsing (UTF-16 code-unit based, matching Java semantics) for the Set Thread Color brick.
```swift
let black = ThreadColor.black
let red = ThreadColor(red: 255, green: 0, blue: 0)
let parsed = ThreadColor(hexString: "#FF0000")  // Returns nil if malformed
```

**Stitch** — One stitch record — a needle penetration or a jump movement (`isJump`) — carrying position, color, and DST record flags.
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

// Set actor color: the first set (before any emission) silently picks the
// starting color; a later differing set arms a DST color change on the
// actor's next surviving stitch (ADR-015)
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

Long moves (exceeding ±121 embroidery units on either axis) are automatically interpolated into jump stitches per US-105. At an exact ±121-unit boundary the guard's difference rounding and the record's position rounding can disagree by one unit; the guard decides on both, so such a move splits rather than encoding an out-of-range delta (ADR-020 — Catroid shares the asymmetry and silently emits a corrupt record instead). Dedup removes stitches at the last recorded stage position. A stitch whose coordinates cannot be converted (non-finite, or past the ×2 conversion's `Int` range) or whose move is too long to split into a bounded number of jumps emits nothing and leaves the stream untouched, armed flags included.

ADR-020's last open item is closed by US-211: the header's field widths were the next reachable crash on this path, and they now throw (ADR-025). The 1,000,000-split cap stays where it is — once serialization throws, an oversize stitch count is a handled error rather than something interpolation has to prevent.

See [ADR-012](../../docs/DECISIONS.md) for interpolation, rounding, and byte-level semantics.

**DSTFile** — The complete, serialized Tajima DST file (512-byte header + 3-byte records + 0x00 0x00 0xF3 terminator).

```swift
let file = try DSTFile(stream: stream, name: "MyDesign")

// Primary API: compare or persist directly
let bytes: Data = file.data

// Convenience: write atomically to a URL
try file.write(to: url)
```

The file name is sanitized to ASCII and truncated to 15 characters (Catroid's limit). Building a file does no I/O, but it can fail: a design larger than a fixed-width header field can describe throws `DSTSerializationError.fieldOverflow(field:value:limit:)` (US-211, ADR-025), which names the field, the value and the limit so a caller can say *which* limit was hit.

**DSTHeader** — The 512-byte DST file header, derived from stream metadata. Public for introspection; normally used only by `DSTFile`. Being public makes it a serialization entry point in its own right, so it throws the same error as `DSTFile`.

```swift
let header = try DSTHeader(stream: stream, name: "Design")
let headerBytes = header.bytes
```

Fields include: design name (LA), stitch count (ST), color blocks (CO), extent magnitudes (+X, −X, +Y, −Y), net displacement from first to last stitch (AX, AY), and padding — enumerated as `DSTHeader.Field`, which carries each field's fixed `width` and `limit` in emission order. Three are reachable from ordinary input and throw rather than trap: the 4-wide extents, the 2-wide `CO` and the 6-wide `ST`. `LA`, `AX` and `AY` cannot overflow (ADR-025).

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

# ProgramModel

A pure value graph for embroidery programs, holding no engine types or dependencies. Models the Catrobat program structure (scene, object, script, brick) in a format suitable for editing, serialization, and interpretation.

## Public API

**Program** — Root of the program tree.

```swift
public struct Program: Sendable, Equatable, Codable {
    public var formatVersion: Int
    public var name: String
    public var scenes: [Scene]
    public var variables: [Variable]  // Project-scoped
}
```

**Scene** — A grouping of objects (actors).

```swift
public struct Scene: Sendable, Equatable, Codable {
    public var name: String
    public var objects: [Object]
}
```

**Object** — A sprite with a starting position, heading, and scripts.

```swift
public struct Object: Sendable, Equatable, Codable {
    public var name: String
    public var startX: Double          // Stage points
    public var startY: Double
    public var startHeading: Double    // Degrees, 0° = up per ADR-007
    public var zIndex: Int
    public var variables: [Variable]   // Object-scoped; shadows project variables
    public var scripts: [Script]
}
```

**Script** — A flat list of paired bricks.

```swift
public struct Script: Sendable, Equatable, Codable {
    public var header: ScriptHeader
    public var bricks: [Brick]
    
    public func validate() throws  // Throws ScriptValidationError
    public func matchingEnd(ofBrickAt index: Int) -> Int?
    public func range(ofPairAt index: Int) -> ClosedRange<Int>?
    public mutating func movePair(from source: Int, to destination: Int) throws
}
```

Scripts are flat, not nested — loops are represented as `.repeatLoop` / `.forever` opener / `.loopEnd` pairs in the same list (ADR-008). The script validates its brick structure via `validate()`, which throws `ScriptValidationError` if control bricks do not balance. Pair operations (moving a loop as one unit) throw `ScriptMoveError` if the indices are invalid or the pair is unbalanced.

**ScriptHeader** — What triggers a script.

```swift
public enum ScriptHeader: Sendable, Equatable, Codable {
    case whenStarted  // M2 ships only this; M4+ adds tap, message, etc.
}
```

**Scope & VariableScope** — Variable-name resolution during formula evaluation.

```swift
public protocol Scope {
    func value(of variableName: String) -> Double  // Unknown → 0
}

public struct VariableScope: Scope, Sendable {
    public init(objectVariables: [Variable] = [], projectVariables: [Variable] = [])
}
```

`VariableScope` implements two-level resolution: object scope is consulted first, then project scope. Within each collection, the first match by name wins. Unknown names yield 0.

**Brick** — An instruction (motion, control, data, or embroidery).

```swift
public indirect enum Brick: Sendable, Equatable, Codable {
    // Motion
    case moveNSteps(Formula)
    case turnLeft(Formula)
    case turnRight(Formula)
    case pointInDirection(Formula)
    case placeAt(x: Formula, y: Formula)
    case setX(Formula), setY(Formula)
    case changeXBy(Formula), changeYBy(Formula)
    
    // Control
    case repeatLoop(times: Formula)
    case forever
    case loopEnd
    case wait(seconds: Formula)
    
    // Data
    case setVariable(name: String, to: Formula)
    case changeVariableBy(name: String, value: Formula)
    
    // Embroidery
    case stitch
    case setThreadColor(hex: String)
    case runningStitch(length: Formula)
    case zigZagStitch(length: Formula, width: Formula)
    case tripleStitch(length: Formula)
    case sewUp
    case stopRunningStitch
    case writeEmbroideryToFile(name: String)
}

public enum BrickDefaults {
    public static let moveSteps: Double = 10
    public static let turnDegrees: Double = 15
    public static let placeAtX: Double = 100
    public static let placeAtY: Double = 200
    public static let stitchLength: Double = 10
    public static let zigZagLength: Double = 2
    public static let zigZagWidth: Double = 10
    public static let threadColorHex: String = "#ff0000"
    public static let waitSeconds: Double = 1.0
}
```

`BrickDefaults` provides Catroid-compatible default values that the M4 editor seeds new bricks with.

**Formula** — Expressions composed of numbers, variables, and binary operators.

```swift
public indirect enum Formula: Sendable, Equatable, Codable {
    case number(Double)
    case variable(String)
    case binary(BinaryOperator, Formula, Formula)
    
    public func evaluate(in scope: Scope) throws -> Double
}

public enum BinaryOperator: Sendable, Equatable, CaseIterable, Codable {
    case plus, minus, mult, divide, mod, pow
}

public enum FormulaError: Error, Equatable, Sendable {
    case notANumber
}
```

Formulas evaluate to `Double` via `evaluate(in:)`, which takes a `Scope` for variable resolution. Throws `FormulaError.notANumber` on division by zero, modulo by zero, non-finite intermediate values, or non-integer truncation. ADR-017 covers arithmetic precision (native `Double`, not decimal128), fallback semantics, and caveats about bit parity with Android.

**Variable** — A named numeric value.

```swift
public struct Variable: Sendable, Equatable, Codable {
    public var name: String
    public var value: Double
}
```

Variables are scoped: project-scoped variables live on `Program`, object-scoped ones on `Object`. Resolution is first-declaration-wins (ADR-018).

## Design Constraints

- **No engine types**: `ProgramModel` depends only on Foundation. It is usable by M4's editor and M5's persistence without linking the embroidery engine.
- **Value semantics**: Everything is `Sendable` and `Codable` to support snapshot/undo and JSON round-tripping (ADR-003, ADR-006).
- **Flat scripts**: Nesting is a rendering concern; the model is Catrobat-compatible (ADR-008).

---

# Interpreter

Maps a `Program` onto the embroidery engine, one tick at a time. Converts program objects and variables to engine actors and state, executes brick instructions, and collects generated stitches into the manager.

## Public API

**Interpreter** — A pure value-type executor.

```swift
public struct Interpreter: Sendable {
    public init(program: Program, clock: InterpreterClock)
    
    // Execute one tick (one round-robin pass over all threads)
    public mutating func step() -> StepOutcome
    
    // Run up to maxTicks ticks
    public mutating func run(maxTicks: Int) -> [InterpreterEvent]
    
    // Is execution finished?
    public var isFinished: Bool
    
    // Access to the assembled stitch stream
    public var manager: EmbroideryPatternManager
}
```

An `Interpreter` is a pure value type — snapshot it to save state, copy it to replay.

**InterpreterClock** — A logical clock driving frame-rate-independent timing (ADR-018).

```swift
public struct InterpreterClock: Sendable, Equatable {
    public init(tickDelta: Double)  // Seconds per tick; typically 1/60
    public let tickDelta: Double
}
```

**StepOutcome** — The result of one `step()` call.

```swift
public enum StepOutcome: Equatable, Sendable {
    case ticked([InterpreterEvent])  // This tick produced these events
    case finished                      // No more runnable threads
}
```

**InterpreterEvent** — Emitted during execution.

```swift
public enum InterpreterEvent: Equatable, Sendable {
    case needleMoved(position: StagePoint, heading: Double)
    case stitch(position: StagePoint, color: ThreadColor, isJump: Bool)
    case colorArmed
    case waited(duration: Double)
    case finalizeRequested(name: String)
}
```

**VirtualNeedle** — The per-object needle state (position and heading).

```swift
public struct VirtualNeedle: Hashable, Sendable {
    public var position: StagePoint
    public var heading: Double  // Degrees
}
```

## Tick Semantics

- **One tick = one round-robin pass** over all runnable threads (one per `whenStarted` script), in creation order.
- **One action per thread per tick**: motion, data, `wait`, or embroidery bricks cost exactly one tick; loop bookkeeping is zero-tick (ADR-018).
- **`wait` uses accumulating logical time**, not wall-clock, so frame rate does not affect duration.
- **Variable resolution** is first-declaration-wins; object variables shadow project variables.
- **Formula errors are non-fatal**: motion falls back to zero movement per axis, data operations fall back to zero, loops fall back to zero iterations.

See [ADR-018](../../docs/DECISIONS.md) for the complete tick accounting and loop nesting semantics.

## Design Constraints

- **No reference types**: All state lives in the value; thread-local state is not shared.
- **No globals**: Deterministic replay by copying.
- **Synchronous**: No `async/await` — the app layer controls async boundaries.

---

# Samples

Bundled sample embroidery programs for learning and demonstration.

## Public API

**SampleLibrary** — Access to bundled samples.

```swift
public enum SampleLibrary {
    /// All shipped samples in presentation order
    public static let all: [SampleProgram]
    
    /// Look up a sample by ID
    public static subscript(id: SampleID) -> SampleProgram
}
```

**SampleProgram** — One sample.

```swift
public struct SampleProgram: Sendable, Hashable, Identifiable {
    public let id: SampleID
    public let program: Program
}
```

**SampleID** — Enumerated sample identifiers.

```swift
public enum SampleID: String, Sendable, Hashable, CaseIterable, Codable {
    case octagonRosette
    case squareCoil
}
```

## Bundled Samples

Each sample is built by a Swift function (e.g. `makeOctagonRosetteProgram()`) and serialized to JSON for round-trip testing. The JSON resources live in `Resources/` (ADR-003).

- **Octagon Rosette** — Demonstrates nested loops, variables, and zigzag stitching. Transcribed brick-for-brick from Catroid's default example project with verified libm-dependent behaviour (ADR-019).
- **Square Coil** — A spiral of increasing sides, demonstrating motion from variables and thread-color changes. Carefully parameterized off the DST threshold boundaries (ADR-020).

See `Sources/Samples/Resources/PROVENANCE.md` for detailed transcription notes, measured figures, and cross-platform comparison caveats.

## Design Constraints

- **Model-only**: Samples depend on `ProgramModel` only, not the engine or interpreter (ADR-022).
- **Deterministic**: Both samples produce identical output across runs.
- **Threshold-aware**: Parameters are chosen to exercise (or avoid) boundary conditions relevant to the interpreter and engine.

---

# StagePreview

Display lists, stage geometry, zoom/pan transforms, and an interpreter driver for live preview. Foundation-only (no SwiftUI or CoreGraphics) so the math is unit-testable and the app can use it for rendering, bounding, and accessibility.

## Public API

### Stage Geometry & Bounds

**StageGeometry** — Constants and utilities for the virtual stage (ADR-007, ADR-020).

```swift
public enum StageGeometry {
    public static let sideInPoints: Double = 500
    public static let halfExtentInPoints: Double = 250
    public static let millimetresPerPoint: Double = 0.2
    public static let box: StageBox  // The hoop outline
    
    /// Fit target: hoop ∪ stitched content (not clipped)
    public static func fitTarget(including content: StageBox?) -> StageBox
}
```

**StageBox** — An axis-aligned bounding box.

```swift
public struct StageBox: Hashable, Sendable {
    public var minX, maxX, minY, maxY: Double
}
```

### Rendering & Interaction

**PreviewRunState** — Display state during a preview run.

```swift
public struct PreviewRunState: Equatable, Sendable {
    public var runState: RunState
    public var manipulation: StageManipulation
    public var summary: StageSummary
    public var exportEligibility: ExportEligibility
}
```

**RunState** — Execution progress.

```swift
public enum RunState: Hashable, Sendable {
    case paused
    case running(RunPhase)
    case complete(RunCompletion)
}
```

**RunCompletion** — Why execution ended.

```swift
public enum RunCompletion: Hashable, Sendable {
    case finished           // Program ran to completion
    case stitchLimitReached // Hit RunBudget.maxStitches
    case stoppedByUser      // User called stop()
}
```

**ExportEligibility** — Whether a finished run can be exported.

```swift
public enum ExportEligibility: Hashable, Sendable {
    case notRun             // No run has completed yet
    case ready(exportModel: EmbroideryPatternManager)  // Terminal update produced this
}
```

Export eligibility is written only from the terminal update (ADR-027), so mid-run the status is always `.notRun` even though stitches are visible.

**StageManipulation** — Zoom and pan state.

```swift
public struct StageManipulation: Equatable, Sendable {
    public var zoom: Double      // Fit-aware with a floor per ADR-028
    public var panX, panY: Double
}
```

**StageInteraction** — Gesture reduction (pinch/pan) into discrete zoom/pan deltas (ADR-028).

```swift
public struct StageInteraction: Equatable, Sendable {
    public mutating func applyMagnification(_ scale: Double)
    public mutating func applyTranslation(_ delta: CGSize)
    public var zoom: StageZoomAdjustment
    public var pan: StagePanDirection
}
```

**StageSummary** — Accessibility summary of the stage state (ADR-028).

```swift
public struct StageSummary: Equatable, Sendable {
    public var designName: String
    public var stageWidth: Double   // Millimetres
    public var stageHeight: Double
    public var totalStitches: Int
    public var totalColors: Int
}
```

**PreviewStitch** — One stitch in the display list.

```swift
public struct PreviewStitch: Hashable, Sendable {
    public var position: StagePoint
    public var color: ThreadColor
}
```

**StitchDisplayList** — Stitches partitioned by color for efficient rendering.

```swift
public struct StitchDisplayList: Equatable, Sendable {
    public struct ColorRun: Hashable, Sendable {
        public let color: ThreadColor
        public let range: Range<Int>  // Into stitches array
    }
    public var stitches: [PreviewStitch]
    public var colorRuns: [ColorRun]  // Gapless partition of stitches.indices
}
```

Color runs enable the app to draw one `Path` per color without scanning the stitch array (ADR-024).

**PreviewNeedle** — Needle position and heading for rendering.

```swift
public struct PreviewNeedle: Hashable, Sendable {
    public var position: StagePoint
    public var heading: Double
}
```

**RunBatch** — Stitches and needle state produced in one frame.

```swift
public struct RunBatch: Hashable, Sendable {
    public var stitches: [PreviewStitch]
    public var needle: PreviewNeedle?
}
```

**RunPhase** — Tick progress within the current frame.

```swift
public struct RunPhase: Equatable, Sendable {
    public var ticksThisFrame: Int
    public var ticksTotal: Int
    public var stitchesThisFrame: Int
    public var stitchesTotal: Int
}
```

**NeedleGlyph** — Needle rendering options.

```swift
public enum NeedleGlyph {
    public static let width: Double
    public static let length: Double
    // Produces CGPath for rendering
}
```

### Run Control

**InterpreterDriver** — Executes an `Interpreter` off the main actor and yields frame updates (ADR-027).

```swift
public struct InterpreterDriver: Sendable {
    public let budget: RunBudget
    
    public init(pacing: some RunPacing, budget: RunBudget = .display)
    
    /// Start the run, returning a session that can be stopped
    public func start(_ interpreter: Interpreter) -> RunSession
}
```

The driver runs the interpreter in a detached task, yielding one frame per update. Cancellation is re-checked both before and after each frame to catch user stops promptly (ADR-027).

**RunPacing** — Frame-rate control protocol.

```swift
public protocol RunPacing: Sendable {
    /// Suspend until the next frame, or until the task is cancelled.
    /// Must respect cancellation to allow stop() to work (ADR-027).
    mutating func waitForNextFrame() async throws
}

public struct DisplayRunPacing: RunPacing {
    // Targets ~60 fps
}

public struct ImmediateRunPacing: RunPacing {
    // No delay; for tests and fast iteration
}
```

Custom pacing can implement frame-rate throttling, slow-motion playback, or other effects. **The cancellation half is critical**: a pacing that ignores cancellation will leave the run producer parked permanently, preventing clean shutdown (ADR-027).

**RunSession** — A cancellable run.

```swift
public struct RunSession: Sendable {
    public let updates: AsyncStream<RunUpdate>
    
    public func stop()  // Cancels the producer
}
```

Consume updates via `for await update in session.updates`. Call `stop()` to cancel the run; it produces a final terminal update.

**RunUpdate** — One frame of progress.

```swift
public struct RunUpdate: Equatable, Sendable {
    public var state: PreviewRunState
    public var batch: RunBatch
    public var termination: RunTermination?
}
```

**RunTermination** — End-of-run summary (ADR-027).

```swift
public struct RunTermination: Equatable, Sendable {
    public var reason: RunCompletion
    public var exportModel: EmbroideryPatternManager
}
```

Terminal updates carry the final `exportModel` so a caller can export the design immediately after stop or completion.

**RunBudget** — Tick and stitch allocation per frame (ADR-027).

```swift
public struct RunBudget: Hashable, Sendable {
    public let maxTicks: Int
    public let maxStitches: Int
    
    public static let display: RunBudget    // ~60 fps target
    public static let immediate: RunBudget  // Fast iteration for tests
}
```

## Coordinate Transforms

**StageRenderTransform** — Converts between stage space and screen coordinates (ADR-007, ADR-024).

```swift
public enum StageRenderTransform: Hashable, Sendable {
    /// Apply to a stage point to get screen coordinates
    public static func apply(_ transform: CGAffineTransform, to point: StagePoint) -> CGPoint
}
```

The transform is computed from the `StageManipulation` zoom/pan and the display bounds. Zoom is fit-aware with a floor per ADR-028.

## Design Constraints

- **Foundation-only**: No SwiftUI, no CoreGraphics — the math is testable with `swift test`.
- **Sendable value types**: All display state is `Sendable` for thread-safe access from the interpreter driver's background task.
- **Deterministic**: Display is computed from the run state; replays produce identical geometry.

---

# Architecture Decisions

The following Architecture Decision Records document the design rationale and are the authority on byte-level semantics, coordinate spaces, tick accounting, and edge cases:

- **[ADR-003](../../docs/DECISIONS.md#adr-003--project-format-native-json-first-catrobat-later-2026-07-06)** — JSON project format and version field (ProgramModel serialization).
- **[ADR-007](../../docs/DECISIONS.md#adr-007--stage-coordinate-space-and-physical-units-2026-07-06)** — Stage space (center origin, y-up, 500×500 pt, 1 pt = 0.2 mm).
- **[ADR-008](../../docs/DECISIONS.md#adr-008--script-representation-flat-brick-list-with-paired-control-bricks-2026-07-06)** — Flat paired-brick scripts (ProgramModel structure).
- **[ADR-012](../../docs/DECISIONS.md#adr-012--dst-semantics-catroid-is-authoritative-known-catty-divergences-are-not-ported-2026-07-06)** — DST byte-level semantics (EmbroideryEngine).
- **[ADR-013](../../docs/DECISIONS.md#adr-013--color-change-flag-placement-on-interpolated-moves-follows-catroid-the-color_change-golden-is-compared-through-a-documented-flag-transposition-2026-07-09)** — Color-change flag placement (EmbroideryEngine).
- **[ADR-014](../../docs/DECISIONS.md#adr-014--pattern-layer-arithmetic-is-double-sub-resolution-divergence-from-catroids-float-is-accepted-2026-07-13)** — Pattern arithmetic precision (EmbroideryEngine).
- **[ADR-015](../../docs/DECISIONS.md#adr-015--set-thread-color-emission-semantics-silent-start-invalid-hex-no-op-clause-b-black-121-tie-off-2026-07-15)** — Thread-color emission (EmbroideryEngine).
- **[ADR-016](../../docs/DECISIONS.md#adr-016--m2-target-layout-programmodel-and-interpreter-as-two-sibling-targets-2026-07-16)** — Product separation (ProgramModel / Interpreter).
- **[ADR-017](../../docs/DECISIONS.md#adr-017--formula-arithmetic-is-native-double-decimal128-divergence-and-non-finite-literal-semantics-pinned-2026-07-19)** — Formula arithmetic (ProgramModel).
- **[ADR-018](../../docs/DECISIONS.md#adr-018--interpreter-tick--clock-semantics-one-action-per-tick-round-robin-zero-tick-loop-bookkeeping-accumulating-logical-clock-2026-07-23)** — Tick accounting and wait semantics (Interpreter).
- **[ADR-019](../../docs/DECISIONS.md#adr-019--structure-determining-threshold-crossings-are-a-distinct-class-from-coordinate-tolerance-a-golden-sitting-on-one-must-say-so-and-guard-it-2026-07-27)** — Libm-dependent golden tests (Samples, EmbroideryEngine).
- **[ADR-020](../../docs/DECISIONS.md#adr-020--the-engines-coordinate-boundary-interpolation-decides-on-the-encodable-delta-unconvertible-coordinates-and-unsplittable-moves-are-guarded-no-ops-2026-07-31)** — Coordinate bounds and interpolation guards (EmbroideryEngine).
- **[ADR-022](../../docs/DECISIONS.md#adr-022)** — App-support products: Samples and StagePreview.
- **[ADR-024](../../docs/DECISIONS.md#adr-024)** — Stage renderer protocol.
- **[ADR-025](../../docs/DECISIONS.md#adr-025)** — DST serialization field widths as throwing errors.
- **[ADR-027](../../docs/DECISIONS.md#adr-027)** — Run lifecycle and interpreter driver.
- **[ADR-028](../../docs/DECISIONS.md#adr-028)** — Zoom/pan and stage VoiceOver summary.

When implementing features across products, consult the relevant ADRs before modifying code.
