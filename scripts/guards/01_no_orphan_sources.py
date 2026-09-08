#!/usr/bin/env python3
"""Guard 01 — no orphan sources (debt types 1 dead code / lava flow, 2 speculative generality).

Checks:
  (a) every `implemented` path in docs/ARCHITECTURE.yaml exists, and every `called_by` path exists
  (b) every Sources/**/*.swift and App/**/*.swift file is registered under `implemented`
  (c) every `public` type declared in Sources/ or App/ is referenced in at least one other file
      (Sources/, App/ or Tests/); files containing `@main` are exempt (entry points have no caller)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from arch_yaml import ROOT, fail, implemented_entries, load  # noqa: E402

PUBLIC_TYPE = re.compile(
    r"^\s*public\s+(?:final\s+)?(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


def swift_files(folder: str) -> list[Path]:
    return sorted(p for p in (ROOT / folder).rglob("*.swift") if ".build" not in p.parts)


def main() -> int:
    failures = 0
    arch = load()
    entries = implemented_entries(arch)
    registered = {entry["path"] for entry in entries}

    for entry in entries:
        if not (ROOT / entry["path"]).exists():
            fail(f"ARCHITECTURE.yaml lists {entry['path']} as implemented but it does not exist")
            failures += 1
        for caller in entry["called_by"]:
            if not (ROOT / caller).exists():
                fail(f"{entry['path']}: called_by {caller} does not exist")
                failures += 1

    sources = swift_files("Sources") + swift_files("App")
    for path in sources:
        rel = path.relative_to(ROOT).as_posix()
        if rel not in registered:
            fail(f"{rel} is not registered in docs/ARCHITECTURE.yaml (delete it or wire it and register it)")
            failures += 1

    all_files = sources + swift_files("Tests")
    contents = {p: p.read_text(encoding="utf-8") for p in all_files}
    for path in sources:
        text = contents[path]
        if "@main" in text:
            continue
        for name in PUBLIC_TYPE.findall(text):
            pattern = re.compile(rf"(?<![A-Za-z0-9_]){re.escape(name)}(?![A-Za-z0-9_])")
            referenced = any(pattern.search(contents[other]) for other in all_files if other != path)
            if not referenced:
                rel = path.relative_to(ROOT).as_posix()
                fail(f"public type {name} in {rel} is referenced nowhere else (dead code: delete or wire)")
                failures += 1

    print(f"guard 01 no_orphan_sources: {len(sources)} source files, {len(entries)} registered entries, failures={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
