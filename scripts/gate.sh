#!/usr/bin/env bash
# One-shot quality gate: every debt guard, then swift build, then swift test.
# Any failure -> non-zero exit. Installed as .git/hooks/pre-commit by scripts/install_hooks.sh.
set -uo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

status=0
declare -a results=()

run_step() {
  local name="$1"; shift
  echo "=== $name ==="
  if "$@"; then
    results+=("PASS  $name")
  else
    results+=("FAIL  $name")
    status=1
  fi
  echo
}

for guard in scripts/guards/[0-9][0-9]_*; do
  case "$guard" in
    *.py) run_step "$(basename "$guard")" python3 "$guard" ;;
    *.sh) run_step "$(basename "$guard")" bash "$guard" ;;
  esac
done

run_step "swift build" swift build
run_step "swift test" swift test

echo "=== gate summary ==="
printf '%s\n' "${results[@]}"
if [ "$status" -eq 0 ]; then
  echo "GATE: PASS"
else
  echo "GATE: FAIL"
fi
exit "$status"
