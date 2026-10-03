#!/usr/bin/env python3
"""
Scans Steam's non-Steam shortcuts (games added manually via
"Add a Non-Steam Game") and outputs a JSON array compatible with
the game drawer (name, appid, lastPlayed, image, runcmd).

Reads the binary shortcuts.vdf of every local userdata account:
  ~/.steam/steam/userdata/<userid>/config/shortcuts.vdf
Custom artwork is picked up from the sibling grid/ folder:
  <shortcutid>.png > <shortcutid>_hero.png > <shortcutid>p.png
Shortcuts without artwork are skipped (set art in Steam:
right-click the shortcut -> Manage -> Set custom artwork).

Shortcut ids follow Valve's scheme:
  shortcut_id = crc32(exe + appname) | 0x80000000
  rungameid   = (shortcut_id << 32) | 0x02000000

No external dependencies -- stdlib only, Python 3.6+ compatible.
"""

import binascii
import glob
import os
import shutil
import struct
import sys
import json

STEAM_ROOT = os.path.expanduser("~/.steam/steam")

GRID_SUFFIXES = ("", "_hero", "p", "_logo", "_icon")
GRID_EXTS = (".png", ".jpg", ".jpeg", ".webp")

EMULATOR_BINS = (
    "eden", "ryujinx", "yuzu", "suyu", "torzu", "sudachi", "dolphin",
    "pcsx2", "rpcs3", "retroarch", "cemu", "duckstation", "ppsspp",
    "citra", "lime3ds", "azahar", "xemu", "vita3k", "shadps4", "melonds",
    "desmume", "mupen", "ares", "bsnes", "snes9x", "mgba", "epsxe",
)
ROM_EXTS = (
    ".nsp", ".xci", ".nca", ".3ds", ".2ds", ".iso", ".cso", ".rvz",
    ".wbfs", ".wdf", ".chd", ".cue", ".gcm", ".nes", ".snes", ".sfc",
    ".n64", ".z64", ".gba", ".gbc", ".gb", ".nds", ".n3ds", ".smd",
    ".gen", ".rom", ".bin", ".img", ".pbp", ".mdf",
)


def classify_source(exe):
    low = (exe or "").lower()
    if any(k in low for k in EMULATOR_BINS) or any(e in low for e in ROM_EXTS):
        return "shortcut"
    return "nosteam"


# ---------- Minimal binary-VDF parser (shortcuts.vdf) ----------
def _read_cstr(data, pos):
    end = data.index(b"\x00", pos)
    return data[pos:end].decode("utf-8", errors="replace"), end + 1


def _parse_obj(data, pos):
    obj = {}
    n = len(data)
    while pos < n:
        t = data[pos]
        pos += 1
        if t == 0x08:  # end of object
            return obj, pos
        key, pos = _read_cstr(data, pos)
        if t == 0x00:  # nested object
            val, pos = _parse_obj(data, pos)
        elif t == 0x01:  # string
            val, pos = _read_cstr(data, pos)
        elif t == 0x02:  # int32
            val = struct.unpack("<i", data[pos:pos + 4])[0]
            pos += 4
        else:
            raise ValueError("unknown VDF type 0x{:02x}".format(t))
        obj[key] = val
    return obj, pos


def parse_shortcuts(path):
    with open(path, "rb") as f:
        data = f.read()
    root, _ = _parse_obj(data, 0)
    shortcuts = root.get("shortcuts", {})
    if not isinstance(shortcuts, dict):
        return []
    return [v for v in shortcuts.values() if isinstance(v, dict)]


# ---------- Shortcut helpers ----------
def get_ci(d, *names):
    """Case-insensitive lookup: Steam mixes 'AppName'/'appname',
    'Exe'/'exe', 'LastPlayTime'/'lastplaytime' depending on which
    client version wrote each entry."""
    if not isinstance(d, dict):
        return None
    lowered = {k.lower(): v for k, v in d.items()}
    for name in names:
        if name in d:
            return d[name]
        if name.lower() in lowered:
            return lowered[name.lower()]
    return None


def shortcut_id(exe, appname):
    return (binascii.crc32((exe + appname).encode("utf-8")) & 0xFFFFFFFF) | 0x80000000


IDS_PATH = os.path.expanduser("~/.local/share/gamedrawer/shortcut_ids.json")


def load_sid_history():
    try:
        with open(IDS_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return {str(k): [int(s) for s in v if isinstance(s, int)]
                    for k, v in data.items() if isinstance(v, list)}
    except (OSError, ValueError, TypeError):
        pass
    return {}


def save_sid_history(history):
    try:
        os.makedirs(os.path.dirname(IDS_PATH), exist_ok=True)
    except OSError:
        return
    tmp_path = IDS_PATH + ".tmp"
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(history, f)
        os.replace(tmp_path, IDS_PATH)
    except OSError:
        pass


def image_size(path):
    try:
        with open(path, "rb") as f:
            head = f.read(64)
            if head[1:4] == b"PNG" and len(head) >= 24:
                w = int.from_bytes(head[16:20], "big")
                h = int.from_bytes(head[20:24], "big")
                return (w, h)
            if head[0:2] != b"\xff\xd8":
                return None
            f.seek(2)
            while True:
                marker = f.read(2)
                if len(marker) < 2 or marker[0] != 0xFF:
                    return None
                if marker[1] in (0xC0, 0xC1, 0xC2):
                    f.read(3)
                    h = int.from_bytes(f.read(2), "big")
                    w = int.from_bytes(f.read(2), "big")
                    return (w, h)
                size = int.from_bytes(f.read(2), "big")
                f.seek(size - 2, 1)
    except OSError:
        pass
    return None


def grid_files(grid_dir, sid):
    found = []
    for suffix in GRID_SUFFIXES:
        for ext in GRID_EXTS:
            candidate = os.path.join(grid_dir, "{}{}".format(sid, suffix) + ext)
            if os.path.isfile(candidate):
                found.append(candidate)
    return found


def best_tile_file(candidates):
    scored = []
    for path in candidates:
        base = os.path.basename(path)
        if "_logo" in base or "_icon" in base:
            continue
        size = image_size(path)
        if not size or size[1] <= 0:
            continue
        bare = os.path.splitext(base)[0].isdigit()
        scored.append((path, size[0], size[0] / size[1], bare))
    if not scored:
        return candidates[0] if candidates else None
    wide = [s for s in scored if s[2] >= 1.4]
    pool = wide if wide else scored
    bare_pool = [s for s in pool if s[3]]
    if bare_pool:
        return max(bare_pool, key=lambda s: s[1])[0]
    return max(pool, key=lambda s: s[1])[0]


def adopt_artwork(grid_dir, old_sid, new_sid):
    for src in grid_files(grid_dir, old_sid):
        base = os.path.basename(src)
        dst = os.path.join(grid_dir, str(new_sid) + base[len(str(old_sid)):])
        if not os.path.isfile(dst):
            try:
                shutil.copyfile(src, dst)
            except OSError:
                pass


def find_artwork(grid_dir, sid, old_sids=()):
    direct = grid_files(grid_dir, sid)
    if direct:
        best = best_tile_file(direct)
        if best:
            return "file://" + best
    # El ID del atajo cambia si Heroic/Steam lo reescribe: se adopta el
    # arte guardado bajo un ID anterior del mismo juego y se copia al actual
    for old_sid in old_sids:
        if old_sid == sid:
            continue
        if grid_files(grid_dir, old_sid):
            adopt_artwork(grid_dir, old_sid, sid)
            adopted = grid_files(grid_dir, sid)
            if adopted:
                best_adopted = best_tile_file(adopted)
                if best_adopted:
                    return "file://" + best_adopted
    return None


def collect_shortcuts():
    games = []
    sid_history = load_sid_history()
    history_dirty = False
    for shortcuts_path in glob.glob(
        os.path.join(STEAM_ROOT, "userdata", "*", "config", "shortcuts.vdf")
    ):
        config_dir = os.path.dirname(shortcuts_path)
        grid_dir = os.path.join(config_dir, "grid")
        try:
            entries = parse_shortcuts(shortcuts_path)
        except Exception as e:
            print("Failed to parse {}: {}".format(shortcuts_path, e), file=sys.stderr)
            continue

        for entry in entries:
            try:
                if int(get_ci(entry, "IsHidden") or 0):
                    continue
                name = (get_ci(entry, "AppName") or "").strip()
                exe = get_ci(entry, "Exe") or ""
                if not name or not exe:
                    continue
                # Steam asigna el appid al crear el atajo y lo conserva
                # aunque Heroic lo edite: ese manda sobre el calculado
                sid = shortcut_id(exe, name)
                try:
                    stored = int(get_ci(entry, "appid") or 0) & 0xFFFFFFFF
                except (ValueError, TypeError):
                    stored = 0
                if stored:
                    sid = stored
                key = name.strip().lower()
                known = sid_history.get(key, [])
                if sid not in known:
                    known.append(sid)
                    sid_history[key] = known[-5:]
                    history_dirty = True
                image = find_artwork(grid_dir, sid, [s for s in reversed(known) if s != sid])
                if not image:
                    continue
                try:
                    last_played = int(get_ci(entry, "LastPlayTime") or 0)
                except (ValueError, TypeError):
                    last_played = 0
                full_id = (sid << 32) | 0x02000000
                games.append(
                    {
                        "appid": str(full_id),
                        "name": name,
                        "lastPlayed": last_played,
                        "image": image,
                        "runcmd": "steam steam://rungameid/{}".format(full_id),
                        "source": classify_source(exe),
                    }
                )
            except Exception as e:
                print("Skipping shortcut entry: {}".format(e), file=sys.stderr)
                continue

    if history_dirty:
        save_sid_history(sid_history)

    games.sort(key=lambda g: g["lastPlayed"], reverse=True)
    return games


def main():
    print(json.dumps(collect_shortcuts(), indent=2))


if __name__ == "__main__":
    main()
