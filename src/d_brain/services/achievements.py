"""Achievements storage — vault/achievements/YYYY-MM.md."""

import re
from datetime import datetime
from pathlib import Path

# Matches an entry header written by append(): '## 2026-06-17 14:50 [voice]'
_ENTRY_HEADER = re.compile(r'^## \d{4}-\d{2}-\d{2} \d{2}:\d{2} \[', re.MULTILINE)


class AchievementsStorage:
    def __init__(self, vault_path: Path) -> None:
        self.vault_path = Path(vault_path)
        self.dir = self.vault_path / "achievements"

    def _file_for(self, ts: datetime) -> Path:
        self.dir.mkdir(parents=True, exist_ok=True)
        return self.dir / f"{ts.strftime("%Y-%m")}.md"

    def append(self, text: str, ts: datetime, source: str = "text") -> Path:
        """Append achievement to monthly file. source: text or voice."""
        path = self._file_for(ts)
        marker = f"[{source}]"
        date_str = ts.strftime("%Y-%m-%d %H:%M")
        entry = f"\n## {date_str} {marker}\n{text.strip()}\n"
        with path.open("a", encoding="utf-8") as f:
            f.write(entry)
        return path

    def count_this_month(self, ts=None) -> int:
        if ts is None:
            ts = datetime.now()
        path = self._file_for(ts)
        if not path.exists():
            return 0
        # Count entry headers only (## YYYY-MM-DD HH:MM [source]) so a markdown
        # heading inside an achievement text never inflates the count.
        text = path.read_text(encoding="utf-8")
        return len(_ENTRY_HEADER.findall(text))
