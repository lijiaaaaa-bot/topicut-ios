#!/usr/bin/env python3
"""Guard 03 — no god objects (debt type 4).

Any Swift file under Sources/ or Tests/ longer than MAX_FILE_LINES fails.
Any `func`/`init` body longer than MAX_FUNC_LINES fails. Coarse brace counting after stripping
comments and multi-line string literals (the prompt file contains `{}` inside strings).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from arch_yaml import ROOT, fail  # noqa: E402

MAX_FILE_LINES = 300
MAX_FUNC_LINES = 60
FUNC_START = re.compile(r"^\s*(?:@\w+\s+)*(?:(?:public|private|internal|fileprivate|static|override|mutating|final)\s+)*(?:func\s+\w+|init\b)")


def strip_noise(text: str) -> str:
    """Blank out multi-line strings, single-line strings and comments while preserving line count."""
    out: list[str] = []
    in_multiline = False
    for line in text.splitlines():
        if in_multiline:
            if '"""' in line:
                in_multiline = False
            out.append("")
            continue
        if line.count('"""') == 1:
            in_multiline = True
            out.append(line.split('"""')[0])
            continue
        line = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
        line = re.sub(r"//.*$", "", line)
        out.append(line)
    return "\n".join(out)


def function_lengths(text: str) -> list[tuple[int, int]]:
    """Return (start_line, length) for each func/init body."""
    lines = strip_noise(text).splitlines()
    results: list[tuple[int, int]] = []
    index = 0
    while index < len(lines):
        if FUNC_START.match(lines[index]):
            start = index
            depth = 0
            opened = False
            while index < len(lines):
                for char in lines[index]:
                    if char == "{":
                        depth += 1
                        opened = True
                    elif char == "}":
                        depth -= 1
                if opened and depth == 0:
                    break
                index += 1
            results.append((start + 1, index - start + 1))
        index += 1
    return results


def main() -> int:
    failures = 0
    files = sorted(p for folder in ("Sources", "Tests") for p in (ROOT / folder).rglob("*.swift"))
    checked = 0
    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8")
        total = len(text.splitlines())
        if total > MAX_FILE_LINES:
            fail(f"{rel} has {total} lines (> {MAX_FILE_LINES}); split it")
            failures += 1
        for start, length in function_lengths(text):
            checked += 1
            if length > MAX_FUNC_LINES:
                fail(f"{rel}:{start} function body spans {length} lines (> {MAX_FUNC_LINES})")
                failures += 1
    print(f"guard 03 no_god_object: {len(files)} files, {checked} functions, failures={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
