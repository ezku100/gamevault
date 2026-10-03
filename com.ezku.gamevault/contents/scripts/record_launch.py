#!/usr/bin/env python3
"""
Registra cuándo se lanzó un juego desde el drawer (recencia real).

Uso: record_launch.py "<nombre del juego>"
Guarda en ~/.local/share/gamedrawer/recent.json un mapa
nombre -> timestamp unix. scan.py lo usa para ordenar el
último jugado primero.

No external dependencies -- stdlib only, Python 3.6+ compatible.
"""

import json
import os
import sys
import time

RECENT_PATH = os.path.expanduser("~/.local/share/gamedrawer/recent.json")
MAX_ENTRIES = 200


def main():
    if len(sys.argv) < 2 or not sys.argv[1].strip():
        return
    name = sys.argv[1].strip()

    try:
        os.makedirs(os.path.dirname(RECENT_PATH), exist_ok=True)
    except OSError:
        return

    try:
        with open(RECENT_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            data = {}
    except (OSError, ValueError):
        data = {}

    data[name] = int(time.time())

    if len(data) > MAX_ENTRIES:
        data = dict(
            sorted(data.items(), key=lambda kv: kv[1], reverse=True)[:MAX_ENTRIES]
        )

    tmp_path = RECENT_PATH + ".tmp"
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp_path, RECENT_PATH)
    except OSError:
        pass


if __name__ == "__main__":
    main()
