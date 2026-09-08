#!/usr/bin/env bash
# Guard 09 — no self-reference in the UI (debt type 9: decorative / redundant copy, ADR-0012).
# The product name lives in project.yml (display name) and the icon. Sources/ and App/ must not
# print it, and must not carry taglines or "welcome" copy. UI text is an action label or a real
# state value; everything else is noise the user has to read past.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

failures=0
report() {
  local label="$1" line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local text="${line#*:*:}"
    if [[ "$text" =~ ^[[:space:]]*// ]]; then continue; fi
    echo "FAIL ($label): $line" >&2
    failures=$((failures + 1))
  done
}

# Product / brand names as user-visible strings.
report 'product name in UI' < <(rg -n --no-heading '"[^"]*(片刻|LiveSlice|Pianke|Topicut)[^"]*"' Sources App --glob '*.swift' || true)
# Greeting / slogan / self-description copy.
report 'slogan copy' < <(rg -n --no-heading '"[^"]*(欢迎|Welcome|一键|轻松|智能|AI 驱动|让你|帮你|只需)[^"]*"' Sources App --glob '*.swift' || true)
# Labels that restate the value next to them ("标签：", "来源：", "时长："). Error prefixes
# ("保存密钥失败：…") name the operation that failed and are information, so they are exempt.
report 'restating label' < <(rg -n --no-heading '"[^"]*[\p{Han}A-Za-z]+：\\\(' Sources App --glob '*.swift' | rg -v '失败|错误|无法' || true)

echo "guard 09 no_self_reference: failures=$failures"
[ "$failures" -eq 0 ]
