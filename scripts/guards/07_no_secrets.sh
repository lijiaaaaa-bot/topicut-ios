#!/usr/bin/env bash
# Guard 07 — no secrets in the repository (debt: key leakage; supports the No Fallbacks rule
# by making the environment variable the *only* place a key can live).
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

failures=0
patterns=(
  'sk-[A-Za-z0-9]{16,}'
  'DEEPSEEK_API_KEY\s*=\s*["\x27]?sk-'
  'DEEPSEEK_API_KEY\s*=\s*["\x27]?[A-Za-z0-9]{20,}'
  'BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY'
)
for pattern in "${patterns[@]}"; do
  if matches=$(rg -n --hidden --glob '!.git' --glob '!.build' --glob '!artifacts' -e "$pattern" . 2>/dev/null); then
    echo "FAIL: pattern '$pattern' matched:" >&2
    echo "$matches" >&2
    failures=$((failures + 1))
  fi
done

if git ls-files --error-unmatch .env >/dev/null 2>&1; then
  echo "FAIL: .env is tracked by git" >&2
  failures=$((failures + 1))
fi
if [ -e .env ]; then
  echo "FAIL: a .env file exists in the working tree; this project reads DEEPSEEK_API_KEY from the shell only" >&2
  failures=$((failures + 1))
fi

echo "guard 07 no_secrets: ${#patterns[@]} patterns, failures=$failures"
[ "$failures" -eq 0 ]
