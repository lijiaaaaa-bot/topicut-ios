#!/usr/bin/env bash
# Guard 02 — no silent fallback (debt type 3).
# Forbidden in Sources/: `try?`, `try!`, empty `catch {}`, and `?? <literal>` defaults.
# Per-line exception: append `// guard-allow: silent-fallback <reason>` (reason required).
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

ALLOW='// guard-allow: silent-fallback [^ ]+'
failures=0

report() {
  # $1 = label, stdin = rg output lines "file:line:text"
  local label="$1" line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local text="${line#*:*:}"
    # skip pure comment lines
    if [[ "$text" =~ ^[[:space:]]*// ]]; then continue; fi
    if [[ "$text" =~ $ALLOW ]]; then
      echo "allowed ($label): $line"
      continue
    fi
    echo "FAIL ($label): $line" >&2
    failures=$((failures + 1))
  done
}

report 'try?' < <(rg -n --no-heading 'try\?' Sources || true)
report 'try!' < <(rg -n --no-heading 'try!' Sources || true)
report 'empty catch' < <(rg -nU --no-heading 'catch\s*\{\s*\}' Sources || true)
report '?? literal' < <(rg -n --no-heading '\?\?\s*("|\x27|-?[0-9]|\[|true\b|false\b|nil\b)' Sources || true)

echo "guard 02 no_silent_fallback: failures=$failures"
[ "$failures" -eq 0 ]
