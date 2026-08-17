#!/usr/bin/env python3
"""Учёт токенов для bash-фаз (process.sh).

Читает JSON-обёртку `claude --print --output-format json` со stdin,
дописывает usage-запись в .runtime/usage.jsonl и печатает текст
результата (поле result) в stdout — дальше пайплайн работает как раньше.

Использование:
    claude --print --output-format json -p "..." | python3 scripts/log_usage.py capture

При не-JSON входе (старый формат, ошибка CLI) пропускает вход насквозь
без учёта — пайплайн не ломается.
"""

import json
import sys
from datetime import datetime
from pathlib import Path


def main() -> None:
    kind = sys.argv[1] if len(sys.argv) > 1 else "unknown"
    raw = sys.stdin.read()
    try:
        data = json.loads(raw.strip())
        usage = data.get("usage") or {}
        rec = {
            "ts": datetime.now().isoformat(timespec="seconds"),
            "kind": kind,
            "user_id": 0,
            "input_tokens": usage.get("input_tokens", 0),
            "output_tokens": usage.get("output_tokens", 0),
            "cache_read_tokens": usage.get("cache_read_input_tokens", 0),
            "cost_usd": data.get("total_cost_usd", 0),
            "duration_ms": data.get("duration_ms", 0),
        }
        runtime = Path(__file__).resolve().parent.parent / ".runtime"
        runtime.mkdir(exist_ok=True)
        with (runtime / "usage.jsonl").open("a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        sys.stdout.write(data.get("result") or "")
    except (json.JSONDecodeError, AttributeError):
        sys.stdout.write(raw)


main()
