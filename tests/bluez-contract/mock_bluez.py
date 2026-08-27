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


class MockBlueZ:
    def __init__(self, bus):
        self.bus = bus
        self.device_present = False
        self.discovering = False
        self.paired = False
        self.connected = False
        self.trusted = False
        self.agents = {}
        self.default_owner = None
        self.pair_attempt = 0
        self.pair_mode = ""
        self.connect_calls = 0
        self.fail_next_connect = False
        self.pending_pair = None
        self.connect_pending = False
        self.quit_event = asyncio.Event()

    def managed_objects(self):
        objects = {
            ADAPTER_PATH: {
                ADAPTER: {
                    "Powered": Variant("b", True),
                    "Discovering": Variant("b", self.discovering),
                }
            },
            "/org/bluez": {AGENT_MANAGER: {}},
        }
        if self.device_present:
            objects[DEVICE_PATH] = {DEVICE: self.device_properties()}
        return objects

    def device_properties(self):
        return {
            "Address": Variant("s", "01:02:03:04:05:06"),
            "Name": Variant("s", "Private Fixture"),
            "Paired": Variant("b", self.paired),
            "Connected": Variant("b", self.connected),
            "Trusted": Variant("b", self.trusted),
            "Adapter": Variant("o", ADAPTER_PATH),
            "Icon": Variant("s", "audio-headset"),
            "RSSI": Variant("n", -42),
        }

    def reply(self, message, signature="", body=None):
        self.bus.send(Message.new_method_return(message, signature, body or []))

    def error(self, message, name, text):
        self.bus.send(Message.new_error(message, name, text))

    def signal(self, path, interface, member, signature, body):
        self.bus.send(Message.new_signal(path, interface, member, signature, body))

    def property_changed(self, name, value):
        signature = "b" if isinstance(value, bool) else "s"
        self.signal(
            DEVICE_PATH,
            PROPERTIES,
            "PropertiesChanged",
            "sa{sv}as",
            [DEVICE, {name: Variant(signature, value)}, []],
        )

    def adapter_property_changed(self, name, value):
        self.signal(
            ADAPTER_PATH,
            PROPERTIES,
            "PropertiesChanged",
            "sa{sv}as",
            [ADAPTER, {name: Variant("b", value)}, []],
        )

    def add_device(self):
        if self.device_present:
            return
        self.device_present = True
        self.paired = False
        self.connected = False
        self.trusted = False
        self.signal(
            "/",
            OBJECT_MANAGER,
            "InterfacesAdded",
            "oa{sa{sv}}",
            [DEVICE_PATH, {DEVICE: self.device_properties()}],
        )

    def remove_device(self):
        self.device_present = False
        self.paired = False
        self.connected = False
        self.trusted = False
        self.signal(
            "/",
            OBJECT_MANAGER,
            "InterfacesRemoved",
            "oas",
            [DEVICE_PATH, [DEVICE]],
        )

    async def call_agent(self, owner, path, member, signature, body):
        return await self.bus.call(
            Message(
                destination=owner,
                path=path,
                interface="org.bluez.Agent1",
                member=member,
                signature=signature,
                body=body,
            )
        )

    async def pair(self, message):
        owner = message.sender
        registration = self.agents.get(owner)
        if registration is None and self.default_owner is not None:
            registration = self.agents.get(self.default_owner)
            owner = self.default_owner
        if registration is None:
            self.error(message, "org.bluez.Error.AuthenticationRejected", "no agent")
            return

        self.pair_attempt += 1
        if self.pair_mode == "pin" or (not self.pair_mode and self.pair_attempt > 1):
            member, signature, body = "RequestPinCode", "o", [DEVICE_PATH]
        elif self.pair_mode == "passkey":
            member, signature, body = "RequestPasskey", "o", [DEVICE_PATH]
        elif self.pair_mode == "authorization":
            member, signature, body = "RequestAuthorization", "o", [DEVICE_PATH]
        elif self.pair_mode == "display-pin":
            await self.call_agent(
                owner, registration[0], "DisplayPinCode", "os", [DEVICE_PATH, "4821"]
            )
            member, signature, body = "RequestAuthorization", "o", [DEVICE_PATH]
            await asyncio.sleep(0.05)
        elif self.pair_mode == "display-passkey":
            await self.call_agent(
                owner,
                registration[0],
                "DisplayPasskey",
                "ouq",
                [DEVICE_PATH, 654321, 3],
            )
            member, signature, body = "RequestAuthorization", "o", [DEVICE_PATH]
            await asyncio.sleep(0.05)
        else:
            member, signature, body = (
                "RequestConfirmation",
                "ou",
                [DEVICE_PATH, 123456],
            )
        task = asyncio.create_task(
            self.call_agent(owner, registration[0], member, signature, body)
        )
        self.pending_pair = (message, owner, registration[0], task)
        try:
            response = await task
        except asyncio.CancelledError:
            return
        finally:
            if self.pending_pair is not None and self.pending_pair[0] is message:
                self.pending_pair = None

        if response.message_type == MessageType.ERROR:
            self.error(message, "org.bluez.Error.AuthenticationRejected", "agent rejected pairing")
            return
        self.paired = True
        self.property_changed("Paired", True)
        self.reply(message)

    async def cancel_pairing(self, message):
        if self.pending_pair is None:
            self.error(message, "org.bluez.Error.DoesNotExist", "no pairing in progress")
            return
        pair_message, owner, path, task = self.pending_pair
        self.pending_pair = None
        task.cancel()
        await self.call_agent(owner, path, "Cancel", "", [])
        self.error(pair_message, "org.bluez.Error.AuthenticationCanceled", "pairing canceled")
        self.reply(message)

    async def connect_device(self, message):
        self.connect_calls += 1
        await asyncio.sleep(0.08)
        self.connect_pending = False
        if self.fail_next_connect:
            self.fail_next_connect = False
            self.error(message, "org.bluez.Error.Failed", "synthetic connection failure")
            return
        self.connected = True
        self.property_changed("Connected", True)
        self.reply(message)

    async def simulate_incoming(self, message):
        if not self.trusted:
            registration = self.agents.get(self.default_owner)
            if registration is None:
                self.error(message, "org.bluez.Error.Rejected", "no default agent")
                return
            response = await self.call_agent(
                self.default_owner,
                registration[0],
                "AuthorizeService",
                "os",
                [DEVICE_PATH, "0000110b-0000-1000-8000-00805f9b34fb"],
            )
            if response.message_type == MessageType.ERROR:
                self.error(message, "org.bluez.Error.Rejected", "service rejected")
                return
        self.connected = True
        self.property_changed("Connected", True)
        self.reply(message)

    async def unregister_agent(self, message, owner, path):
        registration = self.agents.get(owner)
        if registration is None or registration[0] != path:
            self.error(message, "org.bluez.Error.DoesNotExist", "agent not registered")
            return
        await self.call_agent(owner, path, "Release", "", [])
        del self.agents[owner]
        if self.default_owner == owner:
            self.default_owner = None
        self.reply(message)

    async def quit_later(self, message):
        self.reply(message)
        await asyncio.sleep(0.02)
        self.quit_event.set()

    def handle(self, message):
        if message.message_type != MessageType.METHOD_CALL:
            return False

        if message.path == "/" and message.interface == OBJECT_MANAGER and message.member == "GetManagedObjects":
            return Message.new_method_return(message, "a{oa{sa{sv}}}", [self.managed_objects()])

        if message.interface == PROPERTIES:
            if message.member == "Get" and len(message.body) == 2:
                interface, name = message.body
                value = None
                if message.path == DEVICE_PATH and interface == DEVICE and self.device_present:
                    value = self.device_properties().get(name)
                elif message.path == ADAPTER_PATH and interface == ADAPTER:
                    value = self.managed_objects()[ADAPTER_PATH][ADAPTER].get(name)
                if value is None:
                    return Message.new_error(message, "org.freedesktop.DBus.Error.UnknownProperty", "unknown property")
                return Message.new_method_return(message, "v", [value])
            if message.member == "Set" and len(message.body) == 3:
                interface, name, wrapped = message.body
                if message.path == DEVICE_PATH and interface == DEVICE and name == "Trusted" and self.device_present:
                    self.trusted = bool(wrapped.value)
                    self.property_changed("Trusted", self.trusted)
                    return Message.new_method_return(message)
                return Message.new_error(message, "org.freedesktop.DBus.Error.PropertyReadOnly", "property is not writable")

        if message.path == "/org/bluez" and message.interface == AGENT_MANAGER:
            if message.member == "RegisterAgent":
                path, capability = message.body
                if message.sender in self.agents:
                    return Message.new_error(message, "org.bluez.Error.AlreadyExists", "one agent per connection")
                if capability not in ("", "DisplayOnly", "DisplayYesNo", "KeyboardOnly", "NoInputNoOutput", "KeyboardDisplay"):
                    return Message.new_error(message, "org.bluez.Error.InvalidArguments", "invalid capability")
                self.agents[message.sender] = (path, capability)
                return Message.new_method_return(message)
            if message.member == "RequestDefaultAgent":
                path = message.body[0]
                registration = self.agents.get(message.sender)
                if registration is None or registration[0] != path:
                    return Message.new_error(message, "org.bluez.Error.DoesNotExist", "agent not registered")
                self.default_owner = message.sender
                return Message.new_method_return(message)
            if message.member == "UnregisterAgent":
                asyncio.create_task(self.unregister_agent(message, message.sender, message.body[0]))
                return True

        if message.path == ADAPTER_PATH and message.interface == ADAPTER:
            if message.member == "SetDiscoveryFilter":
                if len(message.body) != 1:
                    return Message.new_error(message, "org.bluez.Error.InvalidArguments", "filter required")
                return Message.new_method_return(message)
            if message.member == "StartDiscovery":
                if self.discovering:
                    return Message.new_error(message, "org.bluez.Error.InProgress", "discovery already active")
                self.discovering = True
                self.adapter_property_changed("Discovering", True)
                self.add_device()
                return Message.new_method_return(message)
            if message.member == "StopDiscovery":
                if not self.discovering:
                    return Message.new_error(message, "org.bluez.Error.NotReady", "discovery is not active")
                self.discovering = False
                self.adapter_property_changed("Discovering", False)
                return Message.new_method_return(message)
            if message.member == "RemoveDevice":
                path = message.body[0]
                if path != DEVICE_PATH or not self.device_present:
                    return Message.new_error(message, "org.bluez.Error.DoesNotExist", "device does not exist")
                self.remove_device()
                return Message.new_method_return(message)

        if message.path == DEVICE_PATH and message.interface == DEVICE and self.device_present:
            if message.member == "Pair":
                if self.paired:
                    return Message.new_error(message, "org.bluez.Error.AlreadyExists", "already paired")
                if self.pending_pair is not None:
                    return Message.new_error(message, "org.bluez.Error.InProgress", "pairing in progress")
                asyncio.create_task(self.pair(message))
                return True
            if message.member == "CancelPairing":
                asyncio.create_task(self.cancel_pairing(message))
                return True
            if message.member == "Connect":
                if self.connected:
                    return Message.new_error(message, "org.bluez.Error.AlreadyConnected", "already connected")
                if self.connect_pending:
                    return Message.new_error(message, "org.bluez.Error.InProgress", "connection in progress")
                self.connect_pending = True
                asyncio.create_task(self.connect_device(message))
                return True
            if message.member == "Disconnect":
                if not self.connected:
                    return Message.new_error(message, "org.bluez.Error.NotConnected", "not connected")
                self.connected = False
                self.property_changed("Connected", False)
                return Message.new_method_return(message)

        if message.path == "/org/bluez" and message.interface == MOCK:
            if message.member == "SimulateIncomingConnection":
                asyncio.create_task(self.simulate_incoming(message))
                return True
            if message.member == "SetPairMode":
                self.pair_mode = message.body[0]
                return Message.new_method_return(message)
            if message.member == "FailNextConnect":
                self.fail_next_connect = True
                return Message.new_method_return(message)
            if message.member == "ConnectCallCount":
                return Message.new_method_return(message, "u", [self.connect_calls])
            if message.member == "Quit":
                asyncio.create_task(self.quit_later(message))
                return True

        return Message.new_error(message, "org.freedesktop.DBus.Error.UnknownMethod", "unknown method")


async def main():
    address = os.environ.get("DBUS_SESSION_BUS_ADDRESS")
    if not address:
        print("private session bus address missing", file=sys.stderr)
        return 2
    bus = await MessageBus(bus_address=address).connect()
    mock = MockBlueZ(bus)
    bus.add_message_handler(mock.handle)
    await bus.request_name(BLUEZ)
    print("READY", flush=True)
    await mock.quit_event.wait()
    bus.disconnect()
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
