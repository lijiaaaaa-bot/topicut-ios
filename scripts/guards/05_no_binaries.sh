#!/usr/bin/env bash
# Guard 05 — no binaries in git (debt type 6).
# Scans tracked + staged + untracked-not-ignored files (i.e. everything `git add -A` would take):
#   - any file > 512 KB fails
#   - blocked extensions fail, except files under a Resources/ directory smaller than 200 KB
#   - .gitignore must contain the required patterns
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

MAX_BYTES=$((512 * 1024))
RESOURCE_MAX_BYTES=$((200 * 1024))
BLOCKED_EXT='mp4|mov|m4v|mkv|png|jpg|jpeg|gif|bin|mlmodelc|mlmodel|mlpackage|zip|gz|tar|7z|dmg|pdf|wav|mp3|m4a|aac|ttf|otf'
REQUIRED_IGNORES=('artifacts/' '*.mp4' '.build/' '*.xcuserdata' '.env' 'DerivedData/' '*.mlmodelc' '*.mlmodel' '*.mlpackage' '*.bin')

failures=0
count=0
while IFS= read -r -d '' file; do
  [ -f "$file" ] || continue
  count=$((count + 1))
  size=$(stat -f %z "$file")
  if [ "$size" -gt "$MAX_BYTES" ]; then
    echo "FAIL: $file is $size bytes (> $MAX_BYTES)" >&2
    failures=$((failures + 1))
  fi
  ext="${file##*.}"
  if [[ "$file" == *.* ]] && [[ "$ext" =~ ^($BLOCKED_EXT)$ ]]; then
    if [[ "$file" == */Resources/* ]] && [ "$size" -lt "$RESOURCE_MAX_BYTES" ]; then
      echo "allowed resource: $file ($size bytes)"
    else
      echo "FAIL: $file has blocked extension .$ext" >&2
      failures=$((failures + 1))
    fi
  fi
done < <( { git ls-files -z; git ls-files -z --others --exclude-standard; git diff --cached --name-only -z; } | sort -zu)

if [ ! -f .gitignore ]; then
  echo "FAIL: .gitignore missing" >&2
  failures=$((failures + 1))
else
  for pattern in "${REQUIRED_IGNORES[@]}"; do
    if ! grep -qxF -- "$pattern" .gitignore; then
      echo "FAIL: .gitignore lacks required pattern '$pattern'" >&2
      failures=$((failures + 1))
    fi
  done
fi

echo "guard 05 no_binaries: scanned $count files, failures=$failures"
[ "$failures" -eq 0 ]
