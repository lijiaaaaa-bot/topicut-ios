#!/usr/bin/env python3
"""Guard 06 — documentation must not drift from ARCHITECTURE.yaml (debt type 7).

Every technology term in docs/tech_terms.txt is classified in exactly one `tech_terms` bucket of
docs/ARCHITECTURE.yaml. In README.md, AGENTS.md, CHANGELOG.md and docs/*.md:
  - implemented terms may appear bare (and must NOT carry a planned/not-used marker)
  - planned terms must be written `Term (planned)`
  - requires_new_architecture terms must be written `Term (requires_new_architecture)`
  - not_used terms must be written `Term (not used)`
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from arch_yaml import ROOT, fail, load  # noqa: E402

MARKERS = {
    "implemented": None,
    "planned": "(planned)",
    "requires_new_architecture": "(requires_new_architecture)",
    "not_used": "(not used)",
}
ANY_MARKER = re.compile(r"\s*\((planned|requires_new_architecture|not used)\)")


def doc_files() -> list[Path]:
    files = [ROOT / name for name in ("README.md", "AGENTS.md", "CHANGELOG.md")]
    files += sorted((ROOT / "docs").glob("*.md"))
    return [f for f in files if f.exists()]


def main() -> int:
    failures = 0
    arch = load()
    buckets = arch.get("tech_terms")
    if not isinstance(buckets, dict) or set(buckets) != set(MARKERS):
        fail(f"ARCHITECTURE.yaml tech_terms must have exactly the buckets {sorted(MARKERS)}")
        return 1

    term_bucket: dict[str, str] = {}
    for bucket, terms in buckets.items():
        for term in terms:
            if term in term_bucket:
                fail(f"term {term!r} is in both {term_bucket[term]} and {bucket}")
                failures += 1
            term_bucket[term] = bucket

    listed = {
        line.strip()
        for line in (ROOT / "docs" / "tech_terms.txt").read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    }
    if listed != set(term_bucket):
        fail(f"docs/tech_terms.txt and ARCHITECTURE.yaml tech_terms differ: "
             f"only in txt={sorted(listed - set(term_bucket))}, only in yaml={sorted(set(term_bucket) - listed)}")
        failures += 1

    for path in doc_files():
        rel = path.relative_to(ROOT).as_posix()
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            for term, bucket in term_bucket.items():
                for match in re.finditer(rf"(?<![A-Za-z0-9_]){re.escape(term)}(?![A-Za-z0-9_])", line):
                    marker = ANY_MARKER.match(line, match.end())
                    found = marker.group(0).strip() if marker else None
                    expected = MARKERS[bucket]
                    if found != expected:
                        want = expected or "no marker"
                        fail(f"{rel}:{line_no}: '{term}' is {bucket}; expected {want}, found {found or 'none'}")
                        failures += 1

    print(f"guard 06 docs_drift: {len(term_bucket)} terms across {len(doc_files())} docs, failures={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
