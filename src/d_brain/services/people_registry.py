"""People registry — single source of truth for name → person matching.

Builds a compact index of all people cards (name, aliases, slug, role) so the
daily processor can match mentioned names against ONE list instead of grepping
46 files and guessing similarity each run. Cards are the source of truth; the
registry is regenerated on every /process.
"""

from __future__ import annotations

import json
import logging
import re
from pathlib import Path

logger = logging.getLogger(__name__)


def _parse_frontmatter(text: str) -> dict[str, str]:
    """Extract the raw frontmatter block (between first two ---) as line dict.

    Lightweight: no PyYAML dependency. Handles simple `key: value` and the
    inline-array form `aliases: [a, b, c]` plus folded `description: >-`.
    """
    m = re.search(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return {}
    block = m.group(1)
    fm: dict[str, str] = {}
    lines = block.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        km = re.match(r"^([A-Za-z_][\w-]*):\s?(.*)$", line)
        if km:
            key, val = km.group(1), km.group(2).strip()
            # Folded/literal scalar (>- or |) — gather indented continuation.
            if val in (">-", ">", "|", "|-"):
                parts = []
                i += 1
                while i < len(lines) and (lines[i].startswith("  ") or lines[i].strip() == ""):
                    parts.append(lines[i].strip())
                    i += 1
                fm[key] = " ".join(p for p in parts if p).strip()
                continue
            fm[key] = val
        i += 1
    return fm


def _parse_inline_list(val: str) -> list[str]:
    """`[Лёша, Алёша]` -> ['Лёша', 'Алёша']. Tolerates quotes/empty."""
    val = val.strip()
    if not val or val in ("[]", "[ ]"):
        return []
    if val.startswith("[") and val.endswith("]"):
        inner = val[1:-1]
        return [x.strip().strip("'\"") for x in inner.split(",") if x.strip()]
    return [val.strip().strip("'\"")]


def _name_from_description(desc: str) -> str:
    """type:contact cards keep the full name as the first phrase of description,
    e.g. 'Шалина Анна Юрьевна — ...'. Return that phrase (before — / -)."""
    if not desc:
        return ""
    head = re.split(r"\s[—\-]\s", desc, maxsplit=1)[0].strip()
    # guard against absurdly long heads (not a name)
    return head if 0 < len(head) <= 60 else ""


def build_registry(people_dir: Path) -> list[dict]:
    """Scan people_dir and return a list of person entries."""
    entries: list[dict] = []
    for fp in sorted(Path(people_dir).glob("*.md")):
        if fp.name == "_index.md":
            continue
        try:
            text = fp.read_text(encoding="utf-8")
        except Exception:
            logger.warning("Cannot read %s", fp)
            continue
        fm = _parse_frontmatter(text)
        slug = fm.get("slug", "").strip() or fp.stem
        name = fm.get("name", "").strip()
        desc = fm.get("description", "").strip()
        if not name:
            name = _name_from_description(desc)
        aliases = _parse_inline_list(fm.get("aliases", ""))
        role = fm.get("role", "").strip()
        if not role and desc:
            # short role hint = trailing part of description after the dash
            tail = re.split(r"\s[—\-]\s", desc, maxsplit=1)
            role = tail[1].strip()[:80] if len(tail) > 1 else ""
        entries.append(
            {
                "slug": slug,
                "name": name or slug,
                "aliases": aliases,
                "role": role,
            }
        )
    return entries


def write_registry(people_dir: Path, out_path: Path) -> list[dict]:
    entries = build_registry(people_dir)
    out_path.write_text(
        json.dumps({"people": entries}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    logger.info("People registry written: %s (%d people)", out_path, len(entries))
    return entries


def registry_as_prompt(entries: list[dict]) -> str:
    """Compact one-line-per-person text for embedding in the Claude prompt."""
    lines = []
    for e in entries:
        al = ", ".join(e["aliases"]) if e["aliases"] else ""
        role = f" — {e['role']}" if e["role"] else ""
        alias_part = f" (варианты: {al})" if al else ""
        lines.append(f"- {e['name']} [slug: {e['slug']}]{alias_part}{role}")
    return "\n".join(lines)
