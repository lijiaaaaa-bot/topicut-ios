# Debt Register — debt type → guard → trigger → exception

Source of the debt taxonomy: the 2026-09-06 debt audit of the `math-anything` project (intent-lab).
Every guard runs from `scripts/gate.sh`; any failure makes the gate (and the pre-commit hook) fail.

| # | Debt type | Guard | Fails when | Exception mechanism |
| --- | --- | --- | --- | --- |
| 1 | Dead code / lava flow | `scripts/guards/01_no_orphan_sources.py` | an `implemented` path or `called_by` path in `docs/ARCHITECTURE.yaml` does not exist; a `Sources/**/*.swift` is not registered; a `public` type is referenced in no other file | files containing `@main` skip the public-type check; nothing else |
| 2 | Speculative generality / YAGNI | `01_no_orphan_sources.py` (same guard, `called_by` + reference check) and `docs/ARCHITECTURE.yaml` `planned` bucket | code exists without a listed caller | put the idea in `planned`, not in code |
| 3 | Silent fallback | `scripts/guards/02_no_silent_fallback.sh` | `try?`, `try!`, empty `catch {}`, or `?? <literal>` in `Sources/` | same-line `// guard-allow: silent-fallback <reason>`; reason mandatory; comment-only lines ignored |
| 4 | God object / magic numbers / duplicate models | `scripts/guards/03_no_god_object.py` | any Swift file > 300 lines; any `func`/`init` body > 60 lines (strings & comments stripped) | none — split the file/function |
| 5 | Test file name ≠ content / orphan tests | `scripts/guards/04_test_name_consistency.py` | `XxxTests.swift` does not declare `XxxTests`; a source file has no `<Name>Tests.swift` | `test_exempt: true` + `test_exempt_reason` on the source entry in `ARCHITECTURE.yaml` |
| 6 | Binaries in git | `scripts/guards/05_no_binaries.sh` | any tracked/staged/untracked-not-ignored file > 512 KB; blocked extension (`mp4 mov png jpg bin mlmodelc zip …`); `.gitignore` lacks a required pattern | files under a `Resources/` dir smaller than 200 KB |
| 7 | Documentation drift | `scripts/guards/06_docs_drift.py` + `docs/tech_terms.txt` | a term in README/AGENTS/CHANGELOG/docs is written as present but is `planned` / `not_used` in `ARCHITECTURE.yaml`; term list and yaml buckets disagree | write the marker inline, e.g. `Foo (planned)`, `ffmpeg (not used)` |
| — | Secrets in repo (enabler for No Fallbacks) | `scripts/guards/07_no_secrets.sh` | key-like strings, `DEEPSEEK_API_KEY=<value>` with a real-looking value, private key blocks, a tracked or present `.env` | none |
| 8 | Comprehension debt / orphaned intent | `scripts/guards/08_intent_present.py` | a source file lacks `// Why:` in its first 3 lines; `docs/DECISIONS.md` lacks ADR format or a required topic (多租户 / 端侧 / schema_version / 竖切片 / fallback) | none — write the ADR |
| 9 | Redundant / self-referential UI copy | `scripts/guards/09_no_self_reference.sh` | a user-visible string in `Sources/` or `App/` contains the product name (`Topicut`, `片刻`, `LiveSlice`, `Pianke`), slogan words (欢迎 / 一键 / 轻松 / 智能 …), or a label that restates the value it prefixes (`标签：\(…)`) | error prefixes that name the failed operation (`…失败：`) are exempt; the product name lives only in `project.yml` and the icon |

## Known limitations of the guards (honest scope)

- Guard 01's reference check is textual (`rg`-style word match), not semantic: a type mentioned
  only in a comment elsewhere would pass. It catches the "1000 lines nobody calls" case, not
  every subtle one.
- Guard 03's function-length counter is brace-based on stripped text; unusual formatting (braces
  in raw string literals `#"..."#`) could confuse it.
- Guard 06 only knows the words in `docs/tech_terms.txt`. Add a term the moment it enters a doc.
- Guard 05 scans what `git add -A` would pick up; it cannot see files already ignored.
- None of these replace a human reading the code. They make the known failure modes loud.

## How to add a new guard

1. Create `scripts/guards/NN_<name>.py|sh`, print a one-line summary, exit non-zero on failure.
2. Add a row above with trigger and exception.
3. Run `bash scripts/gate.sh` and prove the guard turns red on a deliberate violation before relying on it.
