#!/usr/bin/env python3

import json
import os
import select
import subprocess
import sys
import time
from pathlib import Path

import dbus


def fail(message, helper=None):
    print(f"wallpaper-service: FAIL: {message}", file=sys.stderr, flush=True)
    if helper is not None:
        helper.kill()
    raise SystemExit(1)


def send(helper, payload):
    helper.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
    helper.stdin.flush()


def next_event(helper, event_type, predicate=lambda event: True, timeout=10):
    deadline = time.monotonic() + timeout
    seen = []
    while time.monotonic() < deadline:
        ready, _, _ = select.select([helper.stdout], [], [], max(0, deadline - time.monotonic()))
        if not ready:
            break
        line = helper.stdout.readline()
        if not line:
            stderr = helper.stderr.read(2048)
            fail(f"helper exited before {event_type}: {stderr}", helper)
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            fail("helper emitted malformed JSON", helper)
        seen.append(event)
        if event.get("type") == event_type and predicate(event):
            return event
    fail(f"timed out waiting for {event_type}; seen={seen}", helper)


def main():
    if len(sys.argv) != 4:
        print("usage: probe.py <helper> <image> <library-root>", file=sys.stderr)
        return 2
    helper_path = sys.argv[1]
    image_path = str(Path(sys.argv[2]).resolve())
    image_url = Path(image_path).as_uri()
    library_root = Path(sys.argv[3]).resolve()
    environment = dict(os.environ)
    environment["QT_QPA_PLATFORM"] = "wayland"
    helper = subprocess.Popen(
        [helper_path],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        env=environment,
    )

    current = next_event(helper, "current", lambda event: event.get("status") == "Multiple")
    if not (
        current.get("status") == "Multiple"
        and current.get("multiple") is True
        and current.get("unsupported") is True
        and current.get("available") is False
        and len(current.get("screens", [])) == 2
        and "imagePath" not in current
    ):
        fail(f"mixed static/plugin readback was not represented explicitly: {current}", helper)

    send(helper, {"op": "interest", "active": True, "roots": [str(library_root)]})
    library = next_event(
        helper,
        "library",
        lambda event: event.get("status") == "ready" and len(event.get("images", [])) == 1,
    )
    if library["images"][0]["name"] != "selected.png":
        fail("approved root did not publish its bounded static image", helper)
    selected = library_root / "selected.png"
    renamed = library_root / "renamed.png"
    selected.rename(renamed)
    changed = next_event(
        helper,
        "library",
        lambda event: event.get("status") == "ready"
        and len(event.get("images", [])) == 1
        and event["images"][0]["name"] == "renamed.png",
    )
    if changed.get("truncated"):
        fail("small renamed library was unexpectedly truncated", helper)
    renamed.unlink()
    deleted = next_event(
        helper,
        "library",
        lambda event: event.get("status") == "ready" and event.get("images") == [],
    )
    if deleted.get("directories") == []:
        fail("deleted image removed the approved root itself", helper)
    send(helper, {"op": "interest", "active": True, "roots": []})
    next_event(helper, "library", lambda event: event.get("status") == "empty")
    send(helper, {"op": "preview-path", "path": image_path})
    preview = next_event(helper, "preview", lambda event: event.get("status") == "ready")
    if not (
        preview.get("outsideLibrary") is True
        and preview.get("name") == Path(image_path).name
        and preview.get("thumbnail", "").startswith("data:image/png;base64,")
        and image_path not in json.dumps(preview)
    ):
        fail("outside-root preview leaked or silently joined the library", helper)

    send(helper, {"op": "apply", "id": preview["id"]})
    next_event(helper, "apply", lambda event: event.get("status") == "pending")
    applied = next_event(helper, "apply", lambda event: event.get("status") != "pending")
    results = applied.get("results", [])
    if not (
        applied.get("status") == "partial"
        and applied.get("success") is False
        and applied.get("partial") is True
        and applied.get("rollbackAttempted") is False
        and len(results) == 2
        and results[0] == {"label": "Display 1", "status": "success"}
        and results[1] == {"label": "Display 2", "status": "failed"}
    ):
        fail("partial all-display apply was not classified per display", helper)

    bus = dbus.SessionBus()
    shell = bus.get_object("org.kde.plasmashell", "/PlasmaShell")
    interface = dbus.Interface(shell, "org.kde.PlasmaShell")
    interface.SetWallpaper(
        "org.kde.image",
        {"Image": dbus.String(image_url, variant_level=1)},
        dbus.UInt32(1),
    )
    confirmed = next_event(
        helper,
        "current",
        lambda event: event.get("status") == "Ready" and event.get("available") is True,
    )
    if not (
        confirmed.get("accent") == "#D94A38"
        and confirmed.get("multiple") is False
        and len(confirmed.get("screens", [])) == 2
        and image_path not in json.dumps(confirmed)
    ):
        fail("external Plasma change did not become the confirmed authority", helper)

    send(helper, {"op": "interest", "active": False, "roots": []})
    idle = next_event(helper, "library", lambda event: event.get("status") == "idle")
    if idle.get("images") != [] or idle.get("directories") != []:
        fail("closed page retained library projection", helper)
    send(helper, {"op": "shutdown"})
    helper.wait(timeout=5)
    if helper.returncode != 0:
        fail("helper did not shut down cleanly")
    print("wallpaper-service: mixed, library-change, partial, external-change, and unload contracts verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
