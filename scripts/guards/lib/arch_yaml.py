"""Minimal reader for docs/ARCHITECTURE.yaml.

Why: guards must run with a stock python3 (no PyYAML). ARCHITECTURE.yaml is written in a small,
regular subset: mappings, block lists (of scalars or mappings), flow lists `[a, b]`, and scalars.
Anything outside that subset raises, so the file cannot silently drift into shapes guards ignore.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ARCH_PATH = ROOT / "docs" / "ARCHITECTURE.yaml"


class ArchYamlError(Exception):
    pass


def _strip(line: str) -> str:
    # Drop comments; the subset never uses '#' inside values.
    return line.split("#", 1)[0].rstrip()


def _scalar(text: str):
    text = text.strip()
    if text.startswith("[") and text.endswith("]"):
        inner = text[1:-1].strip()
        return [] if not inner else [part.strip() for part in inner.split(",")]
    if text in ("true", "false"):
        return text == "true"
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    return text


def _parse_block(lines: list[tuple[int, str]], pos: int, indent: int):
    """Parse a block starting at `pos` whose items share `indent`. Returns (value, next_pos)."""
    if pos >= len(lines):
        return {}, pos
    _, first = lines[pos]
    if first.lstrip().startswith("- "):
        return _parse_list(lines, pos, indent)
    return _parse_mapping(lines, pos, indent)


def _parse_mapping(lines, pos, indent):
    out: dict = {}
    while pos < len(lines):
        ind, text = lines[pos]
        if ind < indent:
            break
        if ind > indent or text.lstrip().startswith("- "):
            raise ArchYamlError(f"unexpected indentation at line {pos + 1}: {text!r}")
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):(.*)$", text.strip())
        if not match:
            raise ArchYamlError(f"expected 'key: value' at line {pos + 1}: {text!r}")
        key, rest = match.group(1), match.group(2).strip()
        pos += 1
        if rest:
            out[key] = _scalar(rest)
        elif pos < len(lines) and lines[pos][0] > indent:
            out[key], pos = _parse_block(lines, pos, lines[pos][0])
        else:
            out[key] = None
    return out, pos


def _parse_list(lines, pos, indent):
    out: list = []
    while pos < len(lines):
        ind, text = lines[pos]
        if ind < indent:
            break
        if ind != indent or not text.lstrip().startswith("- "):
            raise ArchYamlError(f"malformed list item at line {pos + 1}: {text!r}")
        item_text = text.strip()[2:]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*:", item_text):
            # Mapping item: first key is inline, the rest are indented by two more spaces.
            child_indent = indent + 2
            synthetic = [(child_indent, " " * child_indent + item_text)]
            pos += 1
            while pos < len(lines) and lines[pos][0] >= child_indent:
                synthetic.append(lines[pos])
                pos += 1
            value, _ = _parse_mapping(synthetic, 0, child_indent)
            out.append(value)
        else:
            out.append(_scalar(item_text))
            pos += 1
    return out, pos


def load(path: Path = ARCH_PATH) -> dict:
    raw_lines = path.read_text(encoding="utf-8").splitlines()
    lines: list[tuple[int, str]] = []
    for raw in raw_lines:
        text = _strip(raw)
        if not text.strip():
            continue
        if "\t" in text[: len(text) - len(text.lstrip())]:
            raise ArchYamlError("tabs are not allowed for indentation")
        lines.append((len(text) - len(text.lstrip()), text))
    value, pos = _parse_mapping(lines, 0, 0)
    if pos != len(lines):
        raise ArchYamlError(f"trailing content at line {pos + 1}")
    return value


def implemented_entries(arch: dict) -> list[dict]:
    entries = arch.get("implemented")
    if not isinstance(entries, list):
        raise ArchYamlError("'implemented' must be a list")
    for entry in entries:
        if entry.get("status") != "implemented":
            raise ArchYamlError(f"entry {entry.get('path')!r} under implemented has status {entry.get('status')!r}")
        if not entry.get("path"):
            raise ArchYamlError(f"implemented entry without path: {entry!r}")
        if not entry.get("called_by"):
            raise ArchYamlError(f"implemented entry {entry['path']!r} has no called_by")
    return entries


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)


if __name__ == "__main__":
    import json

    print(json.dumps(load(), ensure_ascii=False, indent=2))
