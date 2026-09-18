# Graph Report - catty-embroidery  (2026-09-18)

## Corpus Check
- 130 files · ~788,577 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3549 nodes · 9196 edges · 196 communities (153 shown, 43 thin omitted)
- Extraction: 74% EXTRACTED · 26% INFERRED · 0% AMBIGUOUS · INFERRED: 2380 edges (avg confidence: 0.8)
- Token cost: 568,020 input · 0 output

## Community Hubs (Navigation)
- Preview Run State & Batches
- Stitch Display List & Summary
- Stage Render Transform & Layers
- Frame Time Recorder
- Stage Interaction Transitions
- Interpreter & Program Model
- Embroidery Stream & Points
- Stage Manipulation Channels
- Frame Time Statistics
- Script & Paired Control
- M3 Performance Story Specs
- Interpreter Driver & Budgets
- M2 Story Specs
- Stitch Draw Plan
- Package Products & Golden Glue
- Stage Canvas & Pan Directions
- Draw Plan Coarsening
- Stage Transform Test Glue
- Bake Scheduling & Timing
- Stage Transform Core
- Stage Transform Math
- Stage & Manipulation ADRs
- DST Semantics ADRs
- Zigzag Stitch Pattern
- Formula & Variable Scope
- Stage Box & Fit Targets
- Interpreter Events & Runs
- Repo Process & Review Docs
- Canvas Stitch Strokes
- Export View Model
- Export Readiness & Control
- Run View Model
- Pattern Manager & Actors
- Manipulation Catcher
- Run State & Transport Row
- SwiftUI Manipulation Wiring
- Brick Enum & Defaults
- App Model & Selection
- Gesture Stubs & Recording
- DST File Name Sanitisation
- Preview Fixtures & Divergence
- Stage Fitting & View Size
- Target Layout ADRs
- Arithmetic & Threshold ADRs
- Stage Point & Traversal
- DST File Assembly
- DST Stitch Record Codec
- Stage Accessibility Strings
- Preview Stitch & Run Batch
- Export & Lifecycle ADRs
- Sample Programs & Budgets
- Stepper Embroidery Runs
- Golden Fixture Readers
- Stage Zoom Bounds
- DST Header & Field Errors
- Running Stitch
- Golden Program Oracle
- Synthetic 50k Design
- Design Name Validation
- Recogniser Coordinator
- Design Name Field Layout
- Design Name Presentation
- Frame Time Readout
- Sample Library Wiring
- Program Model Builders
- Cross-Target Test Files
- Manipulation Wiring Tests
- DST Header Tests
- Running Stitch Pattern
- Sew-Up Bar Tack
- Triple Stitch Pattern
- Golden Program Consumption
- Temporary DST File Writer
- Object & Codable Model
- DST Header Field Append
- Accessibility Memoisation
- Touch Tracking View
- Stage View Composition
- Needle Glyph Rendering
- US-307 Stage Screenshots
- Interpolation & Rounding
- Thread Color Hex
- Golden Square Byte Runs
- DST Header Field Types
- Golden Square Programs
- Export & Formula Errors
- Run Screen Screenshots
- Script Compiler Runtime
- Stitch Segment Style
- CI Jobs & Lint Rules
- Project Guidance Docs
- Formula Evaluation Runtime
- Interpolation Predicates
- Sample Threshold Screening
- Stage Toggle & Pan
- App Target Test Files
- Export Control Readiness
- Interpreter Core Concepts
- Virtual Needle Apply
- Stitch Draw Metrics
- Draw Plan Windowing
- DST Round-Trip Decode
- Pattern Manager Colour Tests
- Golden Star Program Tests
- Threshold Screening Probe
- Sample Picker View
- Stage Field View
- DST File Writing Seam
- Coarsening Corner Rule
- Pattern Manager Layers
- Virtual Needle Brick Tests
- DST Design & Export Row
- Export Eligibility Tests
- UTType Declaration
- US-306 Accessibility Screenshots
- Square Coil Screenshots
- Octagon Rosette Screenshots
- iPad Sidebar Screenshots
- Canvas Renderer Protocol
- Stage Summary Invariants
- M3 Close-Out ADR Notes
- Export After Stop
- Virtual Needle Tests
- Gesture Stub Doubles
- Dual-Driver Workflow Docs
- US-306 Stage Screenshots
- Run State Revision Model
- Byte Diff Reporting
- Golden Square Manual Path
- Octagon Rosette Goldens
- Binary Operator Enum
- Gated Run Pacing
- Dark Mode Screenshots
- Display vs Export Model
- Compensated Magnitude
- Square Coil Goldens
- Synthetic Design Builder
- App Root & Window Scene
- Run Session Async Stream
- Stage Content State
- App String Catalog Tests
- Export Error Semantics
- Frame Capture Instrument
- DST Serialization Contract
- Raster & Buffering Policy
- Stage Gesture Value
- Stepper Stitch Colors
- Sample Library Tests
- Stage View Wiring
- Script Representation ADR
- M3 Milestone Stories
- Run Lifecycle Screenshots
- Export Eligibility Reasons
- Settling Phase Enum
- Manipulation Channel Enum
- DST Header Numeric Fields
- Transform Interpolation
- UI Definition of Done
- Coarse Span Rules
- Brick Codable Tests
- SampleRunHarness.swift
- bracketedWaitProgram()
- StageRenderTransformTests
- SampleLinkageTests
- ADR-029 fallback ladder and the frame-
- Mutation as the substitute for red whe
- DoubleEquality.swift
- StageZoomAdjustment.swift
- SplitMix64
- SampleDSTTests
- The .success exit test — proving red a
- ADR-028 amendment — one commit per man
- GoldenSquareLiterals.swift
- ADR-022 — Samples and StagePreview as 
- Buildability check — every story's sym
- Export gates on assembledStream().coun
- The BakeKey settledCount hazard (liven
- StageCommitCounter (#if DEBUG instrume
- PackageDescription
- Binding
- Never
- Task
- Content
- Backlog-at-discovery-time policy
- Golden byte-identity with no re-blessi
- Each row is a single VoiceOver element
- Thread colours are design data, only c
- Press-play empty state
- Temporary synchronous drain in AppMode
- Deferred thread-contrast casing
- reset() as one assignment (value-type 
- Abbreviated for the eye, wide for the 
- DragGesture
- Gesture
- MagnifyGesture
- SimultaneousGesture

## God Nodes (most connected - your core abstractions)
1. `StagePoint` - 258 edges
2. `EmbroideryEngine` - 129 edges
3. `Testing` - 124 edges
4. `StageInteraction` - 99 edges
5. `Interpreter` - 88 edges
6. `EmbroideryStream` - 83 edges
7. `Script` - 81 edges
8. `StagePreview` - 79 edges
9. `Program` - 76 edges
10. `PreviewRunState` - 76 edges

## Surprising Connections (you probably didn't know these)
- `Fixed frame-time bar (p99 <= 16.67 ms, no frame > 33.3 ms)` --semantically_similar_to--> `ADR-012 is the arbiter where references disagree`  [INFERRED] [semantically similar]
  docs/us-309-device-handoff.md → CLAUDE.md
- `An ADR outranks any generated artifact (graph, index, summary)` --semantically_similar_to--> `ADR-012 is the arbiter where references disagree`  [INFERRED] [semantically similar]
  AGENTS.md → CLAUDE.md
- `Custom rule: hardcoded user-facing string` --semantically_similar_to--> `Local commit gate hook (a convenience, not an enforcement boundary)`  [INFERRED] [semantically similar]
  .swiftlint.yml → CLAUDE.md
- `Custom rule: hardcoded user-facing string` --semantically_similar_to--> `US-312 — Thread colours do not survive export`  [INFERRED] [semantically similar]
  .swiftlint.yml → docs/user-stories/backlog.md
- `Graph drift check is defined by its output, not its effort` --semantically_similar_to--> `Knowledge-graph drift check at milestone close`  [INFERRED] [semantically similar]
  AGENTS.md → CLAUDE.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **The DST byte-semantics arbitration chain** — docs_decisions_adr_005, docs_decisions_adr_012, docs_decisions_adr_013, docs_decisions_adr_015, docs_decisions_adr_020, docs_decisions_adr_025, docs_decisions_catroid_is_authoritative, docs_decisions_javaround [EXTRACTED 1.00]
- **The M3 rendering and performance chain (ADR-009's bet to its measurement)** — docs_decisions_adr_009, docs_decisions_adr_021, docs_decisions_adr_024, docs_decisions_adr_027, docs_decisions_adr_028, docs_decisions_adr_029, docs_decisions_adr_030, docs_decisions_adr_031, docs_decisions_fallback_ladder [EXTRACTED 1.00]
- **Package layering and what the fast gate protects** — docs_decisions_adr_002, docs_decisions_adr_006, docs_decisions_adr_016, docs_decisions_adr_022, docs_decisions_adr_023, docs_decisions_local_gate_vs_ci [INFERRED 0.85]
- **The US-309 frame-time instrument** — docs_user_stories_milestone_3_us_309_fifty_thousand_stitch_exit_criterion_frametimerecorder, docs_user_stories_milestone_3_us_309_fifty_thousand_stitch_exit_criterion_frametimeproxy, docs_user_stories_milestone_3_us_309_fifty_thousand_stitch_exit_criterion_frametimestatistics, docs_user_stories_milestone_3_us_309_fifty_thousand_stitch_exit_criterion_framecaptureverdict, docs_user_stories_milestone_3_us_309_fifty_thousand_stitch_exit_criterion_stagedrawcounter [EXTRACTED 1.00]
- **The coarse mid-gesture draw plan** — docs_user_stories_milestone_3_us_310_coarsen_mid_gesture_draw_plan_segmentindexpair, docs_user_stories_milestone_3_us_310_coarsen_mid_gesture_draw_plan_coarsespanrule, docs_user_stories_milestone_3_us_310_coarsen_mid_gesture_draw_plan_perrundotstriding, docs_user_stories_milestone_3_us_310_coarsen_mid_gesture_draw_plan_coarseningstride, docs_user_stories_milestone_3_us_310_coarsen_mid_gesture_draw_plan_forframe, docs_user_stories_milestone_3_us_310_coarsen_mid_gesture_draw_plan_iscorner [EXTRACTED 1.00]
- **The M3 60 fps criterion evidence chain** — docs_user_stories_milestone_3_readme_exitcriteria, docs_user_stories_milestone_3_us_309_fifty_thousand_stitch_exit_criterion_midgesturefailure, docs_user_stories_milestone_3_us_309_fifty_thousand_stitch_exit_criterion_fallbackladder, docs_user_stories_milestone_3_us_310_coarsen_mid_gesture_draw_plan, docs_user_stories_milestone_3_readme_a15capture, docs_user_stories_milestone_3_readme_taildiscriminator [EXTRACTED 1.00]
- **The DST export pipeline: gate → name → serialise → write → share** — docs_user_stories_milestone_3_us_308_design_name_and_dst_export_exporteligibility, docs_user_stories_milestone_3_us_308_design_name_and_dst_export_designname, docs_user_stories_milestone_3_us_308_design_name_and_dst_export_dstfilename, docs_user_stories_milestone_3_us_308_design_name_and_dst_export_eager_preparation, docs_user_stories_milestone_3_us_308_design_name_and_dst_export_dstfilewriting, docs_user_stories_milestone_3_us_308_design_name_and_dst_export_dstdesign, docs_user_stories_milestone_3_us_308_design_name_and_dst_export_uttype_dst [EXTRACTED 1.00]
- **What keeps the DST header's fixed-width fields safe** — docs_user_stories_milestone_3_us_211_dst_field_width_chokepoint_dstserializationerror, docs_user_stories_milestone_3_us_211_dst_field_width_chokepoint_dstheader_field, docs_user_stories_milestone_3_us_211_dst_field_width_chokepoint_emission_order_contract, docs_user_stories_milestone_3_us_211_dst_field_width_chokepoint_reachability_asymmetry, docs_user_stories_milestone_3_us_211_dst_field_width_chokepoint_cap_stays, docs_user_stories_milestone_3_us_308_design_name_and_dst_export_dstheader_sanitized [EXTRACTED 1.00]
- **Two-finger manipulation: recognisers → tracker → one commit → bake** — docs_user_stories_milestone_3_us_313b_two_fingers_reach_the_stage_catcher, docs_user_stories_milestone_3_us_313b_two_fingers_reach_the_stage_lifecycle_rules, docs_user_stories_milestone_3_us_313b_two_fingers_reach_the_stage_touch_counting_view, docs_user_stories_milestone_3_us_313a_manipulation_as_a_package_value_stagemanipulation, docs_user_stories_milestone_3_us_313a_manipulation_as_a_package_value_centroid_derivation, docs_user_stories_milestone_3_us_313a_manipulation_as_a_package_value_adr_028_amendment, docs_user_stories_milestone_3_us_313a_manipulation_as_a_package_value_bakekey_settledcount_hazard [EXTRACTED 1.00]
- **Caveats that keep the frame-time instrument from flattering the renderer** — docs_us_309_device_handoff_no_draws_verdict, docs_us_309_device_handoff_drawn_frame_quantiles, docs_us_310_device_handoff_refresh_period_quantisation, docs_us_310_device_handoff_animating_signature, docs_us_309_device_handoff_frametimerecorder [INFERRED 0.85]
- **Process rules mirrored between CLAUDE.md and AGENTS.md** — claude_project_guidance, agents_guidance, claude_adr012_arbiter, agents_adr_authority_over_generated_artifacts, claude_graphify_drift_check, agents_graph_drift_check_defined_by_output, claude_cross_vendor_review_loop, agents_two_layer_review [EXTRACTED 1.00]
- **Transient stage-transform defects invisible to stills** — docs_user_stories_backlog_us314, docs_user_stories_backlog_us315, docs_user_stories_backlog_manipulation_baseline, docs_decisions_adr_028 [INFERRED 0.85]
- **Two-layer cross-vendor review loop** — _claude_commands_codex_review_codex_review, _claude_commands_codex_review_stop_condition, _claude_commands_codex_review_verification_round, _claude_commands_codex_review_adr_arbiter_triage, agents_two_layer_review, _claude_commands_finish_finish [EXTRACTED 1.00]
- **Golden fixture trust chain (external verification before trust)** — packages_embroideryengine_tests_embroideryenginetests_resources_embroideryreference_provenance_stitch_dst, packages_embroideryengine_tests_embroideryenginetests_resources_embroideryreference_provenance_color_change_dst, packages_embroideryengine_tests_interpretertests_resources_goldenprograms_provenance_square_dst, packages_embroideryengine_sources_samples_resources_provenance_octagonrosette, packages_embroideryengine_sources_samples_resources_provenance_squarecoil, packages_embroideryengine_tests_interpretertests_resources_goldenprograms_provenance_self_golden_trust_rule, docs_decisions_adr_012 [EXTRACTED 1.00]
- **M1 DST export pipeline (model → records → header → interpolation → file)** — docs_user_stories_milestone_1_us_102_stitch_model_and_stream_us_102, docs_user_stories_milestone_1_us_103_dst_record_encoder_us_103, docs_user_stories_milestone_1_us_104_dst_header_writer_us_104, docs_user_stories_milestone_1_us_105_interpolation_and_jumps_us_105, docs_user_stories_milestone_1_us_106_dst_file_generator_golden_us_106 [EXTRACTED 1.00]
- **Engine coordinate boundary chokepoint (five traps)** — docs_user_stories_milestone_2_us_210_coordinate_overflow_chokepoint_trigger_on_either, docs_user_stories_milestone_2_us_210_coordinate_overflow_chokepoint_embroiderypoint_converting, docs_user_stories_milestone_2_us_210_coordinate_overflow_chokepoint_split_cap, docs_user_stories_milestone_2_us_210_coordinate_overflow_chokepoint_lattice_step_guard, docs_user_stories_milestone_2_us_210_coordinate_overflow_chokepoint_canappend [EXTRACTED 1.00]
- **Deterministic tick execution model** — docs_user_stories_milestone_2_us_205_stepper_core_interpreterclock, docs_user_stories_milestone_2_us_205_stepper_core_round_robin_one_brick_per_tick, docs_user_stories_milestone_2_us_205_stepper_core_compiled_instruction_array, docs_user_stories_milestone_2_us_205_stepper_core_batch_equivalence, docs_user_stories_milestone_2_readme_deterministic_time_catroid_faithful_ticks [EXTRACTED 1.00]
- **Golden program verification chain (program → stream → bytes)** — docs_user_stories_milestone_2_us_207_golden_program_square_polygonprogram, docs_user_stories_milestone_2_us_207_golden_program_square_goldenprogramoracle, docs_user_stories_milestone_2_us_207_golden_program_square_goldensquareliterals, docs_user_stories_milestone_2_us_208_golden_program_star_goldenstaroracle, docs_user_stories_milestone_2_us_209_pattern_to_bytes_differential_square_dst [EXTRACTED 1.00]
- **StagePreview's Foundation-only core meets the transform-math exit criterion** — docs_user_stories_milestone_3_us_302_preview_core_stagepreview, docs_user_stories_milestone_3_us_302_preview_core_stitchdisplaylist, docs_user_stories_milestone_3_us_302_preview_core_stagetransform, docs_user_stories_milestone_3_us_302_preview_core_stagegeometry [EXTRACTED 1.00]
- **M3 run data path: driver → batches → observable state → renderer** — docs_user_stories_milestone_3_us_306_run_lifecycle_interpreterdriver, docs_user_stories_milestone_3_us_306_run_lifecycle_runbatch, docs_user_stories_milestone_3_us_306_run_lifecycle_previewrunstate, docs_user_stories_milestone_3_us_305_canvas_stitch_renderer_stitchdrawplan, docs_user_stories_milestone_3_us_305_canvas_stitch_renderer_canvasstitchrenderer [INFERRED 0.85]
- **Settled-raster strategy across renderer, run and gestures** — docs_user_stories_milestone_3_us_305_canvas_stitch_renderer_settled_live_split, docs_user_stories_milestone_3_us_305_canvas_stitch_renderer_bridging_segment, docs_user_stories_milestone_3_us_306_run_lifecycle_previewrunstate, docs_user_stories_milestone_3_us_307_zoom_pan_and_accessibility_mid_gesture_raster_policy [INFERRED 0.85]

## Communities (196 total, 43 thin omitted)

### Community 0 - "Preview Run State & Batches"
Cohesion: 0.09
Nodes (24): .exportEligibility, .isExportable, Bool, PreviewRunState, .state, .summary, .summaryRevision, .visibleNeedle (+16 more)

### Community 1 - "Stitch Display List & Summary"
Cohesion: 0.07
Nodes (20): RunPhase, Sequence, StageSummary, Double, Int, ColorRun, StitchDisplayList, .count (+12 more)

### Community 2 - "Stage Render Transform & Layers"
Cohesion: 0.06
Nodes (49): Baked, BakeKey, CanvasStitchLayers, .bakeKey, .travelOpacity, CanvasStitchRenderer, NeedleLayer, .body (+41 more)

### Community 3 - "Frame Time Recorder"
Cohesion: 0.11
Nodes (15): CADisplayLink, .body, FrameTimeProxy, FrameTimeRecorder, .frameCount, .reservedCapacity, Bool, Double (+7 more)

### Community 4 - "Stage Interaction Transitions"
Cohesion: 0.12
Nodes (12): StageInteraction, .isFollowingFit, .isSettling, .settlingProgress, Bool, Double, Int, StageInteractionTransitionTests (+4 more)

### Community 5 - "Interpreter & Program Model"
Cohesion: 0.12
Nodes (15): AppRunClock, Interpreter, NeedleUpdate, Double, StagePoint, InterpreterClock, Double, Program (+7 more)

### Community 6 - "Embroidery Stream & Points"
Cohesion: 0.10
Nodes (15): Hashable, BoundingBox, EmbroideryStream, .boundingBox, .count, .firstStitchPosition, .lastStitchPosition, Int (+7 more)

### Community 7 - "Stage Manipulation Channels"
Cohesion: 0.17
Nodes (16): ViewPoint, StageManipulation, .hasActiveChannel, .isLive, Bool, ClosedRange, Double, StageGesture (+8 more)

### Community 8 - "Frame Time Statistics"
Cohesion: 0.07
Nodes (20): FrameCaptureVerdict, drawsNotMeasured, interrupted, .isAboutTheRenderer, .label, measured, noDraws, nothingCaptured (+12 more)

### Community 9 - "Script & Paired Control"
Cohesion: 0.09
Nodes (15): ClosedRange, ScriptMoveError, destinationOutOfBounds, sourceIsNotLoopOpener, sourceOutOfBounds, unbalancedPair, ScriptValidationError, unmatchedLoopEnd (+7 more)

### Community 10 - "M3 Performance Story Specs"
Cohesion: 0.05
Nodes (49): Milestone 3 — Walking skeleton app, The A15-class capture (outstanding), main had no branch protection — the Protect main ruleset was disabled since M1, Deviation — display list built from ops, export model from the replay (Clause B colour divergence), M3 exit criteria (end-to-end thread, 50k at 60 fps on A15, unit-tested transform math), Final verification deferred to milestone close, Knowledge-graph drift check at milestone close, The manual accessibility pass, run once over all M3 UI (+41 more)

### Community 11 - "Interpreter Driver & Budgets"
Cohesion: 0.08
Nodes (19): Duration, FrameOutcome, InterpreterDriver, Bool, Int, RunBudget, Int, DisplayRunPacing (+11 more)

### Community 12 - "M2 Story Specs"
Cohesion: 0.06
Nodes (46): ADR-001 — App scope: embroidery-focused block app, Milestone 2 — Interpreter MVP, Bricks are a closed indirect enum, Interpreter only calls the engine, never re-implements stream semantics, M2 exit criterion: incrementally consumable deterministic interpreter, Two sibling targets: ProgramModel and Interpreter, US-201 Program model value types and sibling targets, Interpreter target (+38 more)

### Community 13 - "Stitch Draw Plan"
Cohesion: 0.09
Nodes (20): DotRun, .count, .dottedIndices, Range<Int>, Bool, Int, PreviewStitch, Range (+12 more)

### Community 14 - "Package Products & Golden Glue"
Cohesion: 0.06
Nodes (3): EmbroideryEngine, InterpreterTargetIsolationTests, ProgramModel

### Community 15 - "Stage Canvas & Pan Directions"
Cohesion: 0.07
Nodes (27): AccessibilityAdjustmentDirection, StageCanvas, .body, .commitRecorder, Double, PreviewNeedle, Renderer, RunState (+19 more)

### Community 16 - "Draw Plan Coarsening"
Cohesion: 0.13
Nodes (11): Int, StitchDisplayList, StitchDrawPlanCoarseningCoverageTests, Bool, Int, StitchDisplayList, StitchDrawPlanCoarseningTests, Int (+3 more)

### Community 18 - "Bake Scheduling & Timing"
Cohesion: 0.12
Nodes (19): Any, BakeSchedulingTests, Duration, Int, StitchDisplayList, fastest(), milliseconds(), seconds() (+11 more)

### Community 19 - "Stage Transform Core"
Cohesion: 0.11
Nodes (18): Snapshot, Double, StageTransform, .affine, ViewSize, CGAffineTransform, CoreGraphics, StageGesture (+10 more)

### Community 20 - "Stage Transform Math"
Cohesion: 0.13
Nodes (7): StageTransform, Bool, Double, ViewPoint, .center, RepresentableScaleTests, Double

### Community 21 - "Stage & Manipulation ADRs"
Cohesion: 0.08
Nodes (36): Excluding build/ (measurement builds leave generated sources in the repo), Never edit *.pbxproj (synchronized folder groups), ADR-004 — Minimum iOS version: 17.0, ADR-028 — Zoom and pan: one commit per gesture, a fit-aware floor, and a summary only a transition may write, ADR-029 — The 50 000-stitch measurement: what was proved headlessly, what needs a device, and the fallback ladder, ADR-030 — Coarsening the mid-gesture plan: continuity over dashing, and two constants instead of one, ADR-031 — The manipulation layer: a recogniser pair over a pure tracker, and the terminal signal neither story had, coarseningStride, liveCoarseningThreshold and liveSegmentTarget (+28 more)

### Community 22 - "DST Semantics ADRs"
Cohesion: 0.11
Nodes (35): ADR-005 — DST semantics ported from Catroid, verified against Catty fixtures, ADR-007 — Stage coordinate space and physical units, ADR-012 — DST semantics: Catroid is authoritative; known Catty divergences are not ported, ADR-013 — Color-change flag placement follows Catroid; the golden is compared through a documented flag transposition, ADR-020 — The engine's coordinate boundary: encodable-delta trigger, guarded no-ops, Catroid-is-authoritative arbitration rule, EmbroideryStream, ±121-unit interpolation split rule (+27 more)

### Community 23 - "Zigzag Stitch Pattern"
Cohesion: 0.15
Nodes (27): GoldenRow, Double, ZigzagStitchPattern, accumulation(), astronomicalStitchCount(), degenerateLengths(), diagonalLine(), directionPersists() (+19 more)

### Community 24 - "Formula & Variable Scope"
Cohesion: 0.10
Nodes (11): Formula, binary, number, unaryMinus, variable, Double, Double, VariableScope (+3 more)

### Community 25 - "Stage Box & Fit Targets"
Cohesion: 0.11
Nodes (11): StageBox, .center, .height, .width, StageExtent, Double, StageGeometry, Double (+3 more)

### Community 26 - "Interpreter Events & Runs"
Cohesion: 0.12
Nodes (21): Interpreter, Bool, Double, Int, Bool, Double, InterpreterEvent, colorArmed (+13 more)

### Community 27 - "Repo Process & Review Docs"
Cohesion: 0.08
Nodes (33): ADR-as-arbiter finding triage, /codex-review — cross-vendor Codex review, codex exec stdin hang trap, Severity-trend stop condition, Codex verification round, /finish — session close-out checklist, Manual Ink/Stitch verification callout, Story close-out must be proved by grep (+25 more)

### Community 28 - "Canvas Stitch Strokes"
Cohesion: 0.15
Nodes (15): AnyHashable, .body, CanvasStitchStroke, Bool, CGSize, Double, Path, PreviewStitch (+7 more)

### Community 29 - "Export View Model"
Cohesion: 0.18
Nodes (9): DSTFileWriting, ExportViewModel, .name, EmbroideryStream, Result, RecordingDSTFileWriter, ExportViewModelTests, Data (+1 more)

### Community 30 - "Export Readiness & Control"
Cohesion: 0.08
Nodes (27): ExportControl, .hint, .isEnabled, .notice, .reasonsOwingAHint, .shareURL, Readiness, failed (+19 more)

### Community 31 - "Run View Model"
Cohesion: 0.14
Nodes (12): RunViewModel, EmbroideryStream, Program, RunUpdate, Void, NotificationCounter, RunViewModelTests, Double (+4 more)

### Community 32 - "Pattern Manager & Actors"
Cohesion: 0.18
Nodes (14): ActorID, ColorState, EmbroideryPatternManager, .hasEmittedOps, .hasValidPattern, EmittedPoint, LastCommand, LayerWorkspace (+6 more)

### Community 33 - "Manipulation Catcher"
Cohesion: 0.11
Nodes (15): Animatable, SettlingProgress, .animatableData, .body, Content, StageManipulationCatcher, Void, Hosted (+7 more)

### Community 34 - "Run State & Transport Row"
Cohesion: 0.08
Nodes (20): Animation, Appearance, RunControl, Bool, Double, LocalizedStringResource, StageMotion, Bool (+12 more)

### Community 35 - "SwiftUI Manipulation Wiring"
Cohesion: 0.08
Nodes (6): StageChrome, Double, StagePreviewRenderer, CGFloat, SwiftUI, UIKit

### Community 36 - "Brick Enum & Defaults"
Cohesion: 0.07
Nodes (29): Brick, changeVariableBy, changeXBy, changeYBy, forever, loopEnd, moveNSteps, placeAt (+21 more)

### Community 37 - "App Model & Selection"
Cohesion: 0.14
Nodes (12): AppModel, .samples, Bool, SampleProgram, .stage, StageDestination, stage, previewModelWithASelection() (+4 more)

### Community 38 - "Gesture Stubs & Recording"
Cohesion: 0.18
Nodes (13): CGPoint, .isDrawable, Bool, StageCatcherInputTests, StageCatcherLifecycleTests, CatcherHarness, .fit, Recording (+5 more)

### Community 39 - "DST File Name Sanitisation"
Cohesion: 0.13
Nodes (8): DSTFileNameProblem, empty, prohibitedCharacter, tooLongForFilesystem, Character, Int, Result, DSTFileNameTests

### Community 40 - "Preview Fixtures & Divergence"
Cohesion: 0.13
Nodes (16): DisplayVersusExportModelTests, interpreter(), PreviewColor, serializedTwoObjectProgram(), Int, tickBatches(), twoActorsOnOneLayerProgram(), twoLayersProgram() (+8 more)

### Community 41 - "Stage Fitting & View Size"
Cohesion: 0.17
Nodes (7): StageTransformDrawabilityTests, Double, ViewSize, StageFitBeyondGestureLimitTests, .fit, StageTransformTests, Double

### Community 42 - "Target Layout ADRs"
Cohesion: 0.11
Nodes (28): ADR-002 — Stack: native Swift 6 / SwiftUI, engine as SPM package, ADR-006 — App-layer architecture: @Observable MVVM, no TCA, ADR-010 — Device family: universal, iPhone-first, ADR-016 — M2 target layout: ProgramModel and Interpreter as two sibling targets, ADR-022 — M3 target layout: Samples and StagePreview as app-support targets in the engine package, ADR-023 — What runs where: the local gate protects engine semantics, the app target's protection is CI's, Sample 2 — square coil (triple stitch, two colours), SampleLibrary.all (+20 more)

### Community 43 - "Arithmetic & Threshold ADRs"
Cohesion: 0.09
Nodes (28): ADR-014 — Pattern-layer arithmetic is Double; sub-resolution divergence from Catroid's float accepted, ADR-017 — Formula arithmetic is native Double; decimal128 divergence and non-finite-literal semantics pinned, ADR-018 — Interpreter tick & clock semantics: one-action-per-tick round-robin, zero-tick loop bookkeeping, accumulating logical clock, ADR-019 — Structure-determining threshold crossings are a distinct class from coordinate tolerance, ADR-025 — Header field widths are a serialization error, not a trap; field emission order is a contract, DesignName and DSTFileName — two name types, DST header fixed-width fields and emission order, The ulp-distance screening rule for goldens (+20 more)

### Community 44 - "Stage Point & Traversal"
Cohesion: 0.14
Nodes (6): StagePoint, CoordinateConversionTests, Double, Int, TraversalPredicateTests, StageGeometryTests

### Community 45 - "DST File Assembly"
Cohesion: 0.13
Nodes (12): DSTFile, Data, UInt8, URL, DSTFileTests, Data, Double, EmbroideryStream (+4 more)

### Community 46 - "DST Stitch Record Codec"
Cohesion: 0.11
Nodes (13): DSTStitchRecord, Bool, Int, UInt16, UInt8, BitContribution, DecodedRecord, Bool (+5 more)

### Community 47 - "Stage Accessibility Strings"
Cohesion: 0.15
Nodes (5): StageAccessibility, Double, RunState, StageSummary, StageAccessibilityTests

### Community 48 - "Preview Stitch & Run Batch"
Cohesion: 0.13
Nodes (9): ArraySlice, PreviewStitch, PreviewNeedle, .liveTail, foldBatches(), FoldedRun, RunBatchTests, .stitches (+1 more)

### Community 49 - "Export & Lifecycle ADRs"
Cohesion: 0.11
Nodes (25): ADR-009 — Stage rendering: SwiftUI Canvas with batched paths, ADR-011 — Privacy: fully offline, no accounts, no tracking, ADR-015 — Set Thread Color emission: silent start, invalid-hex no-op, clause-B black, ==121 tie-off, ADR-021 — M3 preview data path: colour-resolved stitch events into an append-only display list, ADR-024 — The stage renderer: batching hoisted out of the renderer, and the deviations from both references, ADR-026 — DST export: the gate, the two name types, eager preparation, and the exported UTType, ADR-027 — The run lifecycle: two tasks, a terminal that cannot be forgotten, and three budget axes, Display list traces the program; export model traces the machine (+17 more)

### Community 50 - "Sample Programs & Budgets"
Cohesion: 0.11
Nodes (16): Hasher, Identifiable, SampleProgram, .descriptionKey, .displayName, .nameKey, .programJSONURL, .summary (+8 more)

### Community 51 - "Stepper Embroidery Runs"
Cohesion: 0.26
Nodes (3): Int, stitchPositions(), StepperEmbroideryTests

### Community 52 - "Golden Fixture Readers"
Cohesion: 0.09
Nodes (4): CoreTransferable, Foundation, SewUp, UniformTypeIdentifiers

### Community 53 - "Stage Zoom Bounds"
Cohesion: 0.13
Nodes (7): CGSize, ClosedRange, Double, StageGesture, StageZoomBounds, Double, StageZoomBoundsTests

### Community 54 - "DST Header & Field Errors"
Cohesion: 0.17
Nodes (7): DSTHeader, DSTSerializationError, fieldOverflow, Int, DSTFieldWidthChokepointTests, UInt8, Sequence

### Community 55 - "Running Stitch"
Cohesion: 0.21
Nodes (4): RunningStitch, StitchPattern, RunningStitchTests, Double

### Community 56 - "Golden Program Oracle"
Cohesion: 0.17
Nodes (23): actionBrickCount(), GoldenOp, activate, finalize, move, setColor, sewUp, turn (+15 more)

### Community 57 - "Synthetic 50k Design"
Cohesion: 0.11
Nodes (9): Brick, makeUS309SyntheticProgram(), rowPair(), Program, Program, Double, Int, StageBox (+1 more)

### Community 58 - "Design Name Validation"
Cohesion: 0.15
Nodes (4): .validatedName, Result, DesignNameTests, Character

### Community 59 - "Recogniser Coordinator"
Cohesion: 0.15
Nodes (11): Coordinator, Binding, Bool, Int, UIGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITapGestureRecognizer (+3 more)

### Community 60 - "Design Name Field Layout"
Cohesion: 0.11
Nodes (16): AnyLayout, Axis, DesignNameField, .arrangement, .body, .counter, .field, .title (+8 more)

### Community 61 - "Design Name Presentation"
Cohesion: 0.12
Nodes (12): .message, Character, LocalizedStringResource, DesignNamePresentationTests, DesignName, DesignNameProblem, empty, tooLong (+4 more)

### Community 62 - "Frame Time Readout"
Cohesion: 0.12
Nodes (14): FrameTimeReadout, .caption, .nominal, Double, .frameTimeReadout, String, .asComment, Comment (+6 more)

### Community 63 - "Sample Library Wiring"
Cohesion: 0.21
Nodes (7): ExportWiringTests, Bool, EmbroideryStream, Int, InterpreterDriver, SampleLibrary, SampleProgram

### Community 64 - "Program Model Builders"
Cohesion: 0.13
Nodes (7): Double, Variable, makeOctagonRosetteProgram(), coilLoop(), makeSquareCoilProgram(), Int, ProgramModelTests

### Community 66 - "Manipulation Wiring Tests"
Cohesion: 0.19
Nodes (13): Harness, Hosted, StageManipulationWiringTests, StubPinch, .state, StubTap, CGSize, StitchDisplayList (+5 more)

### Community 67 - "DST Header Tests"
Cohesion: 0.25
Nodes (6): .header, DSTHeaderTests, Double, EmbroideryStream, Int, UInt8

### Community 68 - "Running Stitch Pattern"
Cohesion: 0.24
Nodes (4): RunningStitchPattern, Double, RunningStitchPatternTests, Double

### Community 69 - "Sew-Up Bar Tack"
Cohesion: 0.26
Nodes (3): Double, SewUpTests, Double

### Community 70 - "Triple Stitch Pattern"
Cohesion: 0.24
Nodes (4): Double, TripleStitchPattern, Double, TripleStitchPatternTests

### Community 71 - "Golden Program Consumption"
Cohesion: 0.21
Nodes (4): eventTags(), recordPositions(), GoldenProgramSquareConsumptionTests, GoldenProgramStarConsumptionTests

### Community 72 - "Temporary DST File Writer"
Cohesion: 0.27
Nodes (6): URL, TemporaryDSTFileWriter, EmbroideryStream, URL, Void, TemporaryDSTFileWriterTests

### Community 73 - "Object & Codable Model"
Cohesion: 0.12
Nodes (13): SampleSelection, .program, Int, Codable, Equatable, StepOutcome, finished, ticked (+5 more)

### Community 74 - "DST Header Field Append"
Cohesion: 0.11
Nodes (18): Field, colorBlocks, endOffsetX, endOffsetY, extentMinusX, extentMinusY, extentPlusX, extentPlusY (+10 more)

### Community 75 - "Accessibility Memoisation"
Cohesion: 0.21
Nodes (11): DescriptionKey, Spoken, StageAccessibilityMemo, Double, RunState, StageSummary, Reading, StageAccessibilityMemoTests (+3 more)

### Community 76 - "Touch Tracking View"
Cohesion: 0.21
Nodes (9): StageTouchTrackingView, CGRect, Int, Set, Void, NSCoder, UIEvent, UITouch (+1 more)

### Community 77 - "Stage View Composition"
Cohesion: 0.12
Nodes (17): StageView, .canvasSlot, .emptyStage, .leavesTheHoop, .state, .unavailableView, Bool, PreviewNeedle (+9 more)

### Community 78 - "Needle Glyph Rendering"
Cohesion: 0.20
Nodes (6): Darwin, Glibc, NeedleGlyph, Double, NeedleGlyphTests, Double

### Community 79 - "US-307 Stage Screenshots"
Cohesion: 0.17
Nodes (18): Circular Back Button, Hoop Boundary Rectangle, Hoop Size Caption 100 mm x 100 mm, Navigation Title: Octagon Rosette, US-307 Screenshot: Mid-Drag Pan, Design Title Header (Octagon Rosette), Octagon Rosette Stitch Design, Pan (Drag) Gesture In Progress (+10 more)

### Community 80 - "Interpolation & Rounding"
Cohesion: 0.22
Nodes (3): InterpolationTests, EmbroideryStream, UInt8

### Community 81 - "Thread Color Hex"
Cohesion: 0.21
Nodes (5): Color, UInt16, UInt8, ThreadColor, ThreadColorHexTests

### Community 82 - "Golden Square Byte Runs"
Cohesion: 0.20
Nodes (8): InterpreterClock, finalizedDesignName(), GoldenProgramRun, runAndSerialize(), EmbroideryStream, InterpreterEvent, Program, GoldenSquareBytesTests

### Community 83 - "DST Header Field Types"
Cohesion: 0.14
Nodes (17): asciiField(), DSTHeaderField, colorBlocks, endOffsetX, endOffsetY, extentMinusX, extentMinusY, extentPlusX (+9 more)

### Community 84 - "Golden Square Programs"
Cohesion: 0.19
Nodes (5): polygonProgram(), GoldenProgramSquareTests, Bool, .displacedProgram, Bool

### Community 85 - "Export & Formula Errors"
Cohesion: 0.16
Nodes (9): ExportError, .message, serialization, writeFailed, Int, LocalizedStringResource, Error, FormulaError (+1 more)

### Community 86 - "Run Screen Screenshots"
Cohesion: 0.18
Nodes (16): Hoop Frame Outline (100 mm x 100 mm), Play Again Button, Fit-to-Content Zoom State, Hoop Bounds Rectangle (100 mm x 100 mm), Hoop Size Caption Label, US-307 Fit-to-Content Screenshot, Embroidery Stage / Run Screen, Terminal (Finished) Run State (+8 more)

### Community 87 - "Script Compiler Runtime"
Cohesion: 0.15
Nodes (14): Instruction, brick, foreverBegin, loopEnd, repeatBegin, ScriptCompiler, Int, .isFinished (+6 more)

### Community 88 - "Stitch Segment Style"
Cohesion: 0.18
Nodes (6): StitchSegmentStyle, suppressed, thread, traversal, Self, StitchSegmentStyleTests

### Community 89 - "CI Jobs & Lint Rules"
Cohesion: 0.16
Nodes (15): app-build-and-test job (xcodebuild), CI workflow, engine-tests job (swift test), Explicit -project and OS=latest destination, SwiftLint job, Shared-scheme precondition check, Pinned DEVELOPER_DIR toolchain, SwiftLint configuration (+7 more)

### Community 90 - "Project Guidance Docs"
Cohesion: 0.14
Nodes (15): Excluding .claude/worktrees (agent checkouts inside the repo), An ADR outranks any generated artifact (graph, index, summary), Graph drift check is defined by its output, not its effort, AGENTS.md — mirrored guidance for non-Claude agents, Journal append-only rule (AGENTS.md mirror), Two-layer review before handover, ADR-012 is the arbiter where references disagree, Cross-vendor review loop and its stop condition (+7 more)

### Community 91 - "Formula Evaluation Runtime"
Cohesion: 0.22
Nodes (6): Float, Double, VirtualNeedle, Double, Int, Scope

### Community 92 - "Interpolation Predicates"
Cohesion: 0.22
Nodes (5): Bool, Double, javaRound(), Double, Int

### Community 93 - "Sample Threshold Screening"
Cohesion: 0.16
Nodes (9): SampleID, octagonRosette, .resourceName, .shipping, squareCoil, us309Synthetic, SampleThresholdTests, Double (+1 more)

### Community 94 - "Stage Toggle & Pan"
Cohesion: 0.26
Nodes (3): StageToggleAndPanTests, Bool, Int

### Community 96 - "Export Control Readiness"
Cohesion: 0.22
Nodes (3): ExportControlTests, Bool, RunState

### Community 97 - "Interpreter Core Concepts"
Cohesion: 0.14
Nodes (14): Deterministic time, Catroid-faithful ticks, The needle is the object, NeedleUpdate (one per executed motion brick), VirtualNeedle (position, heading), Catroid ThreadScheduler (one act per sequence per tick), Interpreter value type (step/run/isFinished), InterpreterClock (injected logical tickDelta), InterpreterEvent enum (+6 more)

### Community 99 - "Stitch Draw Metrics"
Cohesion: 0.24
Nodes (5): StitchDrawMetrics, Double, Double, StitchDrawMetricsTests, Bool

### Community 100 - "Draw Plan Windowing"
Cohesion: 0.32
Nodes (3): StitchDrawPlanWindowTests, Int, StitchDisplayList

### Community 101 - "DST Round-Trip Decode"
Cohesion: 0.24
Nodes (7): DecodedDSTFile, DSTFileReader, Data, Int, UInt8, DSTRecordDecoder, DSTRoundTripTests

### Community 103 - "Golden Star Program Tests"
Cohesion: 0.24
Nodes (3): GoldenProgramStarTests, EmbroideryStream, InterpreterEvent

### Community 104 - "Threshold Screening Probe"
Cohesion: 0.25
Nodes (13): BoundaryProbe, .distanceIsExactlyOnBoundary, .isDecidedByLibm, emissionCountsPerMove(), needleMove(), screen(), Screening, .atRisk (+5 more)

### Community 105 - "Sample Picker View"
Cohesion: 0.21
Nodes (9): ButtonStyle, PickerRowButtonStyle, SamplePickerView, .body, SampleRowView, .body, Bool, SampleRowAccessibilityTests (+1 more)

### Community 106 - "Stage Field View"
Cohesion: 0.17
Nodes (9): StageFieldView, .body, CGRect, StageBox, Double, StageTransformCoreGraphicsTests, Bool, CGRect (+1 more)

### Community 107 - "DST File Writing Seam"
Cohesion: 0.21
Nodes (8): Failure, URL, ThrowingDSTFileWriter, Write, DSTFileName, .value, Set, Unicode

### Community 108 - "Coarsening Corner Rule"
Cohesion: 0.19
Nodes (5): Bool, PreviewStitch, StitchDrawPlanCoarseningRuleTests, Int, StitchDisplayList

### Community 110 - "Virtual Needle Brick Tests"
Cohesion: 0.22
Nodes (3): Bool, Double, VirtualNeedleBrickTests

### Community 111 - "DST Design & Export Row"
Cohesion: 0.17
Nodes (10): DSTDesign, URL, .transferRepresentation, StageExportRow, .body, .control, .title, .body (+2 more)

### Community 114 - "US-306 Accessibility Screenshots"
Cohesion: 0.24
Nodes (11): US-306 Screenshot: Stage at AX5 Dynamic Type, AX5 Accessibility Dynamic Type Setting, Hoop Size Label "Hoop 100 mm x 100 mm", Hoop Boundary Outline (100 mm x 100 mm), Manual Accessibility Pass Evidence (Dynamic Type), Play Again Button (Terminal Run State), Design Decision: Stage Keeps Its Area While Controls Grow, Embroidery Stage Screen (Square Coil) (+3 more)

### Community 115 - "Square Coil Screenshots"
Cohesion: 0.24
Nodes (11): Stitch Preview Canvas, US-306 Post-Run Stage Screenshot, Back Navigation Control, Program Title Header, Square Coil Spiral Design, Stage Screen (Square Coil), Run Lifecycle Terminal State (finished run), Two-Color Thread Change (orange / blue) (+3 more)

### Community 116 - "Octagon Rosette Screenshots"
Cohesion: 0.22
Nodes (11): Hoop Frame Outline, US-307 Screenshot ax5 — Stage at Accessibility Dynamic Type, Back Navigation Button, Completed Run Terminal State, Design Run Screen (Octagon Rosette), Accessibility Dynamic Type Size (AX5), Fit-to-Hoop Zoom Framing, Hoop Boundary Frame in Stage (+3 more)

### Community 117 - "iPad Sidebar Screenshots"
Cohesion: 0.22
Nodes (11): US-307 iPad Regular Size Class Screenshot, Octagon Rosette Example Design, Play Again Primary Action Button, Regular Size Class Adaptive Layout, Selected Design Checkmark Row, Example Designs Sidebar, Sidebar Toggle Toolbar Button, NavigationSplitView Two-Column Layout (+3 more)

### Community 118 - "Canvas Renderer Protocol"
Cohesion: 0.18
Nodes (11): CanvasStitchRenderer, Catty two-SKShapeNodes-per-stitch anti-goal, MetalStitchRenderer escape hatch, Per-colour-run path batching rule (≤ 2 stroked paths + 1 dot path), PreviewStitch, EmbroideryStream.requiresTraversal, StagePreviewRenderer protocol, StageView (generic over renderer) (+3 more)

### Community 119 - "Stage Summary Invariants"
Cohesion: 0.20
Nodes (11): Fit target union(stageRect, contentBounds), hoop unclipped, Hoop-overflow notice, Catty teardown-before-share hazard, Greenfield needle indicator, Producer-only cancellation (RunSession.stop), Terminal batch always carries assembledStream(), accessibilityAdjustableAction zoom + named Fit to Hoop action, Manual verification pass (pinch, VoiceOver, Reduce Motion, fit animation) (+3 more)

### Community 120 - "M3 Close-Out ADR Notes"
Cohesion: 0.20
Nodes (11): ADR-026 — DST export close-out, ExportEligibility — the exportModel.count > 1 gate, Per-session temp directory policy, Info.plist wiring canary (failable UTType lookup), Exported UTType org.catrobat.embroiderydesigner.dst, ADR-031 — the manipulation layer, The centroid-pan derivation (frozen start anchor is correct), StageManipulation (two-channel tracker value type) (+3 more)

### Community 121 - "Export After Stop"
Cohesion: 0.25
Nodes (6): DrainedRun, ExportAfterStopTests, Data, EmbroideryStream, Int, Program

### Community 122 - "Virtual Needle Tests"
Cohesion: 0.29
Nodes (3): Bool, Double, VirtualNeedleTests

### Community 123 - "Gesture Stub Doubles"
Cohesion: 0.20
Nodes (7): StubPinch, .state, StubTap, UIGestureRecognizer, UIView, UIPinchGestureRecognizer, UITapGestureRecognizer

### Community 124 - "Dual-Driver Workflow Docs"
Cohesion: 0.27
Nodes (10): AGENTS.md / CLAUDE.md parity rule, Codex CLI primitives (.codex/config.toml hooks, .codex/agents, .agents/skills), Dual-driver workflow plan (Claude Code / Codex CLI interchangeable), Shared hook scripts (scripts/hooks, scripts/review), Agent roster mapped to workflow phases; delegation boundary, Append-only journal rule, Codex cross-vendor review loop (/codex-review), Review-loop convergence stop rule (cap became a convergence test) (+2 more)

### Community 125 - "US-306 Stage Screenshots"
Cohesion: 0.22
Nodes (10): US-306 Stage Screen Screenshot (Dark Mode), Dark Mode Appearance State, Light Fabric Stage Kept Constant in Dark Mode, Play Again Primary Button, Program Title Header "Square Coil", Run Finished Terminal State, Square Coil Sample Program, Stage / Run Screen (+2 more)

### Community 126 - "Run State Revision Model"
Cohesion: 0.20
Nodes (10): Atomic tick batch (no global event bound), Catroid deltaActionTimeDivisor anti-throttle (do not port), InterpreterDriver, PreviewRunState (revision, settleChunk, visibleNeedle), RunBatch, RunBudget (ticksPerFrame, maxStitchesPerFrame, maxStitchesPerRun), RunPacing (Display / Immediate / gated doubles), RunState (idle | running | finished(reason)) (+2 more)

### Community 127 - "Byte Diff Reporting"
Cohesion: 0.29
Nodes (3): firstByteDifference(), UInt8, ByteDiffTests

### Community 128 - "Golden Square Manual Path"
Cohesion: 0.36
Nodes (5): goldenSquareFixture(), Data, GoldenSquareManualPathTests, Double, EmbroideryStream

### Community 129 - "Octagon Rosette Goldens"
Cohesion: 0.20
Nodes (3): OctagonRosetteGoldenTests, .measured, SampleRun

### Community 130 - "Binary Operator Enum"
Cohesion: 0.22
Nodes (7): CaseIterable, BinaryOperator, divide, minus, mult, plus, pow

### Community 131 - "Gated Run Pacing"
Cohesion: 0.31
Nodes (5): GatedPacing, Bool, CheckedContinuation, Never, Void

### Community 132 - "Dark Mode Screenshots"
Cohesion: 0.25
Nodes (9): US-307 Dark Mode Stage Screenshot, Dark Mode Appearance, Fabric-Neutral Stage in Dark Chrome, Fit-to-Hoop Zoom Baseline, Hoop Boundary 100 mm x 100 mm, Octagon Rosette Design, Embroidery Run/Preview Screen, Stitch Preview Stage Canvas (+1 more)

### Community 133 - "Display vs Export Model"
Cohesion: 0.25
Nodes (9): Display model ≠ export model (the normative rule), Catroid EmbroideryExportIsolationTest.kt, PreviewStitch, RunBatch.reducing(_:from:), StageGeometry (ADR-007's 500×500 stage in code), StagePreview target (Foundation-only library product), StageTransform, StitchDisplayList (+1 more)

### Community 134 - "Compensated Magnitude"
Cohesion: 0.31
Nodes (4): CompensatedMagnitudeTests, Double, Int, compensatedMagnitude()

### Community 135 - "Square Coil Goldens"
Cohesion: 0.22
Nodes (3): SquareCoilTests, .measured, SampleRun

### Community 136 - "Synthetic Design Builder"
Cohesion: 0.28
Nodes (7): Double, Int, PreviewStitch, ThreadColor, SyntheticDesign, .halfHeight, .halfWidth

### Community 137 - "App Root & Window Scene"
Cohesion: 0.29
Nodes (7): App, CatrobatEmbroideryApp, .body, WindowRootView, .body, RootView, .body

### Community 138 - "Run Session Async Stream"
Cohesion: 0.39
Nodes (5): AsyncStream, RunSession, Never, Task, Void

### Community 139 - "Stage Content State"
Cohesion: 0.25
Nodes (6): StageContentState, drawn, noSelection, notRun, Bool, Self

### Community 141 - "Export Error Semantics"
Cohesion: 0.25
Nodes (8): Run lifecycle enum correction — failed has no producer, appendField's precondition (deleted), DSTHeader.Field (the width table), DSTSerializationError.fieldOverflow(field:value:limit:), DSTDesign: Transferable + ShareLink, DSTFileWriting — the injected I/O seam, Eager preparation (ExportViewModel.prepare), ExportState (idle | ready(URL) | failed)

### Community 142 - "Frame Capture Instrument"
Cohesion: 0.29
Nodes (8): Quantiles over drawn frames only, FrameTimeRecorder readout capsule, Instruments Animation Hitches trace (required, not a cross-check), NO DRAWS verdict (measures the display, not the renderer), StitchDrawPlanScalingTests (headless per-draw independence proof), drawn=251 animating signature (mixed-capture detector), Display-link quantisation to multiples of the refresh period, -US310FrameTimes launch argument

### Community 143 - "DST Serialization Contract"
Cohesion: 0.25
Nodes (8): ADR-025 — throwing DST serialization, ADR-020's 1 000 000 interpolation cap stays, Field emission order is a contract, The fit-clamp inheritance and its correction, The reachability asymmetry of the header fields, DesignName (rejecting validator, printable ASCII, ≤15), DSTFileName (file-name sanitisation, independent of the header label), DSTHeader.sanitized(_:) — the mangling backstop

### Community 144 - "Raster & Buffering Policy"
Cohesion: 0.29
Nodes (8): Bridging-segment rule at the watermark, Catroid PenActor FrameBuffer stamp, Settled/live split with cached raster and settledCount watermark, Discarded run's buffered frames landing in the next run (Critical), Unbounded AsyncStream buffering, Simultaneous MagnifyGesture + DragGesture, committed once in onEnded, Mid-gesture raster policy (bake once per gesture, re-stroke per frame), StageRenderTransform (bake + current)

### Community 145 - "Stage Gesture Value"
Cohesion: 0.29
Nodes (5): StageGesture, .isIdentity, .pan, Bool, Double

### Community 149 - "Script Representation ADR"
Cohesion: 0.38
Nodes (7): ADR-008 — Script representation: flat brick list with paired control bricks, Flat scripts with paired control bricks, loopEnd pure marker retained in the model, matchingEnd / range(ofPairAt:) pair resolution, Move-a-pair-as-a-unit model primitive, Catty CBBackend (flatten-to-instructions precedent), Flat script compiled to linear instruction array with jump offsets

### Community 150 - "M3 Milestone Stories"
Cohesion: 0.52
Nodes (7): E4 Stage & preview, E7 Export & sharing, M3 — Walking skeleton app (E4 + E7, thin E6), US-211 — DST serialization field-width chokepoint, US-308 — Design name, DST export via share sheet, exported UTType, gating, US-313a — The manipulation is a package value, US-313b — Two fingers reach the stage

### Community 151 - "Run Lifecycle Screenshots"
Cohesion: 0.29
Nodes (7): US-306 Mid-Run Screenshot (Square Coil), Incremental Live Stitch Growth, Needle Position Cursor, Run Control Affordance (Run/Stop Toggle), Run Lifecycle State: Running, Square Spiral Stitch Path (Blue Thread), Primary Stop Button

### Community 152 - "Export Eligibility Reasons"
Cohesion: 0.29
Nodes (6): ExportEligibility, nothingEmbroiderable, nothingStitched, notRun, ready, singleStitch

### Community 153 - "Settling Phase Enum"
Cohesion: 0.33
Nodes (6): Phase, idle, settling, Bool, Double, Int

### Community 154 - "Manipulation Channel Enum"
Cohesion: 0.33
Nodes (6): Channel, absent, active, ended, .hasBegun, .isActive

### Community 155 - "DST Header Numeric Fields"
Cohesion: 0.60
Nodes (5): coField(), numericField(), stField(), Int, UInt8

### Community 157 - "UI Definition of Done"
Cohesion: 0.40
Nodes (5): Definition of done for every UI story (M3+), DesignNameFieldLayout.axis(for:) — the AX1 counter rule, panned(by:) and the double-tap fit ↔ 2× toggle, Four camera-relative directional pan accessibility actions, US-315 — canvas and hoop drift while the keyboard animates

### Community 158 - "Coarse Span Rules"
Cohesion: 0.40
Nodes (5): Deviation — jump traversals drawn distinctly from thread, Coarsen, do not dash, The coarse-span rule — thread only if every spanned unit segment is thread and both endpoints lie in one colour run, Per-run dot striding anchored at each colour run's own lowerBound, StitchDrawPlan.Segment — a drawn segment as an explicit index pair

### Community 160 - "SampleRunHarness.swift"
Cohesion: 0.50
Nodes (4): extentInMillimetres(), StageBounds, .extreme, Double

### Community 161 - "bracketedWaitProgram()"
Cohesion: 0.40
Nodes (5): bracketedWaitProgram(), oversizeProgram(), singleObjectProgram(), Double, waitProgram()

### Community 164 - "ADR-029 fallback ladder and the frame-"
Cohesion: 0.50
Nodes (4): ADR-029 fallback ladder and the frame-time measurement, liveSegmentTarget = 2000, AC13 A/B — the segment count is not the mid-gesture cost, Accessibility string memoisation on (summary, state, roundedPercent)

### Community 165 - "Mutation as the substitute for red whe"
Cohesion: 0.50
Nodes (4): Mutation as the substitute for red when every red is a compile failure, Wall-clock ratio bounds refuted by CI — ratios establish shape, not absolute cost, StitchDisplayListThroughputTests (16x step, k^1.5 bound), No wall-clock ratio written for coarse against entire

### Community 167 - "StageZoomAdjustment.swift"
Cohesion: 0.50
Nodes (3): StageZoomAdjustment, zoomIn, zoomOut

### Community 170 - "The .success exit test — proving red a"
Cohesion: 0.67
Nodes (3): The .success exit test — proving red against a trap, The already-green test item check, The restating-not-observing test risk

### Community 171 - "ADR-028 amendment — one commit per man"
Cohesion: 0.67
Nodes (3): ADR-028 amendment — one commit per manipulation, not per onEnded, The three recogniser lifecycle rules, The touch-counting view (missing terminal signal)

## Ambiguous Edges - Review These
- `Circular Back Button` → `Run Lifecycle State: Running`  [AMBIGUOUS]
  docs/screenshots/us-306/midrun.png · relation: conceptually_related_to
- `Hoop Boundary Rectangle` → `Pan (Drag) Gesture In Progress`  [AMBIGUOUS]
  docs/screenshots/us-307/mid-drag.png · relation: conceptually_related_to
- `Play Again Primary Action Button` → `Stage VoiceOver Run-State Summary`  [AMBIGUOUS]
  docs/screenshots/us-307/ipad-regular.png · relation: conceptually_related_to
- `Embroidery Stage Screen (iPad)` → `Stage VoiceOver Run-State Summary`  [AMBIGUOUS]
  docs/screenshots/us-307/ipad-regular.png · relation: conceptually_related_to
- `Embroidery Stage Screen (Square Coil)` → `Two-Color Stitch Rendering (Orange / Blue Thread Change)`  [AMBIGUOUS]
  docs/screenshots/us-306/ax5_real.png · relation: conceptually_related_to
- `Stitch Preview Canvas` → `Run Lifecycle Terminal State (finished run)`  [AMBIGUOUS]
  docs/screenshots/us-306/postrun.png · relation: conceptually_related_to
- `Hoop 100 mm x 100 mm Label` → `Stitch Preview Stage`  [AMBIGUOUS]
  docs/screenshots/us-307/ax5.png · relation: shares_data_with
- `Play Again Button` → `Octagon Rosette Design`  [AMBIGUOUS]
  docs/screenshots/us-307/dark.png · relation: shares_data_with
- `Run-In-Progress Stage State` → `VoiceOver Run-State Summary`  [AMBIGUOUS]
  docs/screenshots/us-307/midrun.png · relation: conceptually_related_to
- `Embroidery Stage / Run Screen` → `Terminal (Finished) Run State`  [AMBIGUOUS]
  docs/screenshots/us-307/fit.png · relation: conceptually_related_to

## Knowledge Gaps
- **332 isolated node(s):** `StagePreviewRenderer`, `.description`, `.hasEmittedOps`, `.hasValidPattern`, `finished` (+327 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **43 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Circular Back Button` and `Run Lifecycle State: Running`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Hoop Boundary Rectangle` and `Pan (Drag) Gesture In Progress`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Play Again Primary Action Button` and `Stage VoiceOver Run-State Summary`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Embroidery Stage Screen (iPad)` and `Stage VoiceOver Run-State Summary`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Embroidery Stage Screen (Square Coil)` and `Two-Color Stitch Rendering (Orange / Blue Thread Change)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Stitch Preview Canvas` and `Run Lifecycle Terminal State (finished run)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Hoop 100 mm x 100 mm Label` and `Stitch Preview Stage`?**
  _Edge tagged AMBIGUOUS (relation: shares_data_with) - confidence is low._