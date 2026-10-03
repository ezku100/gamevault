#!/usr/bin/env python3
"""
Scans the local Steam installation for installed games and outputs
a JSON array with name, appid, last-played timestamp, and cover image path.

No external dependencies -- stdlib only, Python 3.6+ compatible.
"""

import os
import sys
import json

STEAM_ROOT = os.path.expanduser("~/.steam/steam")
LIBRARYFOLDERS_VDF = os.path.join(STEAM_ROOT, "steamapps", "libraryfolders.vdf")
LIBRARY_CACHE_DIR = os.path.join(STEAM_ROOT, "appcache", "librarycache")

# ---------- Minimal VDF (KeyValues) parser ----------
def tokenize(text):
    tokens = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c in " \t\r\n":
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] not in "\r\n":
                i += 1
            continue
        if c == '"':
            j = i + 1
            buf = []
            while j < n and text[j] != '"':
                if text[j] == "\\" and j + 1 < n:
                    buf.append(text[j + 1])
                    j += 2
                    continue
                buf.append(text[j])
                j += 1
            tokens.append("".join(buf))
            i = j + 1
            continue
        if c in "{}":
            tokens.append(c)
            i += 1
            continue
        # Unquoted token fallback (rare in these files, but just in case)
        j = i
        while j < n and text[j] not in " \t\r\n{}\"":
            j += 1
        tokens.append(text[i:j])
        i = j
    return tokens

def parse_tokens(tokens):
    idx = 0

    def parse_object():
        nonlocal idx
        obj = {}
        while idx < len(tokens):
            tok = tokens[idx]
            if tok == "}":
                idx += 1
                return obj
            key = tok
            idx += 1
            if idx >= len(tokens):
                break
            nxt = tokens[idx]
            if nxt == "{":
                idx += 1
                value = parse_object()
            else:
                value = nxt
                idx += 1
            obj[key] = value
        return obj

    return parse_object()

def parse_vdf_file(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        text = f.read()
    return parse_tokens(tokenize(text))

def get_ci(d, key):
    """Case-insensitive dict lookup -- Valve's casing isn't fully consistent
    across files/versions, so we don't rely on exact case."""
    if not isinstance(d, dict):
        return None
    for k, v in d.items():
        if k.lower() == key.lower():
            return v
    return None

# ---------- Steam-specific logic ----------

def get_library_folders():
    data = parse_vdf_file(LIBRARYFOLDERS_VDF)
    libs_block = get_ci(data, "libraryfolders") or {}

    libraries = []
    for _, entry in libs_block.items():
        if not isinstance(entry, dict):
            continue
        path = get_ci(entry, "path")
        apps = get_ci(entry, "apps") or {}
        if path and isinstance(apps, dict):
            libraries.append({"path": path, "appids": list(apps.keys())})
    return libraries

def parse_appmanifest(path):
    data = parse_vdf_file(path)
    return get_ci(data, "AppState") or {}

def find_hero_image(appid):
    appdir = os.path.join(LIBRARY_CACHE_DIR, appid)
    if not os.path.isdir(appdir):
        return None

    for root, _dirs, files in os.walk(appdir):
        for fname in files:
            if fname.lower() == "header.jpg":
                return "file://" + os.path.join(root, fname)

    # Image is not (yet) in the cache. Use the CDN link instead.
    return "https://cdn.cloudflare.steamstatic.com/steam/apps/" + appid + "/header.jpg"

def collect_games():
    games = []

    try:
        libraries = get_library_folders()
    except Exception as e:
        print("Failed to read libraryfolders.vdf: {}".format(e), file=sys.stderr)
        return games

    for lib in libraries:
        steamapps_dir = os.path.join(lib["path"], "steamapps")

        for appid in lib["appids"]:
            manifest_path = os.path.join(
                steamapps_dir, "appmanifest_{}.acf".format(appid)
            )
            if not os.path.isfile(manifest_path):
                continue

            try:
                appstate = parse_appmanifest(manifest_path)
            except Exception as e:
                print(
                    "Failed to parse {}: {}".format(manifest_path, e),
                    file=sys.stderr,
                )
                continue

            name = get_ci(appstate, "name")
            if not name:
                continue

            last_played_raw = get_ci(appstate, "LastPlayed") or "0"
            try:
                last_played = int(last_played_raw)
            except ValueError:
                last_played = 0

            games.append(
                {
                    "appid": appid,
                    "name": name,
                    "lastPlayed": last_played,
                    "image": find_hero_image(appid),
                    "runcmd": "steam steam://rungameid/" + appid,
                    "source": "steam",
                }
            )

    games.sort(key=lambda g: g["lastPlayed"], reverse=True)
    return games


def main():
    games = collect_games()
    print(json.dumps(games, indent=2))


if __name__ == "__main__":
    main()
