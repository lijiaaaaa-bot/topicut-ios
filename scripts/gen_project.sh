#!/usr/bin/env bash
# Regenerates LiveSlice.xcodeproj from project.yml (the .xcodeproj is git-ignored).
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
command -v xcodegen >/dev/null || { echo "xcodegen not installed (brew install xcodegen)" >&2; exit 1; }
xcodegen generate --spec project.yml
