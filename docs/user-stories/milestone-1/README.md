# Milestone 1 — Engine core

**Status**: Done — 2026-07-16. All ten stories merged (PRs #1–#15); exit criterion met (US-106 golden-file tests green in CI; generated DST verified in Ink/Stitch, workflow journal 2026-07-09).

Goal: a pure Swift package (`EmbroideryEngine`) that turns needle movements into a valid Tajima DST file, byte-verified against reference fixtures. No UI. See [ROADMAP.md](../../ROADMAP.md).

Every story is developed test-first: the tests listed in its "Test-first plan" are written and red before implementation starts.

Where the Catroid and Catty references disagree at byte level, **ADR-012 in [DECISIONS.md](../../DECISIONS.md) is the arbiter** (Catroid wins; known Catty bugs are listed there) — never "fix" a red golden test by consulting the other reference. The tightest estimates are US-103 and US-106; both stories carry their specific mitigations (verbatim table port; hex-diff test helper).

| Story | Title | Est. | Depends on |
|-------|-------|------|------------|
| [US-101](US-101-project-scaffold-and-ci.md) | Project scaffold, SPM package and CI | ~4 h | — |
| [US-102](US-102-stitch-model-and-stream.md) | Stitch domain model and embroidery stream | ~3 h | US-101 |
| [US-103](US-103-dst-record-encoder.md) | DST stitch record encoder | ~5 h | US-102 |
| [US-104](US-104-dst-header-writer.md) | DST header writer | ~4 h | US-102 |
| [US-105](US-105-interpolation-and-jumps.md) | Long-move interpolation and jumps | ~3 h | US-102, US-103 |
| [US-106](US-106-dst-file-generator-golden.md) | DST file generator + golden-file verification | ~4 h | US-103–105 |
| [US-107](US-107-running-stitch-pattern.md) | Running stitch pattern | ~3 h | US-102 |
| [US-108](US-108-zigzag-stitch-pattern.md) | Zigzag stitch pattern | ~3 h | US-107 |
| [US-109](US-109-triple-stitch-and-sew-up.md) | Triple stitch pattern and sew-up | ~3 h | US-107 |
| [US-110](US-110-thread-color-and-layers.md) | Thread color changes and layer assembly | ~3 h | US-102, US-103 |

**Total: ~35 h.** Suggested order: 101 → 102 → 103 → 104 → 105 → 106 (exit criterion reachable here) → 107 → 108/109/110 in any order.

**Milestone exit criterion**: US-106's golden-file test is green in CI and a generated `.dst` opens correctly in an embroidery viewer.
