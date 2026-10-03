#!/usr/bin/env python3
"""
Geometría (px lógicos) de la pantalla con el foco: {"x":..,"y":..,"width":..,"height":..}.

Pregunta a KWin el output activo y lo cruza con kscreen-doctor.
Si algo falla, responde {} y el QML usa la pantalla del panel.

Sin dependencias externas, solo stdlib.
"""

import json
import os
import subprocess
import sys

QDBUS = None
for _p in ("/usr/bin/qdbus6", "/usr/bin/qdbus"):
    if os.path.isfile(_p):
        QDBUS = _p
        break


def active_output_name():
    if not QDBUS:
        return None
    try:
        out = subprocess.run(
            [QDBUS, "org.kde.KWin", "/KWin",
             "org.kde.KWin.activeOutputName"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, timeout=3, check=False,
        ).stdout.strip()
        return out or None
    except (OSError, subprocess.TimeoutExpired):
        return None


def outputs():
    try:
        out = subprocess.run(
            ["kscreen-doctor", "--json"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, timeout=5, check=False,
        ).stdout
        data = json.loads(out)
        if isinstance(data, dict) and isinstance(data.get("outputs"), list):
            return [o for o in data["outputs"]
                    if isinstance(o, dict) and o.get("enabled")]
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return []


def geometry(out):
    try:
        pos = out.get("pos") or {}
        size = out.get("size") or {}
        scale = float(out.get("scale") or 1)
        if scale <= 0:
            scale = 1
        return {
            "x": int(pos.get("x", 0)),
            "y": int(pos.get("y", 0)),
            "width": int(int(size.get("width", 0)) / scale),
            "height": int(int(size.get("height", 0)) / scale),
        }
    except (ValueError, TypeError, AttributeError):
        return None


def main():
    result = {}
    outs = outputs()
    if outs:
        name = active_output_name()
        target = None
        if name:
            lowered = name.lower()
            for o in outs:
                if str(o.get("name", "")).lower() == lowered:
                    target = o
                    break
        if target is None:
            for o in outs:
                if o.get("priority") == 1:
                    target = o
                    break
        if target is None:
            target = outs[0]
        geo = geometry(target)
        if geo and geo["width"] > 0 and geo["height"] > 0:
            result = geo
    print(json.dumps(result))


if __name__ == "__main__":
    main()
