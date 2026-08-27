#!/usr/bin/env python3

import json
import os
import sys

THUMBNAIL = (
    "data:image/png;base64,"
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


def emit(payload):
    print(json.dumps(payload, separators=(",", ":")), flush=True)


emit({
    "type": "current",
    "generation": 1,
    "available": True,
    "status": "Ready",
    "multiple": False,
    "unsupported": False,
    "accent": "#D94A38",
    "screens": [{"label": "Display 1", "status": "Ready", "supported": True}],
})
emit({
    "type": "current",
    "generation": 2,
    "available": False,
    "status": "UnsupportedPlugin",
    "multiple": False,
    "unsupported": True,
    "accent": "",
    "screens": [{"label": "Display 1", "status": "UnsupportedPlugin", "supported": False}],
})
emit({
    "type": "current",
    "generation": 3,
    "available": True,
    "status": "Ready",
    "multiple": False,
    "unsupported": False,
    "accent": "#1E6FD9",
    "screens": [{"label": "Display 1", "status": "Ready", "supported": True}],
})

for raw in sys.stdin:
    try:
        command = json.loads(raw)
    except json.JSONDecodeError:
        continue
    operation = command.get("op")
    if operation == "interest" and command.get("active"):
        emit({
            "type": "library",
            "generation": 1,
            "status": "ready",
            "scanning": False,
            "truncated": False,
            "visited": 2,
            "elapsedMs": 4,
            "directories": [{
                "id": "d000000000000000000000000",
                "parentId": "",
                "rootId": "d000000000000000000000000",
                "name": "Wallpapers",
                "breadcrumb": "Wallpapers",
            }],
            "images": [{
                "id": "i000000000000000000000000",
                "directoryId": "d000000000000000000000000",
                "name": "fixture.png",
                "byteSize": 78,
                "modifiedMs": 1,
                "width": 8,
                "height": 8,
            }],
        })
    elif operation == "thumbnail":
        emit({
            "type": "thumbnail",
            "id": command.get("id", ""),
            "status": "ready",
            "data": THUMBNAIL,
        })
    elif operation == "preview":
        emit({"type": "preview", "generation": 1, "status": "loading"})
        emit({
            "type": "preview",
            "generation": 2,
            "status": "ready",
            "id": "c000000000000000000000000",
            "name": "fixture.png",
            "thumbnail": THUMBNAIL,
            "accent": "#AA55CC",
            "width": 8,
            "height": 8,
            "byteSize": 78,
            "outsideLibrary": False,
        })
    elif operation == "apply":
        emit({"type": "apply", "generation": 1, "status": "pending"})
        emit({
            "type": "apply",
            "generation": 2,
            "status": "partial",
            "success": False,
            "partial": True,
            "rollbackAttempted": False,
            "results": [
                {"label": "Display 1", "status": "success"},
                {"label": "Display 2", "status": "failed"},
            ],
        })
    elif operation == "crash":
        os._exit(17)
    elif operation == "shutdown":
        break
