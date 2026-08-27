#!/usr/bin/env python3
"""Issue #70 gate 9 mock: a deliberately limited org.kde.plasmashell fixture.

Models only the documented scripting surface (evaluateScript(s)->s plus the
observed wallpaper(u)/setWallpaper/wallpaperChanged shapes) with sequential,
non-transactional containment writes, matching Plasma 6.7.4 source behavior.
"""
import json
import os

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop

dbus.set_default_main_loop(DBusGMainLoop(set_as_default=True))

PLUGIN_AVAILABLE = os.environ.get("MOCK_IMAGE_PLUGIN", "1") == "1"
SESSION_FILE = os.environ.get("MOCK_STATE_FILE", "/tmp/mock-wallpaper-state.json")
PARTIAL_APPLY = os.environ.get("MOCK_PARTIAL_APPLY", "0") == "1"


class Containment:
    def __init__(self, activity, screen, plugin, image):
        self.activity = activity
        self.screen = screen
        self.plugin = plugin
        self.config = {"Image": image} if plugin else {}


STATE = {
    "activities": ["act1", "act2"],
    "current": "act1",
    "known_plugins": {"org.kde.image": "/usr/share/wallpapers"} if PLUGIN_AVAILABLE else {},
    "containments": [
        Containment("act1", 0, "org.kde.image", "file:///usr/share/wallpapers/old-a.png"),
        Containment("act1", 1, "org.kde.potd", ""),
        Containment("act2", 0, "org.kde.image", "file:///usr/share/wallpapers/other-activity.png"),
    ],
}


def save_state():
    import json
    data = {
        "containments": [
            {
                "activity": c.activity,
                "screen": c.screen,
                "plugin": c.plugin,
                "config": dict(c.config),
            }
            for c in STATE["containments"]
        ]
    }
    with open(SESSION_FILE, "w") as handle:
        json.dump(data, handle)


class PlasmaShellMock(dbus.service.Object):
    def __init__(self, connection):
        self.bus = connection
        super().__init__(connection, "/PlasmaShell")

    def current_containments(self):
        return [c for c in STATE["containments"] if c.activity == STATE["current"]]

    @dbus.service.method("org.kde.PlasmaShell", in_signature="u", out_signature="a{sv}")
    def Wallpaper(self, screen):  # noqa: N802 - D-Bus member name
        for containment in self.current_containments():
            if containment.screen == screen:
                result = {"wallpaperPlugin": containment.plugin}
                if containment.plugin == "org.kde.image" and containment.config.get("Image"):
                    result["Image"] = containment.config["Image"]
                return result
        return {}
    @dbus.service.method("org.kde.PlasmaShell", in_signature="u", out_signature="a{sv}")
    def wallpaper(self, screen):
        return self.Wallpaper(screen)


    @dbus.service.method("org.kde.PlasmaShell", in_signature="sa{sv}u", out_signature="")
    def SetWallpaper(self, plugin, parameters, screen):  # noqa: N802
        for containment in self.current_containments():
            if containment.screen == screen:
                containment.plugin = plugin
                if "Image" in parameters:
                    containment.config["Image"] = str(parameters["Image"])
        self.WallpaperChanged(screen)
        self.wallpaperChanged(screen)

    @dbus.service.signal("org.kde.PlasmaShell", signature="u")
    def WallpaperChanged(self, screen):  # noqa: N802
        pass
    @dbus.service.signal("org.kde.PlasmaShell", signature="u")
    def wallpaperChanged(self, screen):
        pass


    @dbus.service.method(
        "org.kde.PlasmaShell", in_signature="s", out_signature="s",
        sender_keyword="sender")
    def EvaluateScript(self, script, sender=None):  # noqa: N802
        output = []
        lines = [line.strip() for line in script.splitlines() if line.strip()]
        # Recognize ONLY the generated grammar; anything else is a script error.
        for line in lines:
            if line.startswith("throw "):
                raise dbus.DBusException(
                    "Injected script failure",
                    name="org.freedesktop.DBus.Error.Failed")
        applied = []
        for containment in self.current_containments():
            if PARTIAL_APPLY and applied:
                save_state()
                raise dbus.DBusException(
                    "Injected partial apply",
                    name="org.freedesktop.DBus.Error.Failed")
            if "knownWallpaperPlugins()" in "".join(lines):
                if "org.kde.image" not in STATE["known_plugins"]:
                    raise dbus.DBusException(
                        "Required wallpaper plugin unavailable: org.kde.image",
                        name="org.freedesktop.DBus.Error.Failed")
            target = None
            for line in lines:
                if line.startswith("const image ="):
                    literal = line.split("=", 1)[1].strip().rstrip(";")
                    image = json.loads(literal) if literal.startswith('"') else literal.strip("'")
                elif line == "throw new Error('injected-after-first-screen');" and applied:
                    raise dbus.DBusException(
                        "Injected script failure",
                        name="org.freedesktop.DBus.Error.Failed")
                elif line.startswith("desktop.wallpaperPlugin ="):
                    plugin = line.split("=", 1)[1].strip().rstrip(";").strip("'")
                    containment.plugin = "org.kde.image" if plugin == "plugin" else plugin
                    target = containment
                elif line.startswith("desktop.writeConfig('Image',") and target is not None:
                    containment.config["Image"] = image
                    applied.append(containment.screen)
                elif line.startswith("print('requested screen="):
                    output.append(f"requested screen={containment.screen}")
                elif line.startswith("print(desktop.screen"):
                    output.append(
                        f"screen={containment.screen} plugin={containment.plugin} "
                        f"image={containment.config.get('Image', '')}"
                    )
        save_state()
        return "\n".join(output)
    @dbus.service.method(
        "org.kde.PlasmaShell", in_signature="s", out_signature="s",
        sender_keyword="sender")
    def evaluateScript(self, script, sender=None):
        return self.EvaluateScript(script, sender)



def main():
    override = os.environ.get("MOCK_PRESEED")
    if override:
        seeded = json.loads(override)
        STATE["containments"] = [
            Containment(c["activity"], c["screen"], c["plugin"], c.get("image", ""))
            for c in seeded
        ]
    save_state()
    bus = dbus.SessionBus()
    name = dbus.service.BusName("org.kde.plasmashell", bus)
    PlasmaShellMock(bus)
    from gi.repository import GLib

    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
