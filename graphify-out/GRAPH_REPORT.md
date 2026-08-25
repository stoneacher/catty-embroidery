# Graph Report - catty-embroidery  (2026-08-25)

## Corpus Check
- 251 files · ~401,194 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2405 nodes · 6717 edges · 125 communities (101 shown, 24 thin omitted)
- Extraction: 71% EXTRACTED · 29% INFERRED · 0% AMBIGUOUS · INFERRED: 1928 edges (avg confidence: 0.8)
- Token cost: 854,446 input · 0 output

## Community Hubs (Navigation)
- Stitch Patterns & Sew-Up
- Pattern Manager & Thread Layers
- DST Golden Byte Tests
- Stream Interpolation & Jumps
- Formula Tree Story Specs
- Repo Process & Provenance Docs
- Stepper Loop & Scheduling
- Preview Run State & Phases
- Stage Interaction Transitions
- Roadmap & Decision Records
- Stage Transform Core
- Interpreter Target Isolation
- Coordinate Conversion Geometry
- Stage Transform Test Suite
- Running Stitch & Traversal
- Stitch Draw Plan Windowing
- Stitch Display List & Summary
- CoreGraphics Canvas Renderer
- Run Lifecycle Story Specs
- Stage Bounds & Fit Targets
- Stitch Pattern Story Specs
- Bundled Sample Story Specs
- Golden Program Consumption
- Run View Model
- Formula Evaluation Tests
- Script & Paired Control
- Golden Program Oracles
- Interpreter Driver & Budgets
- App Model & Renderer Wiring
- Mid-Run Screenshot Evidence
- DST Stitch Record Codec
- Brick Enum & Defaults
- Sample Picker & Selection
- Stepper Embroidery Bricks
- Sample Program Library
- DST Header Writer
- Script Move Semantics
- Stage View & Transport Row
- Stage Gesture Recognition
- Sample Threshold Screening
- Stage Zoom Bounds
- Sample Row Accessibility
- Thread Color & Segment Style
- Triple Stitch Pattern
- Run Pacing & Draining
- Cross-Target Test Glue
- Run Batch Assembly
- DST Fixture Reader
- Needle Glyph Rendering
- Script Compiler & Instructions
- Variable Scope Model
- DST Header Field Reader
- Stage Canvas Animation
- Stage View Wiring
- Stage Accessibility Strings
- Formula Evaluation Runtime
- Interpreter Step Loop
- App String Catalog Tests
- Run State & Completion
- Stage Content State
- DST Field Width Story Spec
- iPad Sidebar Screenshot
- Interpreter Events & Harness
- Virtual Needle Apply
- Stitch Draw Metrics
- Display vs Export Divergence
- Run Control Appearance
- Paired Control Story Spec
- Dynamic Type Screenshot
- Dark Mode Screenshot (US-306)
- Canvas Renderer Story Spec
- Stage Render Transform Bake
- Golden Square Program
- Virtual Needle Brick Tests
- Completed Run Screenshot
- Mid-Run Screenshot (US-307)
- Panned Stage Screenshot
- Stage Fit Target Isolation
- App Root & Window Scene
- Object & Script Header
- Post-Run Screenshot
- Mid-Drag Screenshot
- Preview Core Story Spec
- Stage Box & Extent
- Stitch Segment Classification
- Virtual Needle Finiteness
- Run Clock & Display Pacing
- Dark Mode Screenshot (US-307)
- Fit-to-Content Screenshot
- Stepper Core Story Spec
- Byte Diff Reporting
- DST Round-Trip Decode
- Sample Budget Guards
- Preview Test Fixtures
- Binary Operator Enum
- Gated Run Pacing
- Compensated Magnitude Math
- Stage Motion & Fit Animation
- Run Session Async Stream
- Stepper Stitch Colors
- Stepper Variable Semantics
- Square Coil Sample Checks
- Sample Identity & Resources
- Deterministic Traversal RNG
- Sample Row Accessibility Label
- DST Header Field Types
- Preview Core Deviations
- DST Export Story Spec
- Brick Codable Round-Trip
- Sample Linkage Tests
- Step Outcome Enum
- Variable Store Scope
- Double Equality Helper
- Square Coil Program Builder
- Stage Chrome Colors
- App Rehabilitation Story Spec
- Brick Default Values
- Design Name Sanitisation
- Swift Package Manifest
- Stretch Epic
- Dark Mode Render Rule
- Run Reset Semantics
- VoiceOver Abbreviation Rule
- Headless Throughput Guard
- Sixty FPS Definition

## God Nodes (most connected - your core abstractions)
1. `StagePoint` - 310 edges
2. `EmbroideryStream` - 110 edges
3. `EmbroideryEngine` - 99 edges
4. `EmbroideryPoint` - 94 edges
5. `Testing` - 88 edges
6. `Interpreter` - 85 edges
7. `Script` - 81 edges
8. `Program` - 78 edges
9. `StageTransform` - 67 edges
10. `StitchDisplayList` - 61 edges

## Surprising Connections (you probably didn't know these)
- `DSTHeader.appendField precondition (the chokepoint)` --semantically_similar_to--> `ADR-020 — engine coordinate boundary and ±121 guard`  [INFERRED] [semantically similar]
  docs/user-stories/milestone-3/US-211-dst-field-width-chokepoint.md → Packages/EmbroideryEngine/README.md
- `US-101 — Project scaffold, SPM package and CI` --semantically_similar_to--> `ADR-023 — what runs where: local gate vs CI`  [INFERRED] [semantically similar]
  docs/user-stories/milestone-1/US-101-project-scaffold-and-ci.md → CLAUDE.md
- `VoiceOver Run-State Summary` --implements--> `US-307 — Pinch-zoom / pan and the stage VoiceOver summary`  [AMBIGUOUS]
  docs/screenshots/us-307/midrun.png → docs/user-stories/milestone-3/README.md
- `Zoomed-In Stage State` --conceptually_related_to--> `US-307 — Pinch-zoom / pan and the stage VoiceOver summary`  [AMBIGUOUS]
  docs/screenshots/us-307/panned.png → docs/user-stories/milestone-3/README.md
- `Shared hook scripts (scripts/hooks, scripts/review)` --semantically_similar_to--> `ADR-023 — what runs where: local gate vs CI`  [INFERRED] [semantically similar]
  docs/dual-driver-workflow-plan.md → CLAUDE.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Required status checks keeping red out of main** — _github_workflows_ci_engine_tests, _github_workflows_ci_app_build_and_test, _github_workflows_ci_lint, claude_never_commit_red, docs_decisions_adr_023 [EXTRACTED 1.00]
- **Two-layer cross-vendor review loop** — _claude_commands_codex_review_codex_review, _claude_commands_codex_review_stop_condition, _claude_commands_codex_review_verification_round, _claude_commands_codex_review_adr_arbiter_triage, agents_two_layer_review, _claude_commands_finish_finish [EXTRACTED 1.00]
- **Golden fixture trust chain (external verification before trust)** — packages_embroideryengine_tests_embroideryenginetests_resources_embroideryreference_provenance_stitch_dst, packages_embroideryengine_tests_embroideryenginetests_resources_embroideryreference_provenance_color_change_dst, packages_embroideryengine_tests_interpretertests_resources_goldenprograms_provenance_square_dst, packages_embroideryengine_sources_samples_resources_provenance_octagonrosette, packages_embroideryengine_sources_samples_resources_provenance_squarecoil, packages_embroideryengine_tests_interpretertests_resources_goldenprograms_provenance_self_golden_trust_rule, docs_decisions_adr_012 [EXTRACTED 1.00]
- **M1 DST export pipeline (model → records → header → interpolation → file)** — docs_user_stories_milestone_1_us_102_stitch_model_and_stream_us_102, docs_user_stories_milestone_1_us_103_dst_record_encoder_us_103, docs_user_stories_milestone_1_us_104_dst_header_writer_us_104, docs_user_stories_milestone_1_us_105_interpolation_and_jumps_us_105, docs_user_stories_milestone_1_us_106_dst_file_generator_golden_us_106 [EXTRACTED 1.00]
- **The Double-arithmetic divergence policy (tolerance, thresholds, coordinate bounds)** — docs_decisions_adr_014, docs_decisions_adr_017, docs_decisions_adr_019, docs_decisions_adr_020, docs_decisions_javaround [INFERRED 0.85]
- **M3 preview stack (data path, target layout, renderer, run lifecycle, interaction)** — docs_decisions_adr_021, docs_decisions_adr_022, docs_decisions_adr_024, docs_decisions_adr_027, docs_decisions_adr_028, docs_roadmap_m3_walking_skeleton_app [EXTRACTED 1.00]
- **Golden program verification chain (program → stream → bytes)** — docs_user_stories_milestone_2_us_207_golden_program_square_polygonprogram, docs_user_stories_milestone_2_us_207_golden_program_square_goldenprogramoracle, docs_user_stories_milestone_2_us_207_golden_program_square_goldensquareliterals, docs_user_stories_milestone_2_us_208_golden_program_star_goldenstaroracle, docs_user_stories_milestone_2_us_209_pattern_to_bytes_differential_square_dst [EXTRACTED 1.00]
- **Deterministic tick execution model** — docs_user_stories_milestone_2_us_205_stepper_core_interpreterclock, docs_user_stories_milestone_2_us_205_stepper_core_round_robin_one_brick_per_tick, docs_user_stories_milestone_2_us_205_stepper_core_compiled_instruction_array, docs_user_stories_milestone_2_us_205_stepper_core_batch_equivalence, docs_user_stories_milestone_2_readme_deterministic_time_catroid_faithful_ticks [EXTRACTED 1.00]
- **Engine coordinate boundary chokepoint (five traps)** — docs_user_stories_milestone_2_us_210_coordinate_overflow_chokepoint_trigger_on_either, docs_user_stories_milestone_2_us_210_coordinate_overflow_chokepoint_embroiderypoint_converting, docs_user_stories_milestone_2_us_210_coordinate_overflow_chokepoint_split_cap, docs_user_stories_milestone_2_us_210_coordinate_overflow_chokepoint_lattice_step_guard, docs_user_stories_milestone_2_us_210_coordinate_overflow_chokepoint_canappend [EXTRACTED 1.00]
- **M3 walking skeleton: sample → preview → app shell → picker** — docs_user_stories_milestone_3_us_301_bundled_sample_programs_us_301, docs_user_stories_milestone_3_us_302_preview_core_us_302, docs_user_stories_milestone_3_us_303_app_target_rehabilitation_us_303, docs_user_stories_milestone_3_us_304_sample_picker_us_304, docs_user_stories_milestone_3_readme_milestone_3 [EXTRACTED 1.00]
- **StagePreview's Foundation-only core meets the transform-math exit criterion** — docs_user_stories_milestone_3_us_302_preview_core_stagepreview, docs_user_stories_milestone_3_us_302_preview_core_stitchdisplaylist, docs_user_stories_milestone_3_us_302_preview_core_stagetransform, docs_user_stories_milestone_3_us_302_preview_core_stagegeometry, docs_user_stories_milestone_3_readme_milestone_exit_criteria [EXTRACTED 1.00]
- **Field-width chokepoint: asymmetry + throwing init + typed error** — docs_user_stories_milestone_3_us_211_dst_field_width_chokepoint_dstheader_appendfield, docs_user_stories_milestone_3_us_211_dst_field_width_chokepoint_reachability_asymmetry, docs_user_stories_milestone_3_us_211_dst_field_width_chokepoint_throwing_init_decision, docs_user_stories_milestone_3_us_211_dst_field_width_chokepoint_dstserializationerror, docs_decisions_adr_025 [EXTRACTED 1.00]
- **M3 run data path: driver → batches → observable state → renderer** — docs_user_stories_milestone_3_us_306_run_lifecycle_interpreterdriver, docs_user_stories_milestone_3_us_306_run_lifecycle_runbatch, docs_user_stories_milestone_3_us_306_run_lifecycle_previewrunstate, docs_user_stories_milestone_3_us_305_canvas_stitch_renderer_stitchdrawplan, docs_user_stories_milestone_3_us_305_canvas_stitch_renderer_canvasstitchrenderer [INFERRED 0.85]
- **Settled-raster strategy across renderer, run and gestures** — docs_user_stories_milestone_3_us_305_canvas_stitch_renderer_settled_live_split, docs_user_stories_milestone_3_us_305_canvas_stitch_renderer_bridging_segment, docs_user_stories_milestone_3_us_306_run_lifecycle_previewrunstate, docs_user_stories_milestone_3_us_307_zoom_pan_and_accessibility_mid_gesture_raster_policy, docs_user_stories_milestone_3_us_309_fifty_thousand_stitch_exit_criterion_per_frame_independence [INFERRED 0.85]
- **Export path: terminal export model, gating and DST file writing** — docs_user_stories_milestone_3_us_306_run_lifecycle_terminal_batch_export_model, docs_user_stories_milestone_3_us_308_design_name_and_dst_export_export_gate, docs_user_stories_milestone_3_us_308_design_name_and_dst_export_dstfilewriting, docs_user_stories_milestone_3_us_308_design_name_and_dst_export_dstdesign_transferable, docs_user_stories_milestone_3_us_308_design_name_and_dst_export_exportstate [INFERRED 0.85]

## Communities (125 total, 24 thin omitted)

### Community 0 - "Stitch Patterns & Sew-Up"
Cohesion: 0.07
Nodes (33): GoldenRow, RunningStitch, SewUp, Double, Double, ZigzagStitchPattern, RunningStitchTests, Double (+25 more)

### Community 1 - "Pattern Manager & Thread Layers"
Cohesion: 0.11
Nodes (17): ActorID, ColorState, EmbroideryPatternManager, .hasEmittedOps, .hasValidPattern, EmittedPoint, LastCommand, LayerWorkspace (+9 more)

### Community 2 - "DST Golden Byte Tests"
Cohesion: 0.06
Nodes (24): DSTFile, Data, UInt8, URL, DSTFileTests, Data, Double, Int (+16 more)

### Community 3 - "Stream Interpolation & Jumps"
Cohesion: 0.09
Nodes (10): EmbroideryStream, .count, .firstStitchPosition, .lastStitchPosition, Int, CoordinateChokepointTests, expectEveryDeltaEncodable(), EmbroideryStreamTests (+2 more)

### Community 4 - "Formula Tree Story Specs"
Cohesion: 0.05
Nodes (56): ADR-001 — App scope: embroidery-focused block app, ADR-015 — set-thread-color emission semantics, Milestone 2 — Interpreter MVP, Bricks are a closed indirect enum, Interpreter only calls the engine, never re-implements stream semantics, M2 exit criterion: incrementally consumable deterministic interpreter, Two sibling targets: ProgramModel and Interpreter, US-201 Program model value types and sibling targets (+48 more)

### Community 5 - "Repo Process & Provenance Docs"
Cohesion: 0.06
Nodes (55): ADR-as-arbiter finding triage, /codex-review — cross-vendor Codex review, codex exec stdin hang trap, Severity-trend stop condition, Codex verification round, /finish — session close-out checklist, Manual Ink/Stitch verification callout, Story close-out must be proved by grep (+47 more)

### Community 6 - "Stepper Loop & Scheduling"
Cohesion: 0.12
Nodes (14): Interpreter, NeedleUpdate, Double, InterpreterClock, Double, Program, Int, Scene (+6 more)

### Community 7 - "Preview Run State & Phases"
Cohesion: 0.14
Nodes (11): PreviewRunState, .state, .summary, .summaryRevision, .visibleNeedle, Int, RunBatch, RunTermination (+3 more)

### Community 8 - "Stage Interaction Transitions"
Cohesion: 0.15
Nodes (13): Equatable, Phase, idle, settling, StageInteraction, .isFollowingFit, .isSettling, .settlingProgress (+5 more)

### Community 9 - "Roadmap & Decision Records"
Cohesion: 0.09
Nodes (48): ADR-007 — stage coordinate space and physical units, ADR-009 — Stage rendering: SwiftUI Canvas with batched paths, ADR-010 — Device family: universal, iPhone-first, ADR-016 — M2 target layout: ProgramModel and Interpreter as two sibling targets, ADR-021 — M3 preview data path: colour-resolved stitch events into an append-only display list, ADR-022 — M3 target layout: Samples and StagePreview as app-support targets, ADR-023 — what runs where: local gate vs CI, ADR-024 — The stage renderer: batching hoisted out of the renderer (+40 more)

### Community 10 - "Stage Transform Core"
Cohesion: 0.10
Nodes (11): .affine, CGAffineTransform, StageTransform, Bool, Double, ViewPoint, .center, StagePreviewTargetIsolationTests (+3 more)

### Community 11 - "Interpreter Target Isolation"
Cohesion: 0.07
Nodes (3): EmbroideryEngine, InterpreterTargetIsolationTests, ProgramModel

### Community 12 - "Coordinate Conversion Geometry"
Cohesion: 0.09
Nodes (16): Hashable, BoundingBox, .boundingBox, Bool, Double, EmbroideryPoint, javaRound(), Double (+8 more)

### Community 13 - "Stage Transform Test Suite"
Cohesion: 0.12
Nodes (12): StageTransformDrawabilityTests, StageBox, .center, .height, .width, Double, ViewSize, .asymmetricFit (+4 more)

### Community 14 - "Running Stitch & Traversal"
Cohesion: 0.13
Nodes (8): StagePoint, RunningStitchPattern, Double, RunningStitchPatternTests, Double, Int, TraversalPredicateTests, StageGeometryTests

### Community 15 - "Stitch Draw Plan Windowing"
Cohesion: 0.12
Nodes (10): DotRun, Range<Int>, Int, Range, StitchDrawPlan, Int, Range, StitchDrawPlanTests (+2 more)

### Community 16 - "Stitch Display List & Summary"
Cohesion: 0.10
Nodes (16): ArraySlice, StageSummary, Double, Int, ColorRun, StitchDisplayList, .bounds, .count (+8 more)

### Community 17 - "CoreGraphics Canvas Renderer"
Cohesion: 0.09
Nodes (27): Baked, BakeKey, CanvasStitchLayers, .bakeKey, .body, .travelOpacity, NeedleLayer, .body (+19 more)

### Community 18 - "Run Lifecycle Story Specs"
Cohesion: 0.07
Nodes (35): Bridging-segment rule at the watermark, Press-play empty state, Fit target union(stageRect, contentBounds), hoop unclipped, Hoop-overflow notice, Catroid PenActor FrameBuffer stamp, Settled/live split with cached raster and settledCount watermark, Catty teardown-before-share hazard, Catroid deltaActionTimeDivisor anti-throttle (do not port) (+27 more)

### Community 19 - "Stage Bounds & Fit Targets"
Cohesion: 0.14
Nodes (8): Sequence, displayList(), previewStitch(), StageBoundsAxisIndependenceTests, StageBoundsFinitenessTests, StageFitBeyondGestureLimitTests, StitchDisplayListResetIdentityTests, StitchDisplayListTests

### Community 20 - "Stitch Pattern Story Specs"
Cohesion: 0.15
Nodes (32): ADR-005 — DST semantics ported from Catroid, verified against Catty fixtures, ADR-012 — DST byte-level semantics, Catroid authoritative, ADR-013 — color-change flag placement on interpolated moves, ADR-020 — engine coordinate boundary and ±121 guard, Catroid (Pocket Code Android) reference implementation, Catty (Pocket Code iOS) reference implementation and golden fixtures, javaRound — floor(x + 0.5) rounding rule, E1 — Infrastructure epic (+24 more)

### Community 21 - "Bundled Sample Story Specs"
Cohesion: 0.08
Nodes (32): ADR-014 — pattern arithmetic is Double; no bit-exact Android parity, ADR-017 — formula arithmetic divergences, ADR-018 — interpreter tick/clock semantics, ADR-019 — a golden on a threshold must guard itself, AGENTS.md / CLAUDE.md parity rule, Codex CLI primitives (.codex/config.toml hooks, .codex/agents, .agents/skills), Dual-driver workflow plan (Claude Code / Codex CLI interchangeable), Documented deviations from Catroid (+24 more)

### Community 22 - "Golden Program Consumption"
Cohesion: 0.13
Nodes (5): eventTags(), recordPositions(), GoldenProgramSquareConsumptionTests, GoldenProgramStarConsumptionTests, GoldenProgramStarTests

### Community 23 - "Run View Model"
Cohesion: 0.17
Nodes (9): RunViewModel, Never, Task, Void, NotificationCounter, RunViewModelTests, Double, Int (+1 more)

### Community 24 - "Formula Evaluation Tests"
Cohesion: 0.11
Nodes (9): Formula, binary, number, unaryMinus, variable, Double, FormulaTests, Double (+1 more)

### Community 25 - "Script & Paired Control"
Cohesion: 0.16
Nodes (8): ClosedRange, ScriptValidationError, unmatchedLoopEnd, unmatchedLoopOpener, Int, Script, ScriptTests, Int

### Community 26 - "Golden Program Oracles"
Cohesion: 0.15
Nodes (27): StitchPattern, actionBrickCount(), GoldenOp, activate, finalize, move, setColor, sewUp (+19 more)

### Community 27 - "Interpreter Driver & Budgets"
Cohesion: 0.14
Nodes (11): FrameOutcome, InterpreterDriver, Bool, Int, RunBudget, Int, RunPacing, InterpreterDriverTests (+3 more)

### Community 28 - "App Model & Renderer Wiring"
Cohesion: 0.10
Nodes (4): Observation, StagePreview, SwiftUI, UIKit

### Community 29 - "Mid-Run Screenshot Evidence"
Cohesion: 0.10
Nodes (27): ADR-027 — The run lifecycle: two tasks, a terminal that cannot be forgotten, three budget axes, US-306 Mid-Run Screenshot (Square Coil), Circular Back Button, Hoop Boundary Rectangle, Hoop Size Caption 100 mm x 100 mm, Incremental Live Stitch Growth, Needle Position Cursor, Program Title Header "Square Coil" (+19 more)

### Community 30 - "DST Stitch Record Codec"
Cohesion: 0.11
Nodes (13): DSTStitchRecord, Bool, Int, UInt16, UInt8, BitContribution, DecodedRecord, Bool (+5 more)

### Community 31 - "Brick Enum & Defaults"
Cohesion: 0.07
Nodes (27): Brick, changeVariableBy, changeXBy, changeYBy, forever, loopEnd, moveNSteps, placeAt (+19 more)

### Community 32 - "Sample Picker & Selection"
Cohesion: 0.14
Nodes (14): ButtonStyle, AppModel, .samples, Bool, StageDestination, stage, PickerRowButtonStyle, previewModelWithASelection() (+6 more)

### Community 33 - "Stepper Embroidery Bricks"
Cohesion: 0.24
Nodes (4): Int, runAndSerialize(), stitchPositions(), StepperEmbroideryTests

### Community 34 - "Sample Program Library"
Cohesion: 0.10
Nodes (14): Hasher, Identifiable, SampleProgram, .descriptionKey, .displayName, .nameKey, .programJSONURL, .summary (+6 more)

### Community 35 - "DST Header Writer"
Cohesion: 0.21
Nodes (7): DSTHeader, Int, UInt8, DSTHeaderTests, Double, Int, UInt8

### Community 36 - "Script Move Semantics"
Cohesion: 0.15
Nodes (10): Error, FormulaError, notANumber, ScriptMoveError, destinationOutOfBounds, sourceIsNotLoopOpener, sourceOutOfBounds, unbalancedPair (+2 more)

### Community 37 - "Stage View & Transport Row"
Cohesion: 0.11
Nodes (19): StageTransportRow, Bool, Void, StageView, .body, .canvasSlot, .emptyStage, .hoopSizeDescription (+11 more)

### Community 38 - "Stage Gesture Recognition"
Cohesion: 0.17
Nodes (8): StageGesture, .isIdentity, .pan, Bool, Double, StageInteractionTests, .fit, Double

### Community 39 - "Sample Threshold Screening"
Cohesion: 0.17
Nodes (16): SampleThresholdTests, Double, Int, BoundaryProbe, .distanceIsExactlyOnBoundary, .isDecidedByLibm, emissionCountsPerMove(), needleMove() (+8 more)

### Community 40 - "Stage Zoom Bounds"
Cohesion: 0.16
Nodes (4): CGSize, StageZoomBounds, Double, StageZoomBoundsTests

### Community 42 - "Thread Color & Segment Style"
Cohesion: 0.16
Nodes (9): UInt16, UInt8, ThreadColor, Stroke, StitchSegmentStyle, suppressed, thread, traversal (+1 more)

### Community 43 - "Triple Stitch Pattern"
Cohesion: 0.24
Nodes (4): Double, TripleStitchPattern, Double, TripleStitchPatternTests

### Community 44 - "Run Pacing & Draining"
Cohesion: 0.14
Nodes (13): drain(), DrainedRun, .stitchCountsPerUpdate, .stitches, .terminalCount, .termination, GatedRunPacing, stitchEventCount() (+5 more)

### Community 46 - "Run Batch Assembly"
Cohesion: 0.19
Nodes (5): PreviewStitch, PreviewNeedle, foldBatches(), FoldedRun, RunBatchTests

### Community 47 - "DST Fixture Reader"
Cohesion: 0.16
Nodes (11): StageAccessibility, Double, String, .asComment, Comment, DSTFileReader, UInt8, FixtureTests (+3 more)

### Community 48 - "Needle Glyph Rendering"
Cohesion: 0.20
Nodes (6): Darwin, Glibc, NeedleGlyph, Double, NeedleGlyphTests, Double

### Community 49 - "Script Compiler & Instructions"
Cohesion: 0.15
Nodes (14): Instruction, brick, foreverBegin, loopEnd, repeatBegin, ScriptCompiler, Int, .isFinished (+6 more)

### Community 50 - "Variable Scope Model"
Cohesion: 0.16
Nodes (4): Double, Double, Variable, ProgramModelTests

### Community 51 - "DST Header Field Reader"
Cohesion: 0.13
Nodes (18): asciiField(), DSTHeaderField, colorBlocks, endOffsetX, endOffsetY, extentMinusX, extentMinusY, extentPlusX (+10 more)

### Community 52 - "Stage Canvas Animation"
Cohesion: 0.17
Nodes (14): AccessibilityAdjustmentDirection, Animatable, SettlingProgress, .animatableData, .body, StageCanvas, .body, Double (+6 more)

### Community 53 - "Stage View Wiring"
Cohesion: 0.36
Nodes (7): Binding, Invocation, RecordingRenderer, StageViewWiringTests, CGSize, View, EmptyView

### Community 55 - "Formula Evaluation Runtime"
Cohesion: 0.21
Nodes (7): Float, Double, VirtualNeedle, Double, Int, Scope, VariableScope

### Community 56 - "Interpreter Step Loop"
Cohesion: 0.32
Nodes (6): Interpreter, Bool, Double, Int, Bool, Double

### Community 57 - "App String Catalog Tests"
Cohesion: 0.13
Nodes (3): catrobat_embroidery_ios, AppStringsTests, CoreGraphics

### Community 58 - "Run State & Completion"
Cohesion: 0.14
Nodes (11): RunPhase, RunCompletion, programFinished, stitchLimitReached, stoppedByUser, RunState, finished, idle (+3 more)

### Community 59 - "Stage Content State"
Cohesion: 0.19
Nodes (7): StageContentState, drawn, noSelection, notRun, Bool, Self, StageContentStateTests

### Community 60 - "DST Field Width Story Spec"
Cohesion: 0.16
Nodes (14): ADR-011 — Privacy: fully offline, no accounts, no tracking, ADR-025 — throwing DST serialization (US-211 close-out), E8 — Release readiness epic, M6 — Brick parity & polish milestone, US-210 — Coordinate overflow chokepoint, Export gates on post-replay assembledStream().count > 1, Manual Ink/Stitch verification (US-301 and US-308 only), DSTHeader.appendField precondition (the chokepoint) (+6 more)

### Community 61 - "iPad Sidebar Screenshot"
Cohesion: 0.19
Nodes (14): US-307 iPad Regular Size Class Screenshot, Hoop Bounds Frame and 100 mm x 100 mm Caption, Octagon Rosette Example Design, Play Again Primary Action Button, Regular Size Class Adaptive Layout, Selected Design Checkmark Row, Example Designs Sidebar, Sidebar Toggle Toolbar Button (+6 more)

### Community 62 - "Interpreter Events & Harness"
Cohesion: 0.16
Nodes (13): InterpreterEvent, colorArmed, finalizeRequested, needleMoved, stitch, waited, Int, SampleRun (+5 more)

### Community 64 - "Stitch Draw Metrics"
Cohesion: 0.24
Nodes (5): StitchDrawMetrics, Double, Double, StitchDrawMetricsTests, Bool

### Community 65 - "Display vs Export Divergence"
Cohesion: 0.26
Nodes (5): DisplayVersusExportModelTests, interpreter(), tickBatches(), twoActorsOnOneLayerProgram(), assembledStream()

### Community 66 - "Run Control Appearance"
Cohesion: 0.23
Nodes (6): Appearance, RunControl, Bool, Double, LocalizedStringResource, RunControlTests

### Community 67 - "Paired Control Story Spec"
Cohesion: 0.19
Nodes (13): ADR-002 — Stack: native Swift 6 / SwiftUI, engine as SPM package, ADR-004 — Minimum iOS version 17.0, ADR-006 — @Observable MVVM, no architecture frameworks, ADR-008 — Script representation: flat brick list with paired control bricks, E5 — Block editor epic, Engineering standards (Swift Testing, strict concurrency, Bundle.module fixtures), M4 — Block editor milestone, Flat scripts with paired control bricks (+5 more)

### Community 68 - "Dynamic Type Screenshot"
Cohesion: 0.23
Nodes (13): US-306 Screenshot: Stage at AX5 Dynamic Type, AX5 Accessibility Dynamic Type Setting, Circular Back Navigation Button, Hoop Size Label "Hoop 100 mm x 100 mm", Hoop Boundary Outline (100 mm x 100 mm), Manual Accessibility Pass Evidence (Dynamic Type), Play Again Button (Terminal Run State), Program Title Header "Square Coil" (+5 more)

### Community 69 - "Dark Mode Screenshot (US-306)"
Cohesion: 0.21
Nodes (13): US-306 Stage Screen Screenshot (Dark Mode), Circular Back Navigation Button, Dark Mode Appearance State, Hoop Size Caption Label, Hoop Frame Outline (100 mm x 100 mm), Light Fabric Stage Kept Constant in Dark Mode, Play Again Primary Button, Program Title Header "Square Coil" (+5 more)

### Community 70 - "Canvas Renderer Story Spec"
Cohesion: 0.17
Nodes (13): CanvasStitchRenderer, Catty two-SKShapeNodes-per-stitch anti-goal, MetalStitchRenderer escape hatch, Per-colour-run path batching rule (≤ 2 stroked paths + 1 dot path), PreviewStitch, EmbroideryStream.requiresTraversal, StagePreviewRenderer protocol, StageView (generic over renderer) (+5 more)

### Community 71 - "Stage Render Transform Bake"
Cohesion: 0.18
Nodes (8): StageRenderTransform, .bake, .canUseRaster, .current, live, settled, Bool, StageRenderTransformTests

### Community 73 - "Virtual Needle Brick Tests"
Cohesion: 0.22
Nodes (3): Bool, Double, VirtualNeedleBrickTests

### Community 74 - "Completed Run Screenshot"
Cohesion: 0.23
Nodes (12): US-307 Screenshot ax5 — Stage at Accessibility Dynamic Type, Back Navigation Button, Completed Run Terminal State, Design Run Screen (Octagon Rosette), Accessibility Dynamic Type Size (AX5), Fit-to-Hoop Zoom Framing, Hoop Boundary Frame in Stage, Hoop 100 mm x 100 mm Label (+4 more)

### Community 75 - "Mid-Run Screenshot (US-307)"
Cohesion: 0.24
Nodes (12): Circular Back Navigation Button, Hoop Boundary Rectangle, Hoop 100 mm x 100 mm Caption, Current Needle Position Marker, Octagon Rosette Sample Program, Run-In-Progress Stage State, US-307 Mid-Run Stage Screenshot, Embroidery Stage Screen (+4 more)

### Community 76 - "Panned Stage Screenshot"
Cohesion: 0.26
Nodes (12): US-307 Screenshot: Stage After Panning, Circular Back Button, Stage Clips Panned Content at Its Bounds, Hoop Boundary Rectangle, Hoop 100 mm x 100 mm Caption, Navigation Title 'Octagon Rosette', Pan Offset Translation, Play Again Primary Button (+4 more)

### Community 77 - "Stage Fit Target Isolation"
Cohesion: 0.23
Nodes (3): StageGeometry, Double, StageFitTargetTests

### Community 78 - "App Root & Window Scene"
Cohesion: 0.20
Nodes (10): App, CanvasStitchRenderer, CatrobatEmbroideryApp, .body, WindowRootView, .body, RootView, .body (+2 more)

### Community 79 - "Object & Script Header"
Cohesion: 0.22
Nodes (6): Codable, Object, Double, Int, ScriptHeader, whenStarted

### Community 80 - "Post-Run Screenshot"
Cohesion: 0.25
Nodes (11): US-306 Post-Run Stage Screenshot, Back Navigation Control, Hoop Frame Outline, Hoop 100 mm x 100 mm Label, Play Again Button, Program Title Header, Square Coil Spiral Design, Stage Screen (Square Coil) (+3 more)

### Community 81 - "Mid-Drag Screenshot"
Cohesion: 0.25
Nodes (11): US-307 Screenshot: Mid-Drag Pan, Circular Back Navigation Button, Hoop Boundary Rectangle, Hoop 100 mm x 100 mm Caption, Design Title Header (Octagon Rosette), Octagon Rosette Stitch Design, Pan (Drag) Gesture In Progress, Play Again Primary Button (+3 more)

### Community 82 - "Preview Core Story Spec"
Cohesion: 0.20
Nodes (11): StageTransform.minimumScale / minimumRepresentableScale split, Span versus per-direction extent (the refuted overlap argument), Display model ≠ export model (the normative rule), Catroid EmbroideryExportIsolationTest.kt, PreviewStitch, RunBatch.reducing(_:from:), StageGeometry (ADR-007's 500×500 stage in code), StagePreview target (Foundation-only library product) (+3 more)

### Community 85 - "Virtual Needle Finiteness"
Cohesion: 0.29
Nodes (3): Bool, Double, VirtualNeedleTests

### Community 86 - "Run Clock & Display Pacing"
Cohesion: 0.22
Nodes (4): AppRunClock, Duration, DisplayRunPacing, ImmediateRunPacing

### Community 87 - "Dark Mode Screenshot (US-307)"
Cohesion: 0.24
Nodes (10): US-307 Dark Mode Stage Screenshot, Dark Mode Appearance, Fabric-Neutral Stage in Dark Chrome, Fit-to-Hoop Zoom Baseline, Hoop Boundary 100 mm x 100 mm, Navigation Bar with Back Button and Title, Octagon Rosette Design, Play Again Button (+2 more)

### Community 88 - "Fit-to-Content Screenshot"
Cohesion: 0.31
Nodes (10): Fit-to-Content Zoom State, Hoop Bounds Rectangle (100 mm x 100 mm), Hoop Size Caption Label, Navigation Bar with Back Button and Title, Octagon Rosette Sample Design, Play Again Button, US-307 Fit-to-Content Screenshot, Embroidery Stage / Run Screen (+2 more)

### Community 89 - "Stepper Core Story Spec"
Cohesion: 0.20
Nodes (10): Deterministic time, Catroid-faithful ticks, The needle is the object, NeedleUpdate (one per executed motion brick), VirtualNeedle (position, heading), Catroid ThreadScheduler (one act per sequence per tick), Interpreter value type (step/run/isFinished), InterpreterClock (injected logical tickDelta), InterpreterEvent enum (+2 more)

### Community 90 - "Byte Diff Reporting"
Cohesion: 0.29
Nodes (3): firstByteDifference(), UInt8, ByteDiffTests

### Community 91 - "DST Round-Trip Decode"
Cohesion: 0.38
Nodes (5): DecodedDSTFile, Data, Int, DSTRecordDecoder, DSTRoundTripTests

### Community 92 - "Sample Budget Guards"
Cohesion: 0.29
Nodes (4): SampleBudgetTests, Int, SampleDSTTests, run()

### Community 93 - "Preview Test Fixtures"
Cohesion: 0.33
Nodes (9): bracketedWaitProgram(), oversizeProgram(), PreviewColor, serializedTwoObjectProgram(), singleObjectProgram(), Double, Int, twoLayersProgram() (+1 more)

### Community 94 - "Binary Operator Enum"
Cohesion: 0.22
Nodes (7): CaseIterable, BinaryOperator, divide, minus, mult, plus, pow

### Community 95 - "Gated Run Pacing"
Cohesion: 0.31
Nodes (5): GatedPacing, Bool, CheckedContinuation, Never, Void

### Community 96 - "Compensated Magnitude Math"
Cohesion: 0.31
Nodes (4): CompensatedMagnitudeTests, Double, Int, compensatedMagnitude()

### Community 97 - "Stage Motion & Fit Animation"
Cohesion: 0.29
Nodes (5): Animation, StageMotion, Bool, .body, ContentTransition

### Community 98 - "Run Session Async Stream"
Cohesion: 0.39
Nodes (5): AsyncStream, RunSession, Never, Task, Void

### Community 102 - "Sample Identity & Resources"
Cohesion: 0.29
Nodes (4): SampleID, octagonRosette, .resourceName, squareCoil

### Community 103 - "Deterministic Traversal RNG"
Cohesion: 0.43
Nodes (3): SplitMix64, Double, UInt64

### Community 104 - "Sample Row Accessibility Label"
Cohesion: 0.40
Nodes (4): SampleRowView, .body, Bool, SampleRowAccessibilityTests

### Community 105 - "DST Header Field Types"
Cohesion: 0.60
Nodes (5): coField(), numericField(), stField(), Int, UInt8

### Community 106 - "Preview Core Deviations"
Cohesion: 0.40
Nodes (5): Documented deviations from the Catroid/Catty references, Jump traversals drawn distinctly from thread, Needle indicator (our own design, no reference precedent), EmbroideryStream.interpolationSplitCount (shared dual trigger), EmbroideryStream.requiresTraversal(from:to:)

### Community 107 - "DST Export Story Spec"
Cohesion: 0.40
Nodes (5): DSTDesign: Transferable via ShareLink, Exported-vs-imported type tension, UTExportedTypeDeclarations for .dst, UTType lookup canary test, UTTypeConformsTo public.data + public.content (AirDrop)

### Community 110 - "Step Outcome Enum"
Cohesion: 0.50
Nodes (3): StepOutcome, finished, ticked

### Community 113 - "Square Coil Program Builder"
Cohesion: 0.67
Nodes (3): coilLoop(), makeSquareCoilProgram(), Int

### Community 115 - "App Rehabilitation Story Spec"
Cohesion: 1.00
Nodes (3): SwiftPM does not compile String Catalogs, Localizable.xcstrings (app String Catalog), No-hardcoded-strings SwiftLint rule

## Ambiguous Edges - Review These
- `US-306 — Run lifecycle: driver, AsyncStream, batching, play/stop, needle` → `Multi-Color Thread Rendering (Orange / Blue)`  [AMBIGUOUS]
  docs/screenshots/us-306/dark.png · relation: conceptually_related_to
- `US-307 — Pinch-zoom / pan and the stage VoiceOver summary` → `VoiceOver Run-State Summary`  [AMBIGUOUS]
  docs/screenshots/us-307/midrun.png · relation: implements
- `US-307 — Pinch-zoom / pan and the stage VoiceOver summary` → `Zoomed-In Stage State`  [AMBIGUOUS]
  docs/screenshots/us-307/panned.png · relation: conceptually_related_to
- `Embroidery Stage Screen (Square Coil)` → `Two-Color Stitch Rendering (Orange / Blue Thread Change)`  [AMBIGUOUS]
  docs/screenshots/us-306/ax5_real.png · relation: conceptually_related_to
- `Circular Back Button` → `Run Lifecycle State: Running`  [AMBIGUOUS]
  docs/screenshots/us-306/midrun.png · relation: conceptually_related_to
- `Run Lifecycle Terminal State (finished run)` → `Stitch Preview Canvas`  [AMBIGUOUS]
  docs/screenshots/us-306/postrun.png · relation: conceptually_related_to
- `Stitch Preview Stage` → `Hoop 100 mm x 100 mm Label`  [AMBIGUOUS]
  docs/screenshots/us-307/ax5.png · relation: shares_data_with
- `Octagon Rosette Design` → `Play Again Button`  [AMBIGUOUS]
  docs/screenshots/us-307/dark.png · relation: shares_data_with
- `Embroidery Stage / Run Screen` → `Terminal (Finished) Run State`  [AMBIGUOUS]
  docs/screenshots/us-307/fit.png · relation: conceptually_related_to
- `Embroidery Stage Screen (iPad)` → `Stage VoiceOver Run-State Summary`  [AMBIGUOUS]
  docs/screenshots/us-307/ipad-regular.png · relation: conceptually_related_to
- `Play Again Primary Action Button` → `Stage VoiceOver Run-State Summary`  [AMBIGUOUS]
  docs/screenshots/us-307/ipad-regular.png · relation: conceptually_related_to
- `Pan (Drag) Gesture In Progress` → `Hoop Boundary Rectangle`  [AMBIGUOUS]
  docs/screenshots/us-307/mid-drag.png · relation: conceptually_related_to
- `Run-In-Progress Stage State` → `VoiceOver Run-State Summary`  [AMBIGUOUS]
  docs/screenshots/us-307/midrun.png · relation: conceptually_related_to

## Knowledge Gaps
- **213 isolated node(s):** `PackageDescription`, `.hasValidPattern`, `.hasEmittedOps`, `.count`, `.firstStitchPosition` (+208 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **24 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `US-306 — Run lifecycle: driver, AsyncStream, batching, play/stop, needle` and `Multi-Color Thread Rendering (Orange / Blue)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `US-307 — Pinch-zoom / pan and the stage VoiceOver summary` and `VoiceOver Run-State Summary`?**
  _Edge tagged AMBIGUOUS (relation: implements) - confidence is low._
- **What is the exact relationship between `US-307 — Pinch-zoom / pan and the stage VoiceOver summary` and `Zoomed-In Stage State`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Embroidery Stage Screen (Square Coil)` and `Two-Color Stitch Rendering (Orange / Blue Thread Change)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Circular Back Button` and `Run Lifecycle State: Running`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Run Lifecycle Terminal State (finished run)` and `Stitch Preview Canvas`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Stitch Preview Stage` and `Hoop 100 mm x 100 mm Label`?**
  _Edge tagged AMBIGUOUS (relation: shares_data_with) - confidence is low._