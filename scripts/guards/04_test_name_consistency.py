#!/usr/bin/env python3
"""Guard 04 — test file names match contents; every source has a test twin (debt type 5).

  - Tests/**/XxxTests.swift must declare a type named XxxTests
  - Sources/**/Foo.swift must have Tests/**/FooTests.swift, unless ARCHITECTURE.yaml marks the
    source `test_exempt: true` with a `test_exempt_reason`
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from arch_yaml import ROOT, fail, implemented_entries, load  # noqa: E402


def main() -> int:
    failures = 0
    test_files = sorted((ROOT / "Tests").rglob("*Tests.swift"))
    test_names = {p.stem for p in test_files}

    for path in test_files:
        rel = path.relative_to(ROOT).as_posix()
        expected = path.stem
        pattern = re.compile(rf"\b(?:struct|final class|class|enum|actor)\s+{re.escape(expected)}\b")
        if not pattern.search(path.read_text(encoding="utf-8")):
            fail(f"{rel} does not declare a type named {expected} (file name lies about its content)")
            failures += 1

    exempt: dict[str, dict] = {}
    for entry in implemented_entries(load()):
        if entry.get("test_exempt"):
            if not entry.get("test_exempt_reason"):
                fail(f"{entry['path']} is test_exempt without test_exempt_reason")
                failures += 1
            exempt[entry["path"]] = entry

    sources = sorted((ROOT / "Sources").rglob("*.swift"))
    for path in sources:
        rel = path.relative_to(ROOT).as_posix()
        if rel in exempt:
            continue
        if f"{path.stem}Tests" not in test_names:
            fail(f"{rel} has no Tests/**/{path.stem}Tests.swift (add tests or mark test_exempt with a reason)")
            failures += 1

    print(f"guard 04 test_name_consistency: {len(test_files)} test files, {len(sources)} sources, {len(exempt)} exempt, failures={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
