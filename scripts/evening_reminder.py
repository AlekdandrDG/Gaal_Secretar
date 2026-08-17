#!/usr/bin/env python3
"""Evening reminder: 1h before daily processing, show daily state + nudge user."""

import html
import os
import re
import sys
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
ENV_FILE = PROJECT_DIR / ".env"
VAULT_DIR = PROJECT_DIR / "vault"

if ENV_FILE.exists():
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k, v)

token = os.environ.get("TELEGRAM_BOT_TOKEN")
if not token:
    print("ERROR: TELEGRAM_BOT_TOKEN not set", file=sys.stderr)
    sys.exit(1)

chat_id = os.environ.get("ALLOWED_USER_IDS", "").strip("[]").split(",")[0].strip()
today = date.today().isoformat()
daily_file = VAULT_DIR / "daily" / f"{today}.md"

if not daily_file.exists() or daily_file.stat().st_size < 50:
    message = (
        "⏰ <b>Через час вечерняя обработка</b>\n\n"
        "📭 Сегодня в daily пусто\n\n"
        "Если есть мысли / задачи / итоги встреч — закинь сейчас."
    )
else:
    text = daily_file.read_text()
    pattern = re.compile(r"^## (\d{2}:\d{2}) \[([^\]]+)\]\s*\n+([^\n]+)", re.MULTILINE)
    entries = pattern.findall(text)
    lines = []
    for tm, etype, snippet in entries:
        snippet = snippet.strip()
        if len(snippet) > 70:
            snippet = snippet[:70] + "…"
        lines.append(f"• {tm} <i>{html.escape(etype)}</i> — {html.escape(snippet)}")
    body = "\n".join(lines) if lines else "(не удалось распарсить записи)"
    message = (
        "⏰ <b>Через час вечерняя обработка</b>\n\n"
        f"📝 Сегодня в daily ({len(entries)} записей):\n"
        f"{body}\n\n"
        "Если что-то забыл — закинь сейчас."
    )

data = urllib.parse.urlencode({
    "chat_id": chat_id,
    "text": message,
    "parse_mode": "HTML",
}).encode()

req = urllib.request.Request(
    f"https://api.telegram.org/bot{token}/sendMessage",
    data=data,
)
with urllib.request.urlopen(req, timeout=15) as resp:
    print(f"Reminder sent ({resp.status}) for {today}")
