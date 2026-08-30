#!/usr/bin/env python3
import asyncio
import importlib.util
import json
import os
import pathlib
import sys

from dbus_next import Message, MessageType, RequestNameReply
from dbus_next.aio import MessageBus

ROOT = pathlib.Path(__file__).resolve().parent
FIXTURE_PATH = ROOT / "bluez-contract" / "mock_bluez.py"
spec = importlib.util.spec_from_file_location("nagi_mock_bluez", FIXTURE_PATH)
fixture_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture_module)

BLUEZ = fixture_module.BLUEZ
ADAPTER_PATH = fixture_module.ADAPTER_PATH
ADAPTER = fixture_module.ADAPTER
DEVICE_PATH = fixture_module.DEVICE_PATH
DEVICE = fixture_module.DEVICE
MOCK = fixture_module.MOCK
MockBlueZ = fixture_module.MockBlueZ


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


class Helper:
    def __init__(self, process):
        self.process = process
        self.states = []
        self.cursor = 0
        self.reader_task = asyncio.create_task(self._read())

    async def _read(self):
        while True:
            line = await self.process.stdout.readline()
            if not line:
                return
            message = json.loads(line)
            if message.get("type") == "state":
                self.states.append(message)

    async def send(self, operation, request_id, **payload):
        command = {"op": operation, "requestId": request_id, **payload}
        encoded = json.dumps(command, separators=(",", ":")).encode() + b"\n"
        self.process.stdin.write(encoded)
        await self.process.stdin.drain()

    async def wait_state(self, predicate, description, timeout=3.0):
        deadline = asyncio.get_running_loop().time() + timeout
        while asyncio.get_running_loop().time() < deadline:
            while self.cursor < len(self.states):
                state = self.states[self.cursor]
                self.cursor += 1
                if predicate(state):
                    return state
            await asyncio.sleep(0.01)
        raise RuntimeError(f"timed out waiting for {description}")

    async def stop(self):
        if self.process.returncode is None:
            await self.send("shutdown", 1)
            await asyncio.wait_for(self.process.wait(), 5)
        await self.reader_task


async def mock_call(bus, member, signature="", body=None):
    return await bus.call(
        Message(
            destination=BLUEZ,
            path="/org/bluez",
            interface=MOCK,
            member=member,
            signature=signature,
            body=body or [],
        )
    )


async def main():
    require(len(sys.argv) == 2, "helper path is required")
    bus = await MessageBus().connect()
    mock = MockBlueZ(bus)
    backend_calls = {"StartDiscovery": 0, "StopDiscovery": 0}

    def handle_mock_message(message):
        if message.path == ADAPTER_PATH and message.interface == ADAPTER:
            if message.member in backend_calls:
                backend_calls[message.member] += 1
        return mock.handle(message)

    bus.add_message_handler(handle_mock_message)
    name_reply = await bus.request_name(BLUEZ)
    require(name_reply in (RequestNameReply.PRIMARY_OWNER, RequestNameReply.ALREADY_OWNER),
            "could not own private BlueZ service")
    agents_before_helper = len(mock.agents)

    environment = os.environ.copy()
    environment["NAGI_CONNECTIVITY_BUS"] = "session"
    environment["NAGI_BLUETOOTH_DISCOVERY_MS"] = "100"
    process = await asyncio.create_subprocess_exec(
        sys.argv[1],
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=environment,
    )
    helper = Helper(process)
    helper_pid = process.pid
    request_id = 10

    async def command(operation, **payload):
        nonlocal request_id
        request_id += 1
        await helper.send(operation, request_id, **payload)
        return request_id

    async def scan():
        generation = await command("bluetooth-scan")
        return await helper.wait_state(
            lambda state: state["bluetooth"]["discovering"]
            and state["bluetooth"]["operationGeneration"] == generation
            and len(state["bluetooth"]["devices"]) == 1,
            "bounded discovery snapshot",
        )

    async def stop_scan():
        generation = await command("bluetooth-stop-scan")
        return await helper.wait_state(
            lambda state: not state["bluetooth"]["discovering"]
            and state["bluetooth"]["operation"] == "idle"
            and state["bluetooth"]["operationGeneration"] == generation
            and state["bluetooth"]["operationResult"] == "stopped",
            "explicit discovery stop",
        )

    def require_pairing_clear(state, context):
        bluetooth = state["bluetooth"]
        require(
            bluetooth["operation"] == "idle"
            and bluetooth["pairingPrompt"] == "none"
            and bluetooth["pairingValue"] == ""
            and bluetooth["pairingEntered"] == 0
            and bluetooth["pairingToken"] == 0,
            f"{context} retained pairing secret or operation state",
        )

    async def unpair(token):
        await command("bluetooth-unpair", token=token)
        return await helper.wait_state(
            lambda state: state["bluetooth"]["operationResult"] == "unpaired",
            "confirmed unpair",
        )

    async def pair_round(mode, expected_prompt, response="", display_prompt=None):
        await mock_call(bus, "SetPairMode", "s", [mode])
        scanned = await scan()
        token = scanned["bluetooth"]["devices"][0]["token"]
        await command("bluetooth-pair", token=token)
        if display_prompt is not None:
            await helper.wait_state(
                lambda state: state["bluetooth"]["pairingPrompt"] == display_prompt,
                f"{display_prompt} callback",
            )
        prompt_state = await helper.wait_state(
            lambda state: state["bluetooth"]["pairingPrompt"] == expected_prompt,
            f"{expected_prompt} callback",
        )
        generation = prompt_state["bluetooth"]["operationGeneration"]
        await command(
            "bluetooth-agent-response",
            generation=generation,
            accepted=True,
            response=response,
        )
        completed = await helper.wait_state(
            lambda state: state["bluetooth"]["operationResult"] == "paired-connected",
            "pair, trust, and one connect",
        )
        require_pairing_clear(completed, "pair completion")
        require(mock.trusted and mock.connected and mock.default_owner is None,
                "Nagi pairing did not trust/connect or stole default-agent ownership")
        return token, completed

    initial = await helper.wait_state(
        lambda state: state["bluetooth"]["available"],
        "initial aggregate Bluetooth state",
    )
    bluetooth = initial["bluetooth"]
    require(bluetooth["controllerCount"] == 1 and bluetooth["selectedController"] == 1,
            "deterministic controller selection was not normalized")
    require(bluetooth["devices"] == [] and not bluetooth["discovering"],
            "closed manager exposed discovery work or fabricated devices")
    active_agent_count = len(mock.agents)
    require(agents_before_helper == 0 and active_agent_count == 1
            and mock.default_owner is None and process.pid == helper_pid,
            "helper did not establish exactly one scoped non-default agent")

    await command("bluetooth-interest", interested=True)
    await scan()
    expired = await helper.wait_state(
        lambda state: state["bluetooth"]["operationResult"] == "expired"
        and not state["bluetooth"]["discovering"],
        "30-second product discovery deadline through shortened fixture seam",
    )
    require(len(expired["bluetooth"]["devices"]) == 1,
            "discovered-only device did not remain briefly actionable")

    token, _ = await pair_round("confirmation", "confirm-passkey")
    require(mock.connect_calls == 1, "pair success did not attempt Connect exactly once")

    await command("bluetooth-disconnect", token=token)
    await helper.wait_state(
        lambda state: state["bluetooth"]["operationResult"] == "disconnected",
        "backend-confirmed disconnect",
    )
    await command("bluetooth-connect", token=token)
    await helper.wait_state(
        lambda state: state["bluetooth"]["operationResult"] == "connected",
        "backend-confirmed connect",
    )
    await unpair(token)

    await mock_call(bus, "SetPairMode", "s", ["pin"])
    await mock_call(bus, "FailNextConnect")
    scanned = await scan()
    token = scanned["bluetooth"]["devices"][0]["token"]
    await command("bluetooth-pair", token=token)
    prompt_state = await helper.wait_state(
        lambda state: state["bluetooth"]["pairingPrompt"] == "enter-pin",
        "PIN entry before synthetic connection failure",
    )
    await command(
        "bluetooth-agent-response",
        generation=prompt_state["bluetooth"]["operationGeneration"],
        accepted=True,
        response="2468",
    )
    failed_connection = await helper.wait_state(
        lambda state: state["bluetooth"]["operationFailure"] == "connection-failed"
        and state["bluetooth"]["operationResult"] == "paired",
        "distinct retryable post-pair connection failure",
    )
    require(failed_connection["bluetooth"]["devices"][0]["paired"],
            "connection failure discarded a completed pairing")
    require_pairing_clear(failed_connection, "post-pair connection failure")

    connect_calls_before_retry = mock.connect_calls
    connect_generation = await command("bluetooth-connect", token=token)
    connecting = await helper.wait_state(
        lambda state: state["bluetooth"]["operation"] == "connecting"
        and state["bluetooth"]["operationGeneration"] == connect_generation,
        "mutable backend-owned connection generation",
    )
    require(not connecting["bluetooth"]["devices"][0]["connected"],
            "connection request mutated backend-owned state before confirmation")
    await command("bluetooth-interest", interested=False)
    for _ in range(32):
        await command("bluetooth-connect", token=token)
    connected_after_close = await helper.wait_state(
        lambda state: state["bluetooth"]["operationResult"] == "connected"
        and state["bluetooth"]["operationGeneration"] == connect_generation,
        "accepted connection completion after page close",
    )
    require(mock.connect_calls == connect_calls_before_retry + 1
            and connected_after_close["bluetooth"]["devices"][0]["connected"],
            "mutable-generation flood queued a request or overrode backend confirmation")
    require_pairing_clear(connected_after_close, "connection completion after close")
    await command("bluetooth-interest", interested=True)
    await unpair(token)

    for mode, prompt, response, display in (
        ("pin", "enter-pin", "4821", None),
        ("passkey", "enter-passkey", "654321", None),
        ("authorization", "authorize-pairing", "", None),
        ("display-pin", "authorize-pairing", "", "display-pin"),
        ("display-passkey", "authorize-pairing", "", "display-passkey"),
    ):
        token, _ = await pair_round(mode, prompt, response, display)
        await unpair(token)

    await mock_call(bus, "SetPairMode", "s", ["pin"])
    scanned = await scan()
    token = scanned["bluetooth"]["devices"][0]["token"]
    await command("bluetooth-pair", token=token)
    await helper.wait_state(
        lambda state: state["bluetooth"]["pairingPrompt"] == "enter-pin",
        "interactive pairing before close",
    )
    await command("bluetooth-interest", interested=False)
    cancelled = await helper.wait_state(
        lambda state: state["bluetooth"]["operationResult"] == "cancelled"
        and state["bluetooth"]["pairingPrompt"] == "none",
        "page-close pairing cancellation",
    )
    require(not cancelled["bluetooth"]["discovering"],
            "page close left discovery active")
    require_pairing_clear(cancelled, "page-close cancellation")

    await command("bluetooth-interest", interested=True)
    await scan()
    registration_owner, registration = next(iter(mock.agents.items()))
    unexpected = await mock.call_agent(
        registration_owner,
        registration[0],
        "RequestAuthorization",
        "o",
        [DEVICE_PATH],
    )
    require(unexpected.message_type == MessageType.ERROR,
            "unrelated incoming agent request was not rejected")
    await stop_scan()

    discovery_starts_before = backend_calls["StartDiscovery"]
    discovery_stops_before = backend_calls["StopDiscovery"]
    for cycle in range(50):
        discovered = await scan()
        device = discovered["bluetooth"]["devices"][0]
        require(device["paired"] == mock.paired and device["connected"] == mock.connected,
                "discovery cycle mutated backend-owned device state")
        if cycle == 0:
            for _ in range(32):
                await command("bluetooth-scan")
        stopped = await stop_scan()
        require_pairing_clear(stopped, "explicit discovery stop")
        require(
            backend_calls["StartDiscovery"] == discovery_starts_before + cycle + 1
            and backend_calls["StopDiscovery"] == discovery_stops_before + cycle + 1
            and not mock.discovering,
            "discovery flood queued backend work or a cycle did not stop exactly once",
        )

    await mock_call(bus, "SetPairMode", "s", ["pin"])
    scanned = await scan()
    token = scanned["bluetooth"]["devices"][0]["token"]
    await command("bluetooth-pair", token=token)
    await helper.wait_state(
        lambda state: state["bluetooth"]["pairingPrompt"] == "enter-pin",
        "interactive pairing before owner-loss soak",
    )

    for replacement in range(5):
        await bus.release_name(BLUEZ)
        unavailable = await helper.wait_state(
            lambda state: not state["bluetooth"]["available"]
            and state["bluetooth"]["operationFailure"] in ("unavailable", "replaced"),
            f"BlueZ owner loss cleanup {replacement + 1}",
        )
        require(unavailable["bluetooth"]["devices"] == [],
                "backend loss retained device identity")
        require_pairing_clear(unavailable, "BlueZ owner loss")
        require(len(mock.agents) == agents_before_helper and mock.default_owner is None
                and process.pid == helper_pid and process.returncode is None,
                "owner loss retained an agent or replaced the helper process")
        mock.discovering = False

        name_reply = await bus.request_name(BLUEZ)
        require(name_reply in (RequestNameReply.PRIMARY_OWNER, RequestNameReply.ALREADY_OWNER),
                "could not restore private BlueZ owner")
        restored = await helper.wait_state(
            lambda state: state["bluetooth"]["available"]
            and state["bluetooth"]["operation"] == "idle",
            f"BlueZ replacement {replacement + 1}",
        )
        require_pairing_clear(restored, "BlueZ owner replacement")
        require(len(mock.agents) == active_agent_count and mock.default_owner is None
                and process.pid == helper_pid,
                "owner replacement duplicated the scoped agent or helper")

    await command("bluetooth-interest", interested=False)
    final_state = restored
    require(
        final_state["bluetooth"]["operation"] == "idle"
        and not final_state["bluetooth"]["discovering"]
        and final_state["bluetooth"]["pairingPrompt"] == "none",
        "final clean Bluetooth state",
    )
    require_pairing_clear(final_state, "final fixture cleanup")
    require(len(mock.agents) == active_agent_count and mock.default_owner is None,
            "active fixture did not return to its pre-soak agent count")

    await helper.stop()
    stderr = (await process.stderr.read()).decode(errors="replace")
    forbidden = ("01:02:03:04:05:06", "Private Fixture", "2468", "4821", "654321")
    require(all(value not in stderr for value in forbidden),
            "diagnostics leaked hardware identity, device name, PIN, or passkey")
    require(process.returncode == 0 and len(mock.agents) == agents_before_helper
            and mock.default_owner is None and not mock.discovering,
            "connectivity helper did not restore final process, agent, and operation counts")
    print("Bluetooth manager D-Bus tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
