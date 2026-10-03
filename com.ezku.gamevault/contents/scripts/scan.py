#!/usr/bin/env python3
"""
Calls all other "scan_*.py" scripts in this folder and collates their output into one JSON array.

No external dependencies -- stdlib only, Python 3.6+ compatible.
"""

import os
import sys
import subprocess
import json

RECENT_PATH = os.path.expanduser("~/.local/share/gamedrawer/recent.json")
FAVORITES_PATH = os.path.expanduser("~/.local/share/gamedrawer/favorites.json")
HIDDEN_PATH = os.path.expanduser("~/.local/share/gamedrawer/hidden.json")

def load_recent():
    try:
        with open(RECENT_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return {str(k).strip().lower(): int(v) for k, v in data.items()}
    except (OSError, ValueError, TypeError):
        pass
    return {}

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))

    scan_files = sorted(
        f for f in os.listdir(script_dir)
        if f.startswith('scan_') and f.endswith('.py')
    )

    collated_results = []

    for filename in scan_files:
        filepath = os.path.join(script_dir, filename)

        try:
            result = subprocess.run(
                [sys.executable, filepath],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,  # Equivalent to universal_newlines=True
                check=False, # Don't raise an error if the script exits with non-zero
                timeout=15
            )

            if result.stdout.strip():
                try:
                    data = json.loads(result.stdout)

                    if isinstance(data, list):
                        collated_results.extend(data)

                except json.JSONDecodeError:
                    pass

        except (subprocess.TimeoutExpired, OSError):
            continue
        except Exception:
            pass

    valid_entries = [entry for entry in collated_results if isinstance(entry, dict) and "name" in entry]
    # Dedup por nombre (case-insensitive): conserva el de mayor lastPlayed
    best_by_name = {}
    for entry in valid_entries:
        key = str(entry["name"]).strip().lower()
        if not key:
            continue
        prev = best_by_name.get(key)
        if prev is None:
            best_by_name[key] = entry
        else:
            try:
                cur_ts = int(entry.get("lastPlayed", 0) or 0)
            except (ValueError, TypeError):
                cur_ts = 0
            try:
                prev_ts = int(prev.get("lastPlayed", 0) or 0)
            except (ValueError, TypeError):
                prev_ts = 0
            if cur_ts > prev_ts:
                best_by_name[key] = entry
    collated_results = list(best_by_name.values())

    try:
        with open(FAVORITES_PATH, "r", encoding="utf-8") as f:
            fav_data = json.load(f)
        favorites = {
            str(n).strip().lower() for n in fav_data
        } if isinstance(fav_data, list) else set()
    except (OSError, ValueError, TypeError):
        favorites = set()
    for entry in collated_results:
        entry["favorite"] = (
            str(entry.get("name", "")).strip().lower() in favorites
        )

    try:
        with open(HIDDEN_PATH, "r", encoding="utf-8") as f:
            hidden_data = json.load(f)
        hidden = {
            str(n).strip().lower() for n in hidden_data
        } if isinstance(hidden_data, list) else set()
    except (OSError, ValueError, TypeError):
        hidden = set()
    for entry in collated_results:
        entry["hidden"] = (
            str(entry.get("name", "")).strip().lower() in hidden
        )

    # Recencia real: lo lanzado desde el drawer manda sobre Steam
    recent = load_recent()
    if recent:
        for entry in collated_results:
            try:
                current = int(entry.get("lastPlayed", 0) or 0)
            except (ValueError, TypeError):
                current = 0
            recorded = recent.get(str(entry.get("name", "")).strip().lower())
            if recorded is not None and recorded > current:
                entry["lastPlayed"] = recorded

    # Último jugado primero (global, entre todas las fuentes)
    def _ts(entry):
        try:
            return int(entry.get("lastPlayed", 0) or 0)
        except (ValueError, TypeError):
            return 0
    collated_results.sort(key=_ts, reverse=True)

    print(json.dumps(collated_results, indent=2))

if __name__ == "__main__":
    main()
