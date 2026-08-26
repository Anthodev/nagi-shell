#!/usr/bin/env python3
"""Issue #70 gate 9 client probe: exercises the documented evaluateScript
wallpaper write path against the private mock and classifies every outcome."""
import os
import sys

import dbus

PASS = []
FAIL = []


def record(number, ok, detail):
    (PASS if ok else FAIL).append(detail)
    prefix = "PASS" if ok else "FAIL"
    print(f"{prefix} {number}: {detail}", flush=True)


WRITE_TEMPLATE = """\
const plugin = 'org.kde.image';
const image = '%(image)s';
const available = knownWallpaperPlugins();
if (!Object.prototype.hasOwnProperty.call(available, plugin)) %(guard)s
for (const desktop of desktopsForActivity(currentActivity())) {
    desktop.wallpaperPlugin = plugin;
    desktop.currentConfigGroup = ['Wallpaper', plugin, 'General'];
    desktop.writeConfig('Image', image);
    desktop.reloadConfig();
    print('requested screen=' + desktop.screen);
}
"""

READBACK_SCRIPT = """\
for (const desktop of desktopsForActivity(currentActivity())) {
    desktop.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General'];
    print(desktop.screen, desktop.wallpaperPlugin, desktop.readConfig('Image', ''));
}
"""


def call_evaluate(script):
    bus = dbus.SessionBus()
    shell = bus.get_object("org.kde.plasmashell", "/PlasmaShell")
    return shell.EvaluateScript(script, dbus_interface="org.kde.PlasmaShell")


def readback():
    return call_evaluate(READBACK_SCRIPT)


def main():
    image_url = "file:///tmp/nagi-wallpaper-target.jpg"

    # 1. All-screens write on the current activity + fresh readback.
    try:
        reply = call_evaluate(WRITE_TEMPLATE % {"image": image_url, "guard": "{ throw new Error(plugin); }"})
        wrote_two = reply.count("requested screen=") == 2
        back = readback()
        ok = wrote_two and back.count(image_url) >= 2
        record(1, ok, f"all-screens write+readback (reply_lines={reply.count(chr(10)) + 1}, readback_has_image={ok})")
    except dbus.DBusException as error:
        record(1, False, f"all-screens write raised {error.get_dbus_name()}")

    # 2. Mixed current state: other activity stays untouched.
    state = open(os.environ["MOCK_STATE_FILE"]).read()
    record(2, "other-activity.png" in state and image_url in state,
           "mixed state: non-current activity containment untouched")

    # 3. Missing-file URL accepted as configuration (renderer success unprovable here).
    ghost = "file:///nonexistent/ghost.png"
    try:
        call_evaluate(WRITE_TEMPLATE % {"image": ghost, "guard": "{ throw new Error(plugin); }"})
        back = readback()
        record(3, ghost in back, "nonexistent image URL stored as string without validation")
    except dbus.DBusException as error:
        record(3, False, f"ghost URL write raised {error.get_dbus_name()}")

    # 4. Sequential partial failure: earlier writes persist, outcome indeterminate.
    partial = WRITE_TEMPLATE % {"image": image_url, "guard": "{ throw new Error(plugin); }"}
    partial += "throw new Error('injected-after-first-screen');\n"
    partial = partial.replace(
        "for (const desktop of desktopsForActivity(currentActivity())) {",
        "let seen = 0;\nfor (const desktop of desktopsForActivity(currentActivity())) {\n    seen += 1;\n    if (seen > 1) throw new Error('injected');",
        1)
    try:
        call_evaluate(partial)
        record(4, False, "injected mid-loop failure did not surface as D-Bus error")
    except dbus.DBusException as error:
        failed = error.get_dbus_name() == "org.freedesktop.DBus.Error.Failed"
        persisted = image_url in readback() or ghost in readback()
        record(4, failed and persisted,
               f"partial failure classified (error={error.get_dbus_name()}, earlier_writes_persisted={persisted})")

    # 5. Preflight guard: unavailable plugin makes the script itself fail closed.
    if os.environ.get("MOCK_IMAGE_PLUGIN", "1") != "1":
        try:
            call_evaluate(WRITE_TEMPLATE % {"image": image_url, "guard": "{ throw new Error(plugin); }"})
            record(5, False, "preflight guard did not stop execution without org.kde.image")
        except dbus.DBusException as error:
            record(5, True, f"preflight plugin guard failed closed ({error.get_dbus_name()})")

    print(f"SUMMARY pass={len(PASS)} fail={len(FAIL)}", flush=True)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
