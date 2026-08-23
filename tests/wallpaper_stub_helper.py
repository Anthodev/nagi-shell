#!/usr/bin/env python3

import json
import signal
import sys

snapshots = (
    {
        "generation": 1,
        "available": True,
        "status": "Ready",
        "imagePath": "/tmp/wallpaper-colorful.png",
        "accent": "#D94A38",
    },
    {
        "generation": 2,
        "available": True,
        "status": "Ready",
        "imagePath": "relative/private-path.png",
        "accent": "#FFFFFF",
    },
    {
        "generation": 2,
        "available": False,
        "status": "UnsupportedPlugin",
        "imagePath": "",
        "accent": "",
    },
    {
        "generation": 3,
        "available": False,
        "status": "Missing",
        "imagePath": "/tmp/private-path-must-not-leak.png",
        "accent": "",
    },
    {
        "generation": 3,
        "available": True,
        "status": "Ready",
        "imagePath": "/tmp/wallpaper-oversized.png",
        "accent": "#1E6FD9",
    },
)

for snapshot in snapshots:
    print(json.dumps(snapshot, separators=(",", ":")), flush=True)

signal.pause()
