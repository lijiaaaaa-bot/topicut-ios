# Changelog

All notable changes to this project. Format: Keep a Changelog; versioning: SemVer.
EDL `schema_version` changes are listed under their own heading in each release.

## [Unreleased]

### Added
- BYOK (Bring Your Own Key) open source model formalized with MIT License (`LICENSE`),
  explicit security documentation in `README.md`, and ADR-0007 in `docs/DECISIONS.md`.
- `LLMUsage` (model, prompt/completion/total tokens, latency_ms) returned by `DeepSeekClient` and
  stored in the EDL as optional `llm`; a DeepSeek response without `usage` is now an error.
  `liveslice-cli` prints a `tokens:` line. Cost baseline for prompt/model iteration.
- `EDLClip` invariants: removed segments must lie inside the clip and never overlap kept segments
  (`removedSegmentOutsideClip`, `removedOverlapsKept`). Whole run fails; no trimming.
- Prompt rule: `removed_segments` only records gaps inside the slice, not content outside it.

### EDL schema
- `schema_version` stays 1: `llm` is an optional addition (see `docs/EDL_SCHEMA.md` rule 2).
  Documents without `llm` decode with `nil`.

## [0.1.0] — 2026-09-06

### Added
- `LiveSliceCore` (Swift package, iOS 26 / macOS 26): `Timecode`, `SRTParser`, `SlicingStrategy`
  (`topic_complete + military_news` default with duration-adaptive clip counts),
  `TopicCompletePrompt` (ported from live_slice_auto), `DeepSeekClient` (URLSession, key only from
  `DEEPSEEK_API_KEY`), `LLMResponseParser`, `EDLClip`, `EDLDocument`, `TopicSlicer`.
- `liveslice-cli slice <srt> [--out edl.json]` — the real caller of the core.
- 46 offline unit tests (Swift Testing); no network in tests.
- Debt guards `scripts/guards/01…08` and `scripts/gate.sh`; pre-commit hook installer.
- Docs: `ARCHITECTURE.yaml`, `DEBT_REGISTER.md`, `DECISIONS.md` (ADR-0001…0006), `EDL_SCHEMA.md`.

### EDL schema
- `schema_version` 1 introduced. See `docs/EDL_SCHEMA.md`.
