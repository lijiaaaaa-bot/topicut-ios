#!/usr/bin/env python3
"""Guard 08 — intent must not go missing (debt type 8: comprehension debt / orphaned intent).

  - every Sources/**/*.swift starts with a `// Why:` line within its first 3 lines
  - docs/DECISIONS.md is a list of short ADRs (`## ADR-NNNN <title>`), each with
    `- 状态:`, `- 决策:`, `- 理由:` lines, and the required topics are covered
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from arch_yaml import ROOT, fail  # noqa: E402

REQUIRED_TOPICS = {
    "multi-tenant backend rejected": r"多租户",
    "on-device ASR": r"端侧",
    "EDL schema_version": r"schema_version",
    "single vertical slice first": r"竖切片",
    "no fallback": r"[Ff]allback",
}
ADR_HEADING = re.compile(r"^## (ADR-\d{4}) (.+)$", re.MULTILINE)
REQUIRED_FIELDS = ("- 状态:", "- 决策:", "- 理由:")


def main() -> int:
    failures = 0
    sources = sorted((ROOT / "Sources").rglob("*.swift"))
    for path in sources:
        head = path.read_text(encoding="utf-8").splitlines()[:3]
        if not any(line.startswith("// Why:") for line in head):
            fail(f"{path.relative_to(ROOT).as_posix()} lacks a '// Why:' header line")
            failures += 1

    decisions_path = ROOT / "docs" / "DECISIONS.md"
    if not decisions_path.exists():
        fail("docs/DECISIONS.md missing")
        return 1
    text = decisions_path.read_text(encoding="utf-8")
    headings = list(ADR_HEADING.finditer(text))
    if not headings:
        fail("docs/DECISIONS.md has no '## ADR-NNNN <title>' entries")
        failures += 1

    ids = [m.group(1) for m in headings]
    if len(ids) != len(set(ids)):
        fail(f"duplicate ADR ids: {ids}")
        failures += 1

    for index, match in enumerate(headings):
        end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
        body = text[match.end():end]
        for field in REQUIRED_FIELDS:
            if field not in body:
                fail(f"{match.group(1)} lacks '{field}'")
                failures += 1

    heading_text = "\n".join(m.group(2) for m in headings)
    for label, pattern in REQUIRED_TOPICS.items():
        if not re.search(pattern, heading_text):
            fail(f"no ADR heading covers required topic: {label} (regex {pattern})")
            failures += 1

    print(f"guard 08 intent_present: {len(sources)} sources with Why headers, {len(headings)} ADRs, failures={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
