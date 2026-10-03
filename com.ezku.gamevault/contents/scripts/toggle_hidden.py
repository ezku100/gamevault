#!/usr/bin/env python3
"""
Alterna un juego en ~/.local/share/gamedrawer/hidden.json.

Uso: toggle_hidden.py "<nombre del juego>"
Sin dependencias externas, solo stdlib.
"""

import json
import os
import sys

HIDDEN_PATH = os.path.expanduser("~/.local/share/gamedrawer/hidden.json")


def main():
    if len(sys.argv) < 2 or not sys.argv[1].strip():
        return
    name = sys.argv[1].strip()

    try:
        os.makedirs(os.path.dirname(HIDDEN_PATH), exist_ok=True)
    except OSError:
        return

    try:
        with open(HIDDEN_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, list):
            data = []
    except (OSError, ValueError):
        data = []

    lowered = name.strip().lower()
    if lowered in {str(n).strip().lower() for n in data}:
        data = [n for n in data if str(n).strip().lower() != lowered]
    else:
        data.append(name)

    tmp_path = HIDDEN_PATH + ".tmp"
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp_path, HIDDEN_PATH)
    except OSError:
        pass


if __name__ == "__main__":
    main()
