// The Interpreter target is the only place the program model and the embroidery
// engine meet (ADR-016): it maps `ProgramModel` objects onto engine actors
// (object → `ActorID`, `zIndex` → layer), converts plain `Double` positions to
// `StagePoint`, and parses hex color strings via `ThreadColor(hexString:)`.
// Execution machinery lands from US-204 on; until then this target exists to pin
// the dependency direction — `Interpreter` depends on `ProgramModel` and
// `EmbroideryEngine`, never the reverse.
