#!/usr/bin/env python3
"""Private, mutation-free EasyEffects integration contract probe for issue #85."""

from __future__ import annotations

import ctypes
import os
import select
import socket
import stat
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

MAX_PRESET_NAME_BYTES = 100
MAX_PRESETS_PER_PIPELINE = 128
MAX_DIRECTORY_ENTRIES = 512
MAX_PRESET_FILE_BYTES = 1024 * 1024
MAX_RESPONSE_BYTES = 256
SOCKET_TIMEOUT_SECONDS = 0.12
CONFIRMATION_ATTEMPTS = 3
CONFIRMATION_DEADLINE_SECONDS = 0.45
DESKTOP_ID = "com.github.wwmm.easyeffects.desktop"
SERVER_NAME = "EasyEffectsServer"

IN_CLOSE_WRITE = 0x00000008
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200
IN_DELETE_SELF = 0x00000400
IN_MOVE_SELF = 0x00000800
WATCH_MASK = (
    IN_CLOSE_WRITE
    | IN_MOVED_FROM
    | IN_MOVED_TO
    | IN_CREATE
    | IN_DELETE
    | IN_DELETE_SELF
    | IN_MOVE_SELF
)


class ContractError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def normalize_preset_name(value: object) -> str | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        encoded = value.encode("utf-8", "strict")
    except UnicodeError:
        return None
    if len(encoded) > MAX_PRESET_NAME_BYTES:
        return None
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        return None
    if value in (".", "..") or "/" in value or "\\" in value:
        return None
    return value

@dataclass(frozen=True)
class PresetSnapshot:
    names: tuple[str, ...]
    inspected_entries: int
    truncated: bool


def discover_presets(root: Path) -> PresetSnapshot:
    names: list[str] = []
    inspected = 0
    truncated = False
    try:
        root_mode = os.lstat(root).st_mode
        if not stat.S_ISDIR(root_mode):
            return PresetSnapshot((), 0, False)
        entries = os.scandir(root)
    except OSError:
        return PresetSnapshot((), 0, False)

    with entries:
        for entry in entries:
            inspected += 1
            if inspected > MAX_DIRECTORY_ENTRIES:
                truncated = True
                break
            try:
                metadata = entry.stat(follow_symlinks=False)
            except OSError:
                continue
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_size > MAX_PRESET_FILE_BYTES
                or Path(entry.name).suffix != ".json"
            ):
                continue
            name = Path(entry.name).stem
            normalized = normalize_preset_name(name)
            if normalized is None:
                continue
            names.append(normalized)
            if len(names) == MAX_PRESETS_PER_PIPELINE:
                truncated = True
                break

    names.sort(key=lambda name: (name.casefold(), name))
    return PresetSnapshot(tuple(names), inspected, truncated)


@dataclass(frozen=True)
class Capability:
    state: str
    can_open: bool
    can_control: bool
    can_select_presets: bool


def derive_capability(
    *,
    desktop_present: bool,
    socket_present: bool,
    socket_compatible: bool,
    preset_roots_supported: bool,
) -> Capability:
    if not desktop_present:
        return Capability("absent", False, False, False)
    if not socket_present:
        return Capability("installed-server-unavailable", True, False, False)
    if not socket_compatible:
        return Capability("installed-incompatible", True, False, False)
    if not preset_roots_supported:
        return Capability("control-only", True, True, False)
    return Capability("preset-capable", True, True, True)


@dataclass(frozen=True)
class CurrentPreset:
    name: str
    selectable: bool
    external: bool


def represent_current(name: object, snapshot: PresetSnapshot) -> CurrentPreset | None:
    normalized = normalize_preset_name(name)
    if normalized is None:
        return None
    selectable = normalized in snapshot.names
    return CurrentPreset(normalized, selectable, not selectable)


def is_easyeffects_internal(properties: dict[str, object], role: str) -> bool:
    expected = {
        "output": ("easyeffects_sink", "Audio/Sink"),
        "input": ("easyeffects_source", "Audio/Source/Virtual"),
    }.get(role)
    if expected is None:
        return False
    node_name, media_class = expected
    return (
        properties.get("application.id") == "com.github.wwmm.easyeffects"
        and properties.get("node.name") == node_name
        and properties.get("media.class") == media_class
        and properties.get("node.virtual") == "true"
    )


def normalize_candidates(
    records: list[dict[str, object]], role: str, default_id: int
) -> tuple[list[int], bool]:
    internal_default = False
    eligible: list[int] = []
    for record in records:
        identifier = record.get("id")
        if not isinstance(identifier, int):
            continue
        if is_easyeffects_internal(record, role):
            internal_default = internal_default or identifier == default_id
            continue
        eligible.append(identifier)
    return eligible, internal_default


class FakeEasyEffectsServer:
    def __init__(
        self,
        path: Path,
        *,
        initial: dict[str, str] | None = None,
        apply_after_reads: int = 0,
        response_chunks: tuple[int, ...] = (),
        response_override: bytes | None = None,
        suppress_readback: bool = False,
        close_readback: bool = False,
        replace_after_load: Callable[[str, str], None] | None = None,
    ) -> None:
        self.path = path
        self.current = dict(initial or {"output": "", "input": ""})
        self.apply_after_reads = apply_after_reads
        self.response_chunks = response_chunks
        self.response_override = response_override
        self.suppress_readback = suppress_readback
        self.close_readback = close_readback
        self.replace_after_load = replace_after_load
        self.load_count = 0
        self.commands: list[str] = []
        self._pending: tuple[str, str] | None = None
        self._pending_reads = 0
        self._stop = threading.Event()
        self._listener: socket.socket | None = None
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        try:
            self.path.unlink()
        except FileNotFoundError:
            pass
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.bind(str(self.path))
        listener.listen(8)
        listener.settimeout(0.05)
        self._listener = listener
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self, *, unlink: bool = True) -> None:
        self._stop.set()
        if self._listener is not None:
            self._listener.close()
        if self._thread is not None and self._thread is not threading.current_thread():
            self._thread.join(timeout=1)
        if unlink:
            try:
                self.path.unlink()
            except FileNotFoundError:
                pass

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                assert self._listener is not None
                connection, _ = self._listener.accept()
            except (TimeoutError, OSError):
                continue
            with connection:
                connection.settimeout(0.2)
                request = bytearray()
                while len(request) <= 256 and b"\n" not in request:
                    try:
                        chunk = connection.recv(3)
                    except TimeoutError:
                        break
                    if not chunk:
                        break
                    request.extend(chunk)
                self._handle(connection, bytes(request))

    def _handle(self, connection: socket.socket, request: bytes) -> None:
        try:
            command = request.decode("utf-8", "strict")
        except UnicodeError:
            return
        self.commands.append(command)
        if command.startswith("load_preset:") and command.endswith("\n"):
            parts = command[:-1].split(":", 2)
            if len(parts) != 3:
                return
            _, pipeline, name = parts
            if pipeline not in ("output", "input") or normalize_preset_name(name) is None:
                return
            self.load_count += 1
            self._pending = (pipeline, name)
            self._pending_reads = 0
            if self.apply_after_reads == 0:
                self.current[pipeline] = name
                self._pending = None
            callback = self.replace_after_load
            if callback is not None:
                callback(pipeline, name)
            return

        if not command.startswith("get_last_loaded_preset:") or not command.endswith("\n"):
            return
        pipeline = command[len("get_last_loaded_preset:") : -1]
        if pipeline not in ("output", "input"):
            return
        if self.close_readback:
            return
        if self.suppress_readback:
            time.sleep(SOCKET_TIMEOUT_SECONDS * 2)
            return
        if self._pending is not None and self._pending[0] == pipeline:
            self._pending_reads += 1
            if self._pending_reads >= self.apply_after_reads:
                self.current[pipeline] = self._pending[1]
                self._pending = None
        response = self.response_override
        if response is None:
            response = (self.current[pipeline] + "\n").encode()
        try:
            if not self.response_chunks:
                connection.sendall(response)
                return
            offset = 0
            for length in self.response_chunks:
                chunk = response[offset : offset + length]
                if chunk:
                    connection.sendall(chunk)
                offset += length
                time.sleep(0.005)
            if offset < len(response):
                connection.sendall(response[offset:])
        except OSError:
            return


class SocketContractClient:
    def __init__(self, endpoint: Path) -> None:
        self._endpoint = endpoint
        self.generation = 0
        self.pending = False

    def probe(self) -> bool:
        try:
            self._read_current("output")
            self._read_current("input")
        except (ContractError, OSError):
            return False
        self.generation += 1
        return True

    def _identity(self) -> tuple[int, int]:
        metadata = os.lstat(self._endpoint)
        require(stat.S_ISSOCK(metadata.st_mode), "endpoint is not a Unix socket")
        return metadata.st_dev, metadata.st_ino

    def _exchange(self, command: bytes, expect_response: bool) -> bytes:
        require(len(command) <= 128 and command.endswith(b"\n"), "command framing is bounded")
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.settimeout(SOCKET_TIMEOUT_SECONDS)
        try:
            connection.connect(str(self._endpoint))
            connection.sendall(command)
            if not expect_response:
                return b""
            response = bytearray()
            while b"\n" not in response:
                chunk = connection.recv(16)
                if not chunk:
                    raise ContractError("socket closed before readback")
                response.extend(chunk)
                if len(response) > MAX_RESPONSE_BYTES:
                    raise ContractError("oversized readback")
            line, remainder = bytes(response).split(b"\n", 1)
            require(not remainder, "multiple or trailing response data is rejected")
            try:
                text = line.decode("utf-8", "strict")
            except UnicodeError as error:
                raise ContractError("readback is not UTF-8") from error
            require(normalize_preset_name(text) is not None or text == "", "invalid readback name")
            return line
        except TimeoutError as error:
            raise ContractError("socket deadline exceeded") from error
        finally:
            connection.close()

    def _read_current(self, pipeline: str) -> str:
        require(pipeline in ("output", "input"), "pipeline is normalized")
        response = self._exchange(
            f"get_last_loaded_preset:{pipeline}\n".encode(), expect_response=True
        )
        return response.decode()

    def load_and_confirm(self, pipeline: str, name: object, generation: int) -> bool:
        normalized = normalize_preset_name(name)
        if (
            normalized is None
            or pipeline not in ("output", "input")
            or generation != self.generation
            or self.pending
        ):
            return False
        self.pending = True
        try:
            identity = self._identity()
            command = f"load_preset:{pipeline}:{normalized}\n".encode()
            self._exchange(command, expect_response=False)
            deadline = time.monotonic() + CONFIRMATION_DEADLINE_SECONDS
            for attempt in range(CONFIRMATION_ATTEMPTS):
                if time.monotonic() >= deadline or self._identity() != identity:
                    return False
                try:
                    if self._read_current(pipeline) == normalized:
                        return True
                except (ContractError, OSError):
                    return False
                if attempt + 1 < CONFIRMATION_ATTEMPTS:
                    time.sleep(0.02)
            return False
        except (ContractError, OSError):
            return False
        finally:
            self.pending = False


class VisiblePresetWatcher:
    def __init__(self, roots: tuple[Path, Path]) -> None:
        self.roots = roots
        self.snapshots = 0
        self.events = 0
        self._fd = -1
        self._libc = ctypes.CDLL(None, use_errno=True)

    @property
    def active(self) -> bool:
        return self._fd >= 0

    def open(self) -> tuple[PresetSnapshot, PresetSnapshot]:
        require(not self.active, "watcher opens once")
        self._fd = self._libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        require(self._fd >= 0, "inotify initializes")
        for root in self.roots:
            descriptor = self._libc.inotify_add_watch(
                self._fd, os.fsencode(root), ctypes.c_uint32(WATCH_MASK)
            )
            require(descriptor >= 0, "trusted preset root is watchable")
        return self.refresh()

    def refresh(self) -> tuple[PresetSnapshot, PresetSnapshot]:
        require(self.active, "hidden sessions cannot scan")
        self.snapshots += 1
        return discover_presets(self.roots[0]), discover_presets(self.roots[1])

    def wait_for_event(self) -> tuple[PresetSnapshot, PresetSnapshot]:
        require(self.active, "hidden sessions receive no events")
        ready, _, _ = select.select([self._fd], [], [], 0.5)
        require(bool(ready), "filesystem change emits an event")
        payload = os.read(self._fd, 4096)
        require(len(payload) >= 16, "filesystem event is framed")
        self.events += 1
        return self.refresh()

    def close(self) -> None:
        if self.active:
            os.close(self._fd)
            self._fd = -1


def test_preset_discovery_and_lifecycle(base: Path) -> None:
    output = base / "data" / "easyeffects" / "output"
    input_root = base / "data" / "easyeffects" / "input"
    output.mkdir(parents=True)
    input_root.mkdir(parents=True)
    (output / "Studio.json").write_text("{}", encoding="utf-8")
    (output / "notes.txt").write_text("ignored", encoding="utf-8")
    nested = output / "nested"
    nested.mkdir()
    (nested / "Nested.json").write_text("{}", encoding="utf-8")
    os.symlink(output / "Studio.json", output / "Alias.json")
    (output / (("x" * 101) + ".json")).write_text("{}", encoding="utf-8")
    with (output / "Oversized.json").open("wb") as oversized:
        oversized.truncate(MAX_PRESET_FILE_BYTES + 1)
    linked_root = base / "linked-output"
    os.symlink(output, linked_root)
    require(discover_presets(linked_root).names == (), "symlinked preset roots are rejected")

    watcher = VisiblePresetWatcher((output, input_root))
    initial_output, initial_input = watcher.open()
    require(initial_output.names == ("Studio",), "only direct bounded regular JSON presets are listed")
    require(initial_input.names == (), "empty pipeline is represented without a placeholder")

    (output / "Added.json").write_text("{}", encoding="utf-8")
    changed, _ = watcher.wait_for_event()
    require(changed.names == ("Added", "Studio"), "create event refreshes the visible snapshot")
    (output / "Added.json").rename(output / "Renamed.json")
    renamed, _ = watcher.wait_for_event()
    require(renamed.names == ("Renamed", "Studio"), "rename event refreshes the visible snapshot")
    (output / "Renamed.json").unlink()
    removed, _ = watcher.wait_for_event()
    require(removed.names == ("Studio",), "remove event refreshes the visible snapshot")
    before_manual = watcher.snapshots
    watcher.refresh()
    require(watcher.snapshots == before_manual + 1, "manual refresh performs one bounded snapshot")
    watcher.close()
    closed_snapshots = watcher.snapshots
    (output / "Hidden.json").write_text("{}", encoding="utf-8")
    time.sleep(0.03)
    require(not watcher.active and watcher.snapshots == closed_snapshots, "closed view has no watcher or scan")

    bounded_root = base / "bounded"
    bounded_root.mkdir()
    for index in range(MAX_PRESETS_PER_PIPELINE + 5):
        (bounded_root / f"Preset-{index:03}.json").write_text("{}", encoding="utf-8")
    bounded = discover_presets(bounded_root)
    require(len(bounded.names) == MAX_PRESETS_PER_PIPELINE and bounded.truncated, "preset count is bounded")


def test_capabilities_and_external_state() -> None:
    absent = derive_capability(
        desktop_present=False,
        socket_present=False,
        socket_compatible=False,
        preset_roots_supported=False,
    )
    require(absent.state == "absent", "absence is explicit")
    stopped_or_isolated = derive_capability(
        desktop_present=True,
        socket_present=False,
        socket_compatible=False,
        preset_roots_supported=True,
    )
    require(
        stopped_or_isolated.can_open and not stopped_or_isolated.can_control,
        "installed but unavailable remains explicitly openable",
    )
    incompatible = derive_capability(
        desktop_present=True,
        socket_present=True,
        socket_compatible=False,
        preset_roots_supported=True,
    )
    require(incompatible.state == "installed-incompatible", "malformed server is incompatible")
    control_only = derive_capability(
        desktop_present=True,
        socket_present=True,
        socket_compatible=True,
        preset_roots_supported=False,
    )
    require(
        control_only.can_control and not control_only.can_select_presets,
        "control without a list is not selectable",
    )
    capable = derive_capability(
        desktop_present=True,
        socket_present=True,
        socket_compatible=True,
        preset_roots_supported=True,
    )
    require(capable.can_select_presets, "selection requires both independent capabilities")
    snapshot = PresetSnapshot(("Local",), 1, False)
    external = represent_current("External", snapshot)
    require(
        external is not None and external.external and not external.selectable,
        "external current state is not fabricated into the list",
    )
    require(represent_current("bad\nname", snapshot) is None, "untrusted current names are rejected")


def test_pipewire_identity_and_default_warning() -> None:
    official_sink = {
        "id": 10,
        "application.id": "com.github.wwmm.easyeffects",
        "node.name": "easyeffects_sink",
        "media.class": "Audio/Sink",
        "node.virtual": "true",
        "node.description": "arbitrary",
    }
    official_source = {
        "id": 20,
        "application.id": "com.github.wwmm.easyeffects",
        "node.name": "easyeffects_source",
        "media.class": "Audio/Source/Virtual",
        "node.virtual": "true",
    }
    same_label = {
        "id": 11,
        "application.id": "org.example.Virtual",
        "node.name": "virtual_sink",
        "media.class": "Audio/Sink",
        "node.virtual": "true",
        "node.description": "Easy Effects Sink",
    }
    spoofed_name = {
        "id": 12,
        "application.id": "org.example.Virtual",
        "node.name": "easyeffects_sink",
        "media.class": "Audio/Sink",
        "node.virtual": "true",
    }
    physical = {
        "id": 13,
        "application.id": "org.pipewire.alsa",
        "node.name": "alsa_output.test",
        "media.class": "Audio/Sink",
        "node.virtual": "false",
    }
    require(is_easyeffects_internal(official_sink, "output"), "official sink identity matches exactly")
    require(is_easyeffects_internal(official_source, "input"), "official source identity matches exactly")
    require(not is_easyeffects_internal(same_label, "output"), "display labels never identify internal nodes")
    require(not is_easyeffects_internal(spoofed_name, "output"), "node name alone never excludes a device")
    eligible, warning = normalize_candidates([official_sink, same_label, spoofed_name, physical], "output", 10)
    require(eligible == [11, 12, 13] and warning, "internal default warns while real and unrelated virtual candidates remain")
    require(10 not in eligible, "internal default is never mapped to a selectable fallback")


def test_socket_contract(base: Path) -> None:
    endpoint = base / SERVER_NAME
    server = FakeEasyEffectsServer(endpoint, initial={"output": "Old", "input": ""}, apply_after_reads=2, response_chunks=(1, 1))
    server.start()

    for malformed in (
        b"not-a-command\n",
        b"load_preset:sideways:Name\n",
        b"load_preset:output:\n",
    ):
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.connect(str(endpoint))
        connection.sendall(malformed)
        connection.close()
    client = SocketContractClient(endpoint)
    require(client.probe(), "compatible running server is detected by bounded read-only commands")
    require(server.load_count == 0, "malformed commands have no load effect")
    generation = client.generation
    require(client.load_and_confirm("output", "New", generation), "one load is confirmed by finite partial readback")
    require(server.load_count == 1, "confirmation never resubmits the load")
    require(not client.load_and_confirm("output", "bad\nname", generation), "malformed names never reach the socket")
    require(not client.load_and_confirm("output", "x" * 101, generation), "oversized names never reach the socket")
    require(not client.load_and_confirm("output", "../escape", generation), "path components never reach the socket")
    require(not client.load_and_confirm("output", "Old", generation + 1), "stale generations are rejected")
    client.pending = True
    require(not client.load_and_confirm("input", "Other", generation), "a pending operation rejects rather than queues")
    client.pending = False
    require(server.load_count == 1, "rejected concurrent intent sends no command")
    load_count = server.load_count
    server.stop()

    missing = FakeEasyEffectsServer(endpoint, initial={"output": "Old", "input": ""}, apply_after_reads=99)
    missing.start()
    mismatch_client = SocketContractClient(endpoint)
    require(mismatch_client.probe(), "replacement server can be reprobed")
    require(not mismatch_client.load_and_confirm("output", "Missing", mismatch_client.generation), "missing or rejected preset remains unconfirmed")
    require(missing.load_count == 1, "mismatch uses one submitted command")
    missing.stop()

    timeout_server = FakeEasyEffectsServer(endpoint, suppress_readback=True)
    timeout_server.start()
    timeout_client = SocketContractClient(endpoint)
    require(not timeout_client.probe(), "readback timeout is incompatible")
    timeout_server.stop()

    closing_server = FakeEasyEffectsServer(endpoint, close_readback=True)
    closing_server.start()
    closing_client = SocketContractClient(endpoint)
    require(not closing_client.probe(), "socket closure is incompatible")
    closing_server.stop()

    malformed_responses = (
        (b"missing-newline", "missing LF"),
        (b"one\ntwo\n", "multiple lines"),
        (b"\xff\n", "invalid UTF-8"),
        ((b"x" * (MAX_RESPONSE_BYTES + 1)) + b"\n", "oversized frame"),
    )
    for response, label in malformed_responses:
        malformed_server = FakeEasyEffectsServer(endpoint, response_override=response)
        malformed_server.start()
        malformed_client = SocketContractClient(endpoint)
        require(not malformed_client.probe(), f"{label} readback is incompatible")
        malformed_server.stop()

    replacement_holder: dict[str, FakeEasyEffectsServer] = {}
    replacement_started = threading.Event()

    def replace_server(_pipeline: str, name: str) -> None:
        def perform() -> None:
            original = replacement_holder["original"]
            original.stop()
            successor = FakeEasyEffectsServer(endpoint, initial={"output": name, "input": ""})
            replacement_holder["successor"] = successor
            successor.start()
            replacement_started.set()

        threading.Thread(target=perform, daemon=True).start()

    original = FakeEasyEffectsServer(endpoint, initial={"output": "Old", "input": ""}, replace_after_load=replace_server)
    replacement_holder["original"] = original
    original.start()
    replacement_client = SocketContractClient(endpoint)
    require(replacement_client.probe(), "original server probes before replacement")
    require(not replacement_client.load_and_confirm("output", "New", replacement_client.generation), "process replacement invalidates confirmation")
    require(replacement_started.wait(1), "replacement fixture completed")
    replacement_holder["successor"].stop()
    require(load_count == 1, "earlier operation count remains isolated")


def main() -> int:
    try:
        require(DESKTOP_ID.endswith(".desktop") and SERVER_NAME == "EasyEffectsServer", "official metadata identifiers are pinned")
        with tempfile.TemporaryDirectory(prefix="nagi-easyeffects-contract-") as directory:
            base = Path(directory)
            test_preset_discovery_and_lifecycle(base)
            test_socket_contract(base)
        test_capabilities_and_external_state()
        test_pipewire_identity_and_default_warning()
    except (ContractError, OSError) as error:
        print(f"easyeffects-contract: FAIL: {error}", file=os.sys.stderr)
        return 1
    print("easyeffects-contract: capability, socket, preset, lifecycle, and PipeWire gates passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
