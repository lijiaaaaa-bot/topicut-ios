# EDL (Edit Decision List) JSON — schema_version 1

The EDL is the contract between the slicing decision (this package) and any renderer.
Producer: `EDLDocument.encode()`. Consumer: `EDLDocument.decode(_:)`. Keys are snake_case, sorted.

## Compatibility rules

1. `schema_version` is a required top-level integer. Decoders MUST refuse a document whose
   version they do not know (`EDLDocumentError.unsupportedSchemaVersion`) and one without the
   key (`EDLDocumentError.missingSchemaVersion`). Never guess.
2. Adding an **optional** field is backward compatible and does not bump the version.
   Decoders ignore unknown keys.
3. Any breaking change (removing/renaming a field, changing a type or semantics, making an
   optional field required) bumps `schema_version` by 1 and gets a CHANGELOG entry plus an update
   to `schema_version_of_edl` in `docs/ARCHITECTURE.yaml`.
4. A decoder that wants to read older versions must implement an explicit migration per version;
   until it does, older versions are rejected, not approximated.

## Document

| key | type | notes |
| --- | --- | --- |
| `schema_version` | int | always `1` for this version |
| `generated_at` | string | ISO-8601 UTC, e.g. `2026-09-06T14:00:00Z` |
| `strategy` | object | `mode`, `domain`, `duration_ranges[]`, `max_transcript_chars` — the `SlicingStrategy` used |
| `clip_count_policy` | object | `duration_minutes`, `min_clips`, `max_clips`, `hard_max_clips` |
| `transcript` | object | `cue_count`, `start_sec`, `end_sec` of the source SRT |
| `clips` | array | see below; may be empty only if the LLM returned zero slices (which currently is an error) |
| `llm` | object? | **optional, added 2026-09-06 without a version bump** (rule 2). `model`, `prompt_tokens`, `completion_tokens`, `total_tokens`, `latency_ms`, and (optional, added 2026-09-07, rule 2) `prompt_cache_hit_tokens` — the prompt tokens the server billed at its cache-hit rate; present only when the server reports it (DeepSeek does). Absent in documents written before the field existed; decoders get `nil`. Producers must fill it: a DeepSeek response without `usage` is an error, never zero-filled. |

## Clip

| key | type | notes |
| --- | --- | --- |
| `id` | string | `<framework_id>_c_<NN>` |
| `title` | string | non-empty |
| `reason` | string | why this topic is publishable |
| `start` / `end` | string | `HH:MM:SS.mmm`, equal to first segment start / last segment end |
| `start_sec` / `end_sec` | number | seconds, 3 decimals, same values as above |
| `score` | number | 0.0 … 1.0 |
| `tags` | string[] | |
| `category` | string? | one of the topic categories in the prompt (e.g. 观点论述, 深度解读, 战情动态, etc.) |
| `framework_id` / `framework_title` | string | the topic block the clip belongs to |
| `mode` | string | `continuous` (1 segment) or `compressed_concat` (n segments) |
| `segments` | segment[] | kept ranges, ordered, non-overlapping, each `end > start`, at least one |
| `removed_segments` | segment[] | removed ranges (quiz, interaction); may be empty |

## Segment

| key | type | notes |
| --- | --- | --- |
| `start` / `end` | string | `HH:MM:SS.mmm` |
| `start_sec` / `end_sec` | number | seconds |
| `reason` | string? | `keep_reason` for kept segments, `reason` for removed ones in the LLM output; unified here |

## Invariants enforced on encode and decode

- every range has `end > start`
- segments (and removed segments) are sorted ascending and do not overlap within their own list
- clip outer boundary equals its segments' boundary
- every removed segment lies inside the clip's outer boundary (±1 ms) and does not intersect any
  kept segment (touching an edge is allowed) — `removedSegmentOutsideClip` / `removedOverlapsKept`
- `score` within `[0, 1]`, `mode` within the allowed set, `title` non-empty

Violations are errors for the whole run; nothing is trimmed or dropped to "make it fit".

Not validated on decode (tracked as risk): kept segments outside the subtitle range are checked
only in `TopicSlicer` (±0.5 s), because a bare EDL does not carry the subtitle bounds' authority.
