#!/usr/bin/env python3
"""Извлекает первый валидный JSON-объект из stdin.

Устойчив к: многострочному (pretty-printed) JSON, code fences (```json),
преамбулам и хвостам вокруг объекта. Печатает JSON с indent=2.
Exit 1 — если валидный объект не найден.

Использование в process.sh:
    echo "$CAPTURE" | python3 scripts/extract_json.py > capture.json
"""

import json
import re
import sys


def main() -> None:
    raw = sys.stdin.read()
    raw = re.sub(r"```(?:json)?", "", raw)  # срезать code fences

    decoder = json.JSONDecoder()
    for m in re.finditer(r"\{", raw):
        try:
            obj, _ = decoder.raw_decode(raw, m.start())
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict):
            json.dump(obj, sys.stdout, ensure_ascii=False, indent=2)
            return
    sys.exit(1)


main()
