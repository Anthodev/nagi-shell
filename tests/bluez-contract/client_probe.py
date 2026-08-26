#!/usr/bin/env python3
import asyncio
import os
import sys

from dbus_next import Message, MessageType, Variant
from dbus_next.aio import MessageBus

BLUEZ = "org.bluez"
ADAPTER_PATH = "/org/bluez/hci0"
DEVICE_PATH = "/org/bluez/hci0/dev_01_02_03_04_05_06"
OBJECT_MANAGER = "org.freedesktop.DBus.ObjectManager"
PROPERTIES = "org.freedesktop.DBus.Properties"
ADAPTER = "org.bluez.Adapter1"
DEVICE = "org.bluez.Device1"
AGENT_MANAGER = "org.bluez.AgentManager1"
MOCK = "org.bluez.Mock1"


class ProbeFailure(RuntimeError):
    pass


def require(condition, detail):
    if not condition:
        raise ProbeFailure(detail)


def require_ok(reply, operation):
    if reply.message_type == MessageType.ERROR:
        raise ProbeFailure(f"{operation}: {reply.error_name}: {reply.body}")
    return reply


def require_error(reply, expected, operation):
    require(reply.message_type == MessageType.ERROR, f"{operation}: expected {expected}, got success")
    require(reply.error_name == expected, f"{operation}: expected {expected}, got {reply.error_name}")


async def wait_event(event, detail):
    try:
        await asyncio.wait_for(event.wait(), 2.0)
    except TimeoutError as error:
        raise ProbeFailure(detail) from error


async def call(bus, path, interface, member, signature="", body=None, destination=BLUEZ):
    return await bus.call(
        Message(
            destination=destination,
            path=path,
            interface=interface,
            member=member,
            signature=signature,
            body=body or [],
        )
    )


async def add_match(bus, rule):
    require_ok(
        await call(
            bus,
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "AddMatch",
            "s",
            [rule],
            "org.freedesktop.DBus",
        ),
        "AddMatch",
    )


class Agent:
    def __init__(self, name):
        self.name = name
        self.confirmations = 0
        self.pin_requests = 0
        self.authorizations = 0
        self.cancels = 0
        self.releases = 0
        self.pin_event = asyncio.Event()

    @property
    def pairing_prompts(self):
        return self.confirmations + self.pin_requests

    def handle(self, message):
        if message.message_type != MessageType.METHOD_CALL or message.interface != "org.bluez.Agent1":
            return False
        if message.member == "RequestConfirmation":
            self.confirmations += 1
            return Message.new_method_return(message)
        if message.member == "RequestPinCode":
            self.pin_requests += 1
            self.pin_event.set()
            return True
        if message.member == "AuthorizeService":
            self.authorizations += 1
            return Message.new_method_return(message)
        if message.member == "Cancel":
            self.cancels += 1
            return Message.new_method_return(message)
        if message.member == "Release":
            self.releases += 1
            return Message.new_method_return(message)
        return Message.new_error(message, "org.bluez.Error.Rejected", f"{self.name} rejected unknown request")


class Observer:
    def __init__(self):
        self.rows = set()
        self.added = asyncio.Event()
        self.removed_count = 0
        self.removed = asyncio.Event()
        self.owner_lost = asyncio.Event()
        self.property_events = []

    def handle(self, message):
        if message.message_type != MessageType.SIGNAL:
            return False
        if message.interface == OBJECT_MANAGER and message.member == "InterfacesAdded":
            path, interfaces = message.body
            if DEVICE in interfaces:
                self.rows.add(path)
                self.added.set()
            return False
        if message.interface == OBJECT_MANAGER and message.member == "InterfacesRemoved":
            path, interfaces = message.body
            if DEVICE in interfaces:
                self.rows.discard(path)
                self.removed_count += 1
                self.removed.set()
            return False
        if message.interface == PROPERTIES and message.member == "PropertiesChanged":
            self.property_events.append(message.body)
            return False
        if message.interface == "org.freedesktop.DBus" and message.member == "NameOwnerChanged":
            name, old_owner, new_owner = message.body
            if name == BLUEZ and old_owner and not new_owner:
                self.owner_lost.set()
            return False
        return False


async def get_property(bus, name):
    reply = require_ok(
        await call(bus, DEVICE_PATH, PROPERTIES, "Get", "ss", [DEVICE, name]),
        f"read Device1.{name}",
    )
    return reply.body[0].value


async def set_trusted(bus, value):
    require_ok(
        await call(
            bus,
            DEVICE_PATH,
            PROPERTIES,
            "Set",
            "ssv",
            [DEVICE, "Trusted", Variant("b", value)],
        ),
        "write Device1.Trusted",
    )


async def discover(bus, observer):
    observer.added.clear()
    require_ok(
        await call(
            bus,
            ADAPTER_PATH,
            ADAPTER,
            "SetDiscoveryFilter",
            "a{sv}",
            [{"Transport": Variant("s", "auto"), "UUIDs": Variant("as", [])}],
        ),
        "SetDiscoveryFilter",
    )
    require_ok(await call(bus, ADAPTER_PATH, ADAPTER, "StartDiscovery"), "StartDiscovery")
    await wait_event(observer.added, "InterfacesAdded was not observed")
    require(DEVICE_PATH in observer.rows, "client row was not created from InterfacesAdded")
    require_ok(await call(bus, ADAPTER_PATH, ADAPTER, "StopDiscovery"), "StopDiscovery")


async def main():
    address = os.environ.get("DBUS_SESSION_BUS_ADDRESS")
    if not address:
        print("FAIL: private session bus address missing", file=sys.stderr)
        return 2

    bus_a = await MessageBus(bus_address=address).connect()
    bus_b = await MessageBus(bus_address=address).connect()
    require(bus_a.unique_name != bus_b.unique_name, "agents do not have distinct unique bus names")

    agent_a = Agent("A")
    agent_b = Agent("B")
    observer = Observer()
    bus_a.add_message_handler(agent_a.handle)
    bus_a.add_message_handler(observer.handle)
    bus_b.add_message_handler(agent_b.handle)
    await add_match(bus_a, "type='signal',sender='org.bluez'")
    await add_match(bus_a, "type='signal',sender='org.freedesktop.DBus',member='NameOwnerChanged'")

    snapshot = require_ok(
        await call(bus_a, "/", OBJECT_MANAGER, "GetManagedObjects"),
        "GetManagedObjects",
    ).body[0]
    require(DEVICE_PATH not in snapshot, "device existed before discovery event")
    require(not observer.rows, "client created a device row from something other than InterfacesAdded")

    path_b = "/org/example/AgentB"
    path_a = "/org/example/AgentA"
    require_ok(
        await call(bus_b, "/org/bluez", AGENT_MANAGER, "RegisterAgent", "os", [path_b, "DisplayYesNo"]),
        "RegisterAgent(B)",
    )
    require_ok(
        await call(bus_b, "/org/bluez", AGENT_MANAGER, "RequestDefaultAgent", "o", [path_b]),
        "RequestDefaultAgent(B)",
    )
    require_ok(
        await call(bus_a, "/org/bluez", AGENT_MANAGER, "RegisterAgent", "os", [path_a, "KeyboardDisplay"]),
        "RegisterAgent(A)",
    )

    await discover(bus_a, observer)
    print("PASS 1 discovery filter/lifecycle and event-first InterfacesAdded")

    require(await get_property(bus_a, "Paired") is False, "initial Paired was not false")
    require(await get_property(bus_a, "Connected") is False, "initial Connected was not false")
    require(await get_property(bus_a, "Trusted") is False, "initial Trusted was not false")

    require_ok(
        await call(bus_a, "/org/bluez", MOCK, "SimulateIncomingConnection"),
        "untrusted incoming connection",
    )
    require(agent_b.authorizations == 1, "untrusted incoming connection did not use default agent B")
    require(agent_a.authorizations == 0, "registered agent A stole default service authorization")
    require(await get_property(bus_a, "Connected") is True, "accepted incoming connection did not connect")
    require_ok(await call(bus_a, DEVICE_PATH, DEVICE, "Disconnect"), "Disconnect incoming")

    await set_trusted(bus_a, True)
    require(await get_property(bus_a, "Trusted") is True, "Trusted write was not observable")
    require_ok(
        await call(bus_a, "/org/bluez", MOCK, "SimulateIncomingConnection"),
        "trusted incoming connection",
    )
    require(agent_b.authorizations == 1, "trusted incoming connection incorrectly prompted default agent")
    require(await get_property(bus_a, "Connected") is True, "trusted incoming connection was not auto-accepted")
    require_ok(await call(bus_a, DEVICE_PATH, DEVICE, "Disconnect"), "Disconnect trusted incoming")
    print("PASS 2 Paired/Connected/Trusted properties and trusted auto-accept")

    connect_task = asyncio.create_task(call(bus_a, DEVICE_PATH, DEVICE, "Connect"))
    await asyncio.sleep(0.01)
    require_error(
        await call(bus_a, DEVICE_PATH, DEVICE, "Connect"),
        "org.bluez.Error.InProgress",
        "concurrent Connect",
    )
    require_ok(await connect_task, "first Connect")
    require(await get_property(bus_a, "Connected") is True, "Connect did not set Connected")
    require_error(
        await call(bus_a, DEVICE_PATH, DEVICE, "Connect"),
        "org.bluez.Error.AlreadyConnected",
        "connected Connect",
    )
    require_ok(await call(bus_a, DEVICE_PATH, DEVICE, "Disconnect"), "Disconnect")
    require(await get_property(bus_a, "Connected") is False, "Disconnect did not clear Connected")
    print("PASS 4 Connect/Disconnect transitions and InProgress/AlreadyConnected errors")

    await set_trusted(bus_a, False)
    require_ok(await call(bus_a, DEVICE_PATH, DEVICE, "Pair"), "Pair")
    require(agent_a.confirmations == 1, "calling connection A did not receive RequestConfirmation")
    require(agent_b.pairing_prompts == 0, "default agent B received A's scoped pairing prompt")
    require(await get_property(bus_a, "Paired") is True, "Pair did not set Paired")
    print("PASS 3 Pair routed to calling connection A; default B untouched")

    observer.removed.clear()
    require_ok(
        await call(bus_a, ADAPTER_PATH, ADAPTER, "RemoveDevice", "o", [DEVICE_PATH]),
        "RemoveDevice(paired)",
    )
    await wait_event(observer.removed, "InterfacesRemoved for paired device was not observed")
    require(DEVICE_PATH not in observer.rows, "client retained row after InterfacesRemoved")

    await discover(bus_a, observer)
    require(await get_property(bus_a, "Paired") is False, "rediscovered fixture was not unpaired")
    observer.removed.clear()
    require_ok(
        await call(bus_a, ADAPTER_PATH, ADAPTER, "RemoveDevice", "o", [DEVICE_PATH]),
        "RemoveDevice(unpaired)",
    )
    await wait_event(observer.removed, "InterfacesRemoved for unpaired device was not observed")
    require_error(
        await call(bus_a, ADAPTER_PATH, ADAPTER, "RemoveDevice", "o", [DEVICE_PATH]),
        "org.bluez.Error.DoesNotExist",
        "RemoveDevice(missing)",
    )
    print("PASS 5 RemoveDevice removes paired or unpaired objects; missing path errors")

    await discover(bus_a, observer)
    pair_task = asyncio.create_task(call(bus_a, DEVICE_PATH, DEVICE, "Pair"))
    await wait_event(agent_a.pin_event, "calling connection A did not receive RequestPinCode")
    require(agent_b.pairing_prompts == 0, "default agent B received A's second scoped pairing prompt")
    require_ok(await call(bus_a, DEVICE_PATH, DEVICE, "CancelPairing"), "CancelPairing")
    require_error(await pair_task, "org.bluez.Error.AuthenticationCanceled", "canceled Pair")
    require(agent_a.cancels == 1, "Cancel was not sent to the pending scoped agent")

    require_ok(
        await call(bus_a, "/org/bluez", AGENT_MANAGER, "UnregisterAgent", "o", [path_a]),
        "UnregisterAgent(A)",
    )
    require(agent_a.releases == 1, "UnregisterAgent(A) did not invoke Release")
    require_ok(
        await call(bus_b, "/org/bluez", AGENT_MANAGER, "UnregisterAgent", "o", [path_b]),
        "UnregisterAgent(B)",
    )
    require(agent_b.releases == 1, "UnregisterAgent(B) did not invoke Release")
    print("PASS 6 registration preserves default; cancel invokes Cancel; unregister invokes Release")

    require_ok(await call(bus_a, "/org/bluez", MOCK, "Quit"), "mock Quit")
    await wait_event(observer.owner_lost, "org.bluez owner loss was not observed")
    absent = await call(bus_a, "/", OBJECT_MANAGER, "GetManagedObjects")
    require(absent.message_type == MessageType.ERROR, "org.bluez unexpectedly remained available")
    require(
        absent.error_name in ("org.freedesktop.DBus.Error.ServiceUnknown", "org.freedesktop.DBus.Error.NameHasNoOwner"),
        f"unexpected absence error {absent.error_name}",
    )
    print("PASS 7 org.bluez absence detected as explicit unavailable state")

    bus_a.disconnect()
    bus_b.disconnect()
    print("PASS bluez-contract: all private-bus contracts verified")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main()))
    except ProbeFailure as error:
        print(f"FAIL bluez-contract: {error}", file=sys.stderr)
        raise SystemExit(1)
