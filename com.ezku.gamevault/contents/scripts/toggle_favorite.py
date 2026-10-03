#!/usr/bin/env python3
"""
Alterna un juego en ~/.local/share/gamedrawer/favorites.json.

Uso: toggle_favorite.py "<nombre del juego>"
Sin dependencias externas, solo stdlib.
"""

import json
import os
import sys

FAVORITES_PATH = os.path.expanduser("~/.local/share/gamedrawer/favorites.json")


def main():
    if len(sys.argv) < 2 or not sys.argv[1].strip():
        return
    name = sys.argv[1].strip()

    try:
        os.makedirs(os.path.dirname(FAVORITES_PATH), exist_ok=True)
    except OSError:
        return

    try:
        with open(FAVORITES_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, list):
            data = []
    except (OSError, ValueError):
        data = []

    lowered = {str(n).strip().lower() for n in data}
    if name.strip().lower() in lowered:
        data = [n for n in data if str(n).strip().lower() != name.strip().lower()]
    else:
        data.append(name)

    tmp_path = FAVORITES_PATH + ".tmp"
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp_path, FAVORITES_PATH)
    except OSError:
        pass


if __name__ == "__main__":
    main()
