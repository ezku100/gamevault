#!/usr/bin/env python3
"""
Scans (i.e. emits) a local json file with games for the game drawer.
The file it looks for is "~/.local/share/gamedrawer/local.json". If
the file does not exist or is unreadable, this scan emits an empty JSON.

The file needs to contain a single JSON array, where each element has
the following keys (at least):
{
    "name": "<The name of the game>",
    "image": "<Boxart image of the game (ideally in 460x215 format)>",
    "runcmd": "<Shell command to start the game>",
}

The "runcmd" command will be executed in a /bin/sh instance, so
common variables (like $HOME) are available.
"""

import os
import json

def main():
    file_path = os.path.expanduser("~/.local/share/gamedrawer/local.json")
    
    try:
        with open(file_path, "r") as f:
            data = json.load(f)
            
        # Ensure the top-level structure is a list
        if not isinstance(data, list):
            print("[]")
            return

        # Filter entries: must be a dict and contain all required keys
        filtered_data = []
        for entry in data:
            if isinstance(entry, dict) and all(
                key in entry for key in ["name", "image", "runcmd"]
            ):
                entry.setdefault("source", "local")
                filtered_data.append(entry)

        print(json.dumps(filtered_data, indent=2))

    except (FileNotFoundError, PermissionError, json.JSONDecodeError, OSError):
        # Handles missing file, permission issues, bad JSON, or other OS errors
        print("[]")

if __name__ == "__main__":
    main()
