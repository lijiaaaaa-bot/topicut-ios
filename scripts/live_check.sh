#!/usr/bin/env bash
# Real DeepSeek run through the CLI (the only network path in this repo).
# Requires DEEPSEEK_API_KEY in the environment; exits 2 with a clear message otherwise.
# Output EDL goes to artifacts/live_check/ (gitignored).
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "error: DEEPSEEK_API_KEY is not set in this shell; live check not run (no offline substitute exists)." >&2
  exit 2
fi

input="${1:-Fixtures/sample_military_news.srt}"
mkdir -p artifacts/live_check
out="artifacts/live_check/edl_$(date +%Y%m%d_%H%M%S).json"

swift build --product liveslice-cli
started=$(date +%s)
swift run --skip-build liveslice-cli slice "$input" --out "$out"
echo "live check OK in $(( $(date +%s) - started ))s -> $out"
