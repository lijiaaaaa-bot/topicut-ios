# Agent Entry Rules — liveslice-ios

## Read first, in this order

1. `docs/ARCHITECTURE.yaml` — what exists (`implemented`), what is decided but unwritten
   (`planned`), what is out of scope for this codebase shape (`requires_new_architecture`).
2. `docs/DEBT_REGISTER.md` — the debt types this repo defends against and the guard for each.
3. `docs/DECISIONS.md` — ADRs. If you are about to make a non-obvious choice, add one.

## Three buckets, one vocabulary

When describing capabilities anywhere (code comments, docs, chat), say which bucket:
`implemented now` / `planned now` / `requires new architecture`. Never describe `planned` as if it
exists. Guard 06 enforces this for technology names in docs via the `(planned)` marker.

## No Fallbacks

- No mock data, demo output, cached output or downgraded path when the real path fails.
- Missing `DEEPSEEK_API_KEY`, non-2xx HTTP, unparsable or invalid LLM output, `end <= start`
  ranges: throw a typed error and stop. The CLI exits non-zero with the exact reason.
- A guard, test or gate is never marked PASS on fallback output.

## Every file has a caller

Do not add a Swift file unless something in `Sources/` (or `scripts/`) calls it today. Register it
in `docs/ARCHITECTURE.yaml` with `called_by`, and add `Tests/**/<Name>Tests.swift`. Ideas for later
go in the `planned` section, not in code. No protocols or abstraction layers "for the future".

## Workflow

- Run `bash scripts/gate.sh` before and after any change; it is also the pre-commit hook
  (`bash scripts/install_hooks.sh` after cloning).
- Real DeepSeek run: `bash scripts/live_check.sh` (requires `DEEPSEEK_API_KEY` in the shell).
- Do not commit, push, reset, or rewrite history unless the user explicitly asks for that git action.
- Do not install tools (brew/pip/npm) unless the user explicitly asks.
- EDL schema changes follow `docs/EDL_SCHEMA.md` and get a `CHANGELOG.md` entry.
- `topic_complete` is the core slicing mode; `general` is the default domain, with `military_news` preserved as an optional preset.
