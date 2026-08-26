#!/usr/bin/env python3
import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

SERVICE = "org.freedesktop.NetworkManager"
MANAGER_PATH = "/org/freedesktop/NetworkManager"
MANAGER_IFACE = SERVICE
DEVICE_PATH = MANAGER_PATH + "/Devices/0"
DEVICE_IFACE = SERVICE + ".Device"
WIRELESS_IFACE = DEVICE_IFACE + ".Wireless"
AP_IFACE = SERVICE + ".AccessPoint"
ACTIVE_PATH = MANAGER_PATH + "/ActiveConnection/1"
ACTIVE_IFACE = SERVICE + ".Connection.Active"
PROFILE_IFACE = SERVICE + ".Settings.Connection"
PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"
CONTROL_IFACE = "io.github.Anthodev.NagiShell.NetworkManagerContract"
USER_PROFILE = MANAGER_PATH + "/Settings/User"
SYSTEM_PROFILE = MANAGER_PATH + "/Settings/System"
NO_AGENT_PROFILE = MANAGER_PATH + "/Settings/NoAgent"


def variant_dict(values):
    return dbus.Dictionary(values, signature="sv")


class PropertiesObject(dbus.service.Object):
    @dbus.service.method(PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        try:
            return self.properties(interface)[name]
        except KeyError as error:
            raise dbus.exceptions.DBusException(
                f"unknown property {interface}.{name}",
                name="org.freedesktop.DBus.Error.UnknownProperty",
            ) from error

    @dbus.service.method(PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return variant_dict(self.properties(interface))

    @dbus.service.signal(PROPERTIES_IFACE, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass


class AccessPoint(PropertiesObject):
    def __init__(self, bus, path, ssid, strength, flags, wpa_flags, rsn_flags, bssid):
        super().__init__(bus, path)
        self.path = path
        self.ssid = dbus.ByteArray(ssid)
        self.strength = dbus.Byte(strength)
        self.flags = dbus.UInt32(flags)
        self.wpa_flags = dbus.UInt32(wpa_flags)
        self.rsn_flags = dbus.UInt32(rsn_flags)
        self.bssid = bssid

    def properties(self, interface):
        if interface != AP_IFACE:
            return {}
        return {
            "Ssid": self.ssid,
            "Strength": self.strength,
            "Flags": self.flags,
            "WpaFlags": self.wpa_flags,
            "RsnFlags": self.rsn_flags,
            "HwAddress": self.bssid,
            "Frequency": dbus.UInt32(5180),
            "Mode": dbus.UInt32(2),
        }


class WirelessDevice(PropertiesObject):
    def __init__(self, bus, access_points):
        super().__init__(bus, DEVICE_PATH)
        self.access_points = access_points
        self.visible_paths = list(access_points)[:3]
        self.last_scan = dbus.Int64(-1)

    def properties(self, interface):
        if interface == DEVICE_IFACE:
            return {
                "DeviceType": dbus.UInt32(2),
                "State": dbus.UInt32(30),
                "ActiveConnection": dbus.ObjectPath("/"),
            }
        if interface == WIRELESS_IFACE:
            return {
                "AccessPoints": dbus.Array(
                    [dbus.ObjectPath(path) for path in self.visible_paths], signature="o"
                ),
                "LastScan": self.last_scan,
                "ActiveAccessPoint": dbus.ObjectPath("/"),
                "Mode": dbus.UInt32(2),
                "WirelessCapabilities": dbus.UInt32(0x7F),
            }
        return {}

    @dbus.service.method(WIRELESS_IFACE, in_signature="a{sv}", out_signature="")
    def RequestScan(self, options):
        if "ssid" in options:
            raise dbus.exceptions.DBusException(
                "singular ssid option is invalid",
                name="org.freedesktop.DBus.Error.InvalidArgs",
            )
        GLib.timeout_add(20, self._finish_scan)

    def _finish_scan(self):
        new_path = list(self.access_points)[3]
        self.visible_paths.append(new_path)
        self.last_scan = dbus.Int64(424242)
        self.AccessPointAdded(dbus.ObjectPath(new_path))
        self.PropertiesChanged(
            WIRELESS_IFACE,
            variant_dict(
                {
                    "AccessPoints": dbus.Array(
                        [dbus.ObjectPath(path) for path in self.visible_paths], signature="o"
                    ),
                    "LastScan": self.last_scan,
                }
            ),
            dbus.Array([], signature="s"),
        )
        return False

    @dbus.service.method(WIRELESS_IFACE, in_signature="", out_signature="ao")
    def GetAllAccessPoints(self):
        return dbus.Array(
            [dbus.ObjectPath(path) for path in self.visible_paths], signature="o"
        )

    @dbus.service.signal(WIRELESS_IFACE, signature="o")
    def AccessPointAdded(self, path):
        pass


class ActiveConnection(PropertiesObject):
    def __init__(self, bus):
        super().__init__(bus, ACTIVE_PATH)
        self.state = dbus.UInt32(0)

    def properties(self, interface):
        return {"State": self.state} if interface == ACTIVE_IFACE else {}

    def transition(self, state, reason):
        self.state = dbus.UInt32(state)
        self.StateChanged(self.state, dbus.UInt32(reason))
        self.PropertiesChanged(
            ACTIVE_IFACE,
            variant_dict({"State": self.state}),
            dbus.Array([], signature="s"),
        )
        return False

    @dbus.service.signal(ACTIVE_IFACE, signature="uu")
    def StateChanged(self, state, reason):
        pass


class Profile(PropertiesObject):
    def __init__(self, bus, path, user_owned):
        super().__init__(bus, path)
        self.user_owned = user_owned

    def properties(self, interface):
        return {}
    @dbus.service.method(PROFILE_IFACE, in_signature="", out_signature="a{sa{sv}}")
    def GetSettings(self):
        permissions = (
            dbus.Array(["user:test:"], signature="s")
            if self.user_owned
            else dbus.Array([], signature="s")
        )
        return dbus.Dictionary(
            {
                "connection": variant_dict(
                    {
                        "id": "Personal fixture" if self.user_owned else "System fixture",
                        "type": "802-11-wireless",
                        "permissions": permissions,
                    }
                ),
                "802-11-wireless-security": variant_dict(
                    {"key-mgmt": "wpa-psk", "psk-flags": dbus.UInt32(0)}
                ),
            },
            signature="sa{sv}",
        )


    @dbus.service.method(PROFILE_IFACE, in_signature="s", out_signature="a{sa{sv}}")
    def GetSecrets(self, setting_name):
        if setting_name != "802-11-wireless-security":
            return dbus.Dictionary({}, signature="sa{sv}")
        return dbus.Dictionary(
            {
                setting_name: variant_dict(
                    {"psk": "fixture-passphrase", "psk-flags": dbus.UInt32(0)}
                )
            },
            signature="sa{sv}",
        )

    @dbus.service.method(PROFILE_IFACE, in_signature="", out_signature="")
    def Delete(self):
        if not self.user_owned:
            raise dbus.exceptions.DBusException(
                "system profile requires authorization",
                name="org.freedesktop.NetworkManager.Settings.PermissionDenied",
            )
        self.Removed()

    @dbus.service.signal(PROFILE_IFACE, signature="")
    def Removed(self):
        pass


class Manager(PropertiesObject):
    def __init__(self, bus, loop, device, active):
        super().__init__(bus, MANAGER_PATH)
        self.bus = bus
        self.loop = loop
        self.device = device
        self.active = active
        self.wireless_enabled = True
        self.networking_enabled = True
        self.hidden_shape_valid = False

    def properties(self, interface):
        if interface != MANAGER_IFACE:
            return {}
        return {
            "WirelessEnabled": dbus.Boolean(self.wireless_enabled),
            "NetworkingEnabled": dbus.Boolean(self.networking_enabled),
            "WirelessHardwareEnabled": dbus.Boolean(True),
            "Version": "1.56.1-fixture",
        }

    @dbus.service.method(MANAGER_IFACE, in_signature="", out_signature="ao")
    def GetDevices(self):
        return dbus.Array([dbus.ObjectPath(DEVICE_PATH)], signature="o")

    @dbus.service.method(MANAGER_IFACE, in_signature="ooo", out_signature="o")
    def ActivateConnection(self, connection, device, specific_object):
        if str(connection) == NO_AGENT_PROFILE:
            raise dbus.exceptions.DBusException(
                "no Secret Agent returned secrets",
                name="org.freedesktop.NetworkManager.AgentManager.NoSecrets",
            )
        if str(device) != DEVICE_PATH or str(specific_object) not in ("/", *self.device.visible_paths):
            raise dbus.exceptions.DBusException(
                "invalid activation target", name="org.freedesktop.DBus.Error.InvalidArgs"
            )
        GLib.timeout_add(20, self.active.transition, 1, 1)
        GLib.timeout_add(40, self.active.transition, 2, 1)
        return dbus.ObjectPath(ACTIVE_PATH)

    @dbus.service.method(MANAGER_IFACE, in_signature="o", out_signature="")
    def DeactivateConnection(self, active_connection):
        if str(active_connection) != ACTIVE_PATH:
            raise dbus.exceptions.DBusException(
                "unknown active connection", name="org.freedesktop.DBus.Error.InvalidArgs"
            )
        GLib.timeout_add(20, self.active.transition, 3, 2)
        GLib.timeout_add(40, self.active.transition, 4, 2)

    @dbus.service.method(MANAGER_IFACE, in_signature="a{sa{sv}}oo", out_signature="oo")
    def AddAndActivateConnection(self, settings, device, specific_object):
        wireless = settings.get("802-11-wireless", {})
        connection = settings.get("connection", {})
        security = settings.get("802-11-wireless-security", {})
        self.hidden_shape_valid = (
            str(device) == DEVICE_PATH
            and str(specific_object) == "/"
            and bytes(wireless.get("ssid", b"")) == b"Hidden Lab"
            and bool(wireless.get("hidden", False))
            and str(wireless.get("mode", "")) == "infrastructure"
            and str(connection.get("type", "")) == "802-11-wireless"
            and list(connection.get("permissions", [])) == ["user:test:"]
            and str(security.get("key-mgmt", "")) == "wpa-psk"
            and int(security.get("psk-flags", 99)) == 1
        )
        return dbus.ObjectPath(USER_PROFILE), dbus.ObjectPath(ACTIVE_PATH)

    @dbus.service.method(CONTROL_IFACE, in_signature="", out_signature="")
    def ToggleRadios(self):
        self.wireless_enabled = False
        self.networking_enabled = False
        self.PropertiesChanged(
            MANAGER_IFACE,
            variant_dict(
                {
                    "WirelessEnabled": dbus.Boolean(False),
                    "NetworkingEnabled": dbus.Boolean(False),
                }
            ),
            dbus.Array([], signature="s"),
        )

    @dbus.service.method(CONTROL_IFACE, in_signature="", out_signature="b")
    def HiddenShapeValid(self):
        return dbus.Boolean(self.hidden_shape_valid)

    @dbus.service.method(CONTROL_IFACE, in_signature="", out_signature="")
    def Quit(self):
        GLib.idle_add(self.loop.quit)


def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    loop = GLib.MainLoop()
    name = dbus.service.BusName(SERVICE, bus=bus, do_not_queue=True)
    aps = {}
    specs = [
        ("/AccessPoint/1", b"Mesh", 42, 1, 0, 0x100, "02:00:00:00:00:01"),
        ("/AccessPoint/2", b"Mesh", 83, 1, 0, 0x100, "02:00:00:00:00:02"),
        ("/AccessPoint/3", b"Cafe", 61, 0, 0, 0, "02:00:00:00:00:03"),
        ("/AccessPoint/4", b"Secure", 70, 1, 0, 0x400, "02:00:00:00:00:04"),
    ]
    for suffix, ssid, strength, flags, wpa, rsn, bssid in specs:
        path = MANAGER_PATH + suffix
        aps[path] = AccessPoint(bus, path, ssid, strength, flags, wpa, rsn, bssid)
    device = WirelessDevice(bus, aps)
    active = ActiveConnection(bus)
    profiles = [
        Profile(bus, USER_PROFILE, True),
        Profile(bus, SYSTEM_PROFILE, False),
        Profile(bus, NO_AGENT_PROFILE, True),
    ]
    manager = Manager(bus, loop, device, active)
    print("READY", flush=True)
    loop.run()
    _keep_alive = (name, manager, device, active, profiles, aps)
    return 0


if __name__ == "__main__":
    sys.exit(main())
