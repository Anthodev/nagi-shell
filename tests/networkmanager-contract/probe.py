#!/usr/bin/env python3
import sys
import time

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

SERVICE = "org.freedesktop.NetworkManager"
MANAGER_PATH = "/org/freedesktop/NetworkManager"
MANAGER_IFACE = SERVICE
DEVICE_PATH = MANAGER_PATH + "/Devices/0"
WIRELESS_IFACE = SERVICE + ".Device.Wireless"
AP_IFACE = SERVICE + ".AccessPoint"
ACTIVE_PATH = MANAGER_PATH + "/ActiveConnection/1"
ACTIVE_IFACE = SERVICE + ".Connection.Active"
PROFILE_IFACE = SERVICE + ".Settings.Connection"
PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"
CONTROL_IFACE = "io.github.Anthodev.NagiShell.NetworkManagerContract"
USER_PROFILE = MANAGER_PATH + "/Settings/User"
SYSTEM_PROFILE = MANAGER_PATH + "/Settings/System"
NO_AGENT_PROFILE = MANAGER_PATH + "/Settings/NoAgent"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def wait_until(predicate, description, timeout=3.0):
    context = GLib.MainContext.default()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        while context.pending():
            context.iteration(False)
        if predicate():
            return
        time.sleep(0.005)
    raise AssertionError(f"timed out waiting for {description}")


def changed_receiver(target, interface, sink):
    def receive(changed_interface, changed, invalidated):
        if str(changed_interface) == target:
            sink.append((dict(changed), list(invalidated)))

    interface.connect_to_signal("PropertiesChanged", receive)


def classify_security(flags, wpa_flags, rsn_flags):
    psk = 0x00000100
    sae = 0x00000400
    if rsn_flags & sae:
        return "WPA3-SAE"
    if rsn_flags & psk:
        return "WPA2-PSK"
    if flags == 0 and wpa_flags == 0 and rsn_flags == 0:
        return "open"
    return "secured-other"


def secret_flag_semantics(value):
    labels = []
    if value == 0:
        return ["system-owned"]
    if value & 0x1:
        labels.append("agent-owned")
    if value & 0x2:
        labels.append("not-saved")
    if value & 0x4:
        labels.append("not-required")
    return labels


def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    dbus_daemon = dbus.Interface(
        bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus"),
        "org.freedesktop.DBus",
    )
    require(bool(dbus_daemon.NameHasOwner(SERVICE)), "mock service has no owner")

    manager_object = bus.get_object(SERVICE, MANAGER_PATH)
    manager = dbus.Interface(manager_object, MANAGER_IFACE)
    manager_properties = dbus.Interface(manager_object, PROPERTIES_IFACE)
    control = dbus.Interface(manager_object, CONTROL_IFACE)

    # 1. Initial reads and event-driven radio updates.
    require(bool(manager_properties.Get(MANAGER_IFACE, "WirelessEnabled")), "wireless read")
    require(bool(manager_properties.Get(MANAGER_IFACE, "NetworkingEnabled")), "networking read")
    radio_changes = []
    changed_receiver(MANAGER_IFACE, manager_properties, radio_changes)
    control.ToggleRadios()
    wait_until(lambda: bool(radio_changes), "radio PropertiesChanged")
    changed = radio_changes[-1][0]
    require(changed.get("WirelessEnabled") is not None and not bool(changed["WirelessEnabled"]), "wireless event")
    require(changed.get("NetworkingEnabled") is not None and not bool(changed["NetworkingEnabled"]), "networking event")
    print("PASS 1 radio properties and PropertiesChanged event", flush=True)

    # 2. RequestScan acknowledges first; completion and AP changes arrive as events.
    devices = list(manager.GetDevices())
    require([str(path) for path in devices] == [DEVICE_PATH], "Wi-Fi device enumeration")
    device_object = bus.get_object(SERVICE, DEVICE_PATH)
    wireless = dbus.Interface(device_object, WIRELESS_IFACE)
    device_properties = dbus.Interface(device_object, PROPERTIES_IFACE)
    scan_changes = []
    added = []
    changed_receiver(WIRELESS_IFACE, device_properties, scan_changes)
    wireless.connect_to_signal("AccessPointAdded", lambda path: added.append(str(path)))
    require(int(device_properties.Get(WIRELESS_IFACE, "LastScan")) == -1, "initial LastScan")
    wireless.RequestScan(dbus.Dictionary({}, signature="sv"))
    require(int(device_properties.Get(WIRELESS_IFACE, "LastScan")) == -1, "scan ack is not completion")
    wait_until(
        lambda: any("LastScan" in changed for changed, _ in scan_changes),
        "LastScan PropertiesChanged",
    )
    require(int(device_properties.Get(WIRELESS_IFACE, "LastScan")) == 424242, "scan completion value")
    require(added == [MANAGER_PATH + "/AccessPoint/4"], "AccessPointAdded")
    require(any("AccessPoints" in changed for changed, _ in scan_changes), "AccessPoints update")
    print("PASS 2 RequestScan ack and event-driven AP/LastScan updates", flush=True)

    # 3 and 4. Build the client-side SSID model from individual AP properties.
    access_points = list(device_properties.Get(WIRELESS_IFACE, "AccessPoints"))
    groups = {}
    classifications = {}
    for path_value in access_points:
        path = str(path_value)
        ap_properties = dbus.Interface(bus.get_object(SERVICE, path), PROPERTIES_IFACE)
        ssid = bytes(ap_properties.Get(AP_IFACE, "Ssid"))
        strength = int(ap_properties.Get(AP_IFACE, "Strength"))
        candidate = (strength, path)
        groups.setdefault(ssid, []).append(candidate)
        flags = int(ap_properties.Get(AP_IFACE, "Flags"))
        wpa_flags = int(ap_properties.Get(AP_IFACE, "WpaFlags"))
        rsn_flags = int(ap_properties.Get(AP_IFACE, "RsnFlags"))
        classifications[ssid] = classify_security(flags, wpa_flags, rsn_flags)
    require(len(groups[b"Mesh"]) == 2, "same-SSID BSS candidates were discarded")
    strongest = max(groups[b"Mesh"])
    require(strongest == (83, MANAGER_PATH + "/AccessPoint/2"), "strongest BSS selection")
    print("PASS 3 client groups equal raw SSIDs and keeps strongest AP", flush=True)
    require(classifications[b"Cafe"] == "open", "open classification")
    require(classifications[b"Mesh"] == "WPA2-PSK", "WPA2 PSK classification")
    require(classifications[b"Secure"] == "WPA3-SAE", "WPA3 SAE classification")
    require(classify_security(1, 0, 0x500) == "WPA3-SAE", "transition SAE capability")
    print("PASS 4 Flags/WpaFlags/RsnFlags security classification", flush=True)

    # 5. Hidden SSID shape: complete profile, device path, and '/' specific object.
    settings = dbus.Dictionary(
        {
            "connection": dbus.Dictionary(
                {
                    "id": "Hidden Lab",
                    "uuid": "12345678-1234-4234-9234-123456789abc",
                    "type": "802-11-wireless",
                    "permissions": dbus.Array(["user:test:"], signature="s"),
                },
                signature="sv",
            ),
            "802-11-wireless": dbus.Dictionary(
                {
                    "ssid": dbus.ByteArray(b"Hidden Lab"),
                    "hidden": dbus.Boolean(True),
                    "mode": "infrastructure",
                },
                signature="sv",
            ),
            "802-11-wireless-security": dbus.Dictionary(
                {
                    "key-mgmt": "wpa-psk",
                    "psk": "fixture-passphrase",
                    "psk-flags": dbus.UInt32(1),
                },
                signature="sv",
            ),
        },
        signature="sa{sv}",
    )
    profile_path, active_path = manager.AddAndActivateConnection(
        settings, dbus.ObjectPath(DEVICE_PATH), dbus.ObjectPath("/")
    )
    require(str(profile_path) == USER_PROFILE and str(active_path) == ACTIVE_PATH, "hidden activation result")
    require(bool(control.HiddenShapeValid()), "hidden connection argument shape")
    print("PASS 5 hidden SSID AddAndActivateConnection argument shape", flush=True)

    # 6. Secret flag bits, profile GetSecrets, and the no-agent error contract.
    require(secret_flag_semantics(0) == ["system-owned"], "psk-flags NONE")
    require(secret_flag_semantics(1) == ["agent-owned"], "psk-flags AGENT_OWNED")
    require(secret_flag_semantics(2) == ["not-saved"], "psk-flags NOT_SAVED")
    require(secret_flag_semantics(4) == ["not-required"], "psk-flags NOT_REQUIRED")
    require(secret_flag_semantics(3) == ["agent-owned", "not-saved"], "combined psk flags")
    user_profile = dbus.Interface(bus.get_object(SERVICE, USER_PROFILE), PROFILE_IFACE)
    secrets = user_profile.GetSecrets("802-11-wireless-security")
    security_secrets = secrets["802-11-wireless-security"]
    require(str(security_secrets["psk"]) == "fixture-passphrase", "GetSecrets PSK")
    require(int(security_secrets["psk-flags"]) == 0, "GetSecrets psk-flags")
    try:
        manager.ActivateConnection(
            dbus.ObjectPath(NO_AGENT_PROFILE), dbus.ObjectPath(DEVICE_PATH), dbus.ObjectPath("/")
        )
        raise AssertionError("no-agent activation unexpectedly succeeded")
    except dbus.exceptions.DBusException as error:
        require(
            error.get_dbus_name() == "org.freedesktop.NetworkManager.AgentManager.NoSecrets",
            f"wrong no-agent error: {error.get_dbus_name()}",
        )
    print("PASS 6 psk-flags, GetSecrets, and AgentManager.NoSecrets", flush=True)

    # 7. Signal-driven activation/deactivation plus personal/system deletion ownership.
    active_object = bus.get_object(SERVICE, ACTIVE_PATH)
    active = dbus.Interface(active_object, ACTIVE_IFACE)
    active_states = []
    active.connect_to_signal("StateChanged", lambda state, reason: active_states.append((int(state), int(reason))))
    returned_active = manager.ActivateConnection(
        dbus.ObjectPath(USER_PROFILE), dbus.ObjectPath(DEVICE_PATH), dbus.ObjectPath("/")
    )
    require(str(returned_active) == ACTIVE_PATH, "ActivateConnection active path")
    wait_until(lambda: [state for state, _ in active_states][:2] == [1, 2], "activation states")
    manager.DeactivateConnection(dbus.ObjectPath(ACTIVE_PATH))
    wait_until(lambda: [state for state, _ in active_states] == [1, 2, 3, 4], "deactivation states")
    user_permissions = list(user_profile.GetSettings()["connection"]["permissions"])
    require([str(value) for value in user_permissions] == ["user:test:"], "personal profile permissions")
    system_profile = dbus.Interface(bus.get_object(SERVICE, SYSTEM_PROFILE), PROFILE_IFACE)
    system_permissions = list(system_profile.GetSettings()["connection"]["permissions"])
    require(not system_permissions, "system profile permissions must be empty")

    removed = []
    user_profile.connect_to_signal("Removed", lambda: removed.append(True))
    user_profile.Delete()
    wait_until(lambda: bool(removed), "user profile Removed")
    try:
        system_profile.Delete()
        raise AssertionError("system profile deletion unexpectedly succeeded")
    except dbus.exceptions.DBusException as error:
        require(
            error.get_dbus_name() == "org.freedesktop.NetworkManager.Settings.PermissionDenied",
            f"wrong system deletion error: {error.get_dbus_name()}",
        )
    print("PASS 7 activation lifecycle, Deactivate, and profile ownership", flush=True)

    # 8. Remove the fixture owner; capability detection is a bus-name query, not a crash.
    control.Quit()
    wait_until(lambda: not bool(dbus_daemon.NameHasOwner(SERVICE)), "mock owner exit")
    require(SERVICE not in [str(name) for name in dbus_daemon.ListNames()], "service remained listed")
    try:
        bus.call_blocking(
            SERVICE,
            MANAGER_PATH,
            MANAGER_IFACE,
            "GetDevices",
            "",
            (),
            timeout=1,
        )
        raise AssertionError("absent service call unexpectedly succeeded")
    except dbus.exceptions.DBusException as error:
        require(
            error.get_dbus_name()
            in ("org.freedesktop.DBus.Error.ServiceUnknown", "org.freedesktop.DBus.Error.NameHasNoOwner"),
            f"unexpected absent-service error: {error.get_dbus_name()}",
        )
    print("PASS 8 graceful capability detection when NM has no owner", flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"FAIL networkmanager-contract: {error}", file=sys.stderr, flush=True)
        sys.exit(1)
