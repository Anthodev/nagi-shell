#!/usr/bin/env python3
"""Fail when synthetic private values escape approved test boundaries."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
from dataclasses import dataclass, field
from pathlib import Path


MAX_ENTRIES = 8192
MAX_FILES = 4096
MAX_FILE_BYTES = 8 * 1024 * 1024
MAX_TOTAL_BYTES = 64 * 1024 * 1024
MAX_PATH_BYTES = 4096
MAX_FAILURES = 64

TEXT_FORBIDDEN = {
    "wifi-ssid": b"SensitiveSSID",
    "wifi-psk": b"wifi-secret-82",
    "bluetooth-address": b"AA:BB:CC:DD:EE:82",
    "bluetooth-name": b"Private Headset 82",
    "notification-sender": b"sender-private-82",
    "notification-body": b"notification-body-private-82",
    "weather-label": b"Private Weather Label 82",
    "weather-provider-body": b"provider-body-private-82",
    "display-metadata": b"Display Serial Private 82",
    "wallpaper-path": b"/home/test/private-wallpaper-82.png",
    "wallpaper-digest": b"digest-private-82",
    "executable": b"/opt/private/bin/private-app-82",
    "raw-dbus": b"raw-dbus-private-82",
}
NUMERIC_FORBIDDEN = {
    "bluetooth-pin": b"4821",
    "bluetooth-passkey": b"654321",
    "weather-latitude": b"48.8566",
    "weather-longitude": b"2.3522",
    "pid": b"824282",
}
NUMERIC_PATTERNS = {
    name: re.compile(rb"(?<![A-Za-z0-9.])" + re.escape(value) + rb"(?![A-Za-z0-9.])")
    for name, value in NUMERIC_FORBIDDEN.items()
}
SERIALIZED_ASCII_ESCAPES = (
    re.compile(rb"%([0-9A-Fa-f]{2})"),
    re.compile(rb"\\u00([0-9A-Fa-f]{2})"),
    re.compile(rb"\\x([0-9A-Fa-f]{2})"),
)

EXPECTED_FIXTURE_DIRECTORIES = ("xdg-config", "xdg-state", "xdg-cache")
EXPECTED_FIXTURE_FILES = (
    "console.log",
    "diagnostic.txt",
    "ipc-snapshot.json",
    "accessibility.json",
)
EXPECTED_CAPTURES = (
    "privacy-wifi-a.png",
    "privacy-wifi-b.png",
    "privacy-bluetooth-a.png",
    "privacy-bluetooth-b.png",
)


def serialized_ascii(payload: bytes) -> bytes:
    """Decode bounded ASCII serialization forms before matching exact tokens."""
    normalized = payload.replace(b"\\/", b"/")
    for _ in range(2):
        previous = normalized
        for pattern in SERIALIZED_ASCII_ESCAPES:
            normalized = pattern.sub(
                lambda match: bytes((int(match.group(1), 16),)), normalized
            )
        normalized = normalized.replace(b"\\/", b"/")
        if normalized == previous:
            break
    return normalized


def forbidden_hits(payload: bytes) -> list[str]:
    normalized = serialized_ascii(payload)
    representations = (payload,) if normalized == payload else (payload, normalized)
    hits = [
        name
        for name, value in TEXT_FORBIDDEN.items()
        if any(value in representation for representation in representations)
    ]
    hits.extend(
        name
        for name, pattern in NUMERIC_PATTERNS.items()
        if any(pattern.search(representation) for representation in representations)
    )
    return hits


@dataclass
class ScanState:
    failures: list[str] = field(default_factory=list)
    file_count: int = 0
    entry_count: int = 0
    total_bytes: int = 0
    exhausted: bool = False
    seen_files: set[tuple[int, int]] = field(default_factory=set)
    seen_directories: set[tuple[int, int]] = field(default_factory=set)
    remembered_paths: set[str] = field(default_factory=set)
    payloads: dict[str, bytes] = field(default_factory=dict)
    digests: dict[str, bytes] = field(default_factory=dict)

    def fail(self, message: str) -> None:
        if len(self.failures) < MAX_FAILURES:
            self.failures.append(message)
        elif len(self.failures) == MAX_FAILURES:
            self.failures.append("additional failures omitted at the diagnostic bound")

    def path_key(self, path: Path) -> str:
        return os.path.abspath(os.fspath(path))

    def inspect_path(self, path: Path, label: str) -> None:
        encoded = os.fsencode(os.fspath(path))
        if len(encoded) > MAX_PATH_BYTES:
            self.fail(f"{label}: path exceeds the {MAX_PATH_BYTES}-byte scan bound")
            return
        for hit in forbidden_hits(encoded):
            self.fail(f"{label}: forbidden {hit} value leaked through a path component")

    def scan(self, path: Path, label: str) -> None:
        self.inspect_path(path, label)
        try:
            metadata = os.lstat(path)
        except OSError as error:
            self.fail(f"{label}: required path is missing or unreadable: {error.strerror}")
            return
        if stat.S_ISLNK(metadata.st_mode):
            self.fail(f"{label}: symbolic links are not valid privacy artifacts")
        elif stat.S_ISREG(metadata.st_mode):
            self.scan_file(path, metadata, label)
        elif stat.S_ISDIR(metadata.st_mode):
            self.scan_directory(path, metadata, label)
        else:
            self.fail(f"{label}: unsupported filesystem object in privacy artifacts")

    def scan_directory(self, root: Path, metadata: os.stat_result, label: str) -> None:
        root_identity = (metadata.st_dev, metadata.st_ino)
        if root_identity in self.seen_directories or self.exhausted:
            return
        self.seen_directories.add(root_identity)
        pending = [root]
        while pending and not self.exhausted:
            directory = pending.pop()
            try:
                entries = []
                with os.scandir(directory) as iterator:
                    for entry in iterator:
                        self.entry_count += 1
                        if self.entry_count > MAX_ENTRIES:
                            self.fail(
                                f"{label}: traversal exceeds the {MAX_ENTRIES}-entry scan bound"
                            )
                            self.exhausted = True
                            return
                        entries.append(entry)
            except OSError as error:
                self.fail(f"{label}: directory is unreadable: {error.strerror}")
                continue

            children: list[tuple[Path, os.stat_result]] = []
            for entry in sorted(entries, key=lambda value: os.fsencode(value.name)):
                child = Path(entry.path)
                self.inspect_path(child, label)
                try:
                    child_metadata = entry.stat(follow_symlinks=False)
                except OSError as error:
                    self.fail(f"{label}: artifact entry is unreadable: {error.strerror}")
                    continue
                if stat.S_ISLNK(child_metadata.st_mode):
                    self.fail(f"{label}: symbolic links are not valid privacy artifacts")
                elif stat.S_ISREG(child_metadata.st_mode):
                    self.scan_file(child, child_metadata, label)
                elif stat.S_ISDIR(child_metadata.st_mode):
                    children.append((child, child_metadata))
                else:
                    self.fail(f"{label}: unsupported filesystem object in privacy artifacts")
                if self.exhausted:
                    return

            for child, child_metadata in reversed(children):
                identity = (child_metadata.st_dev, child_metadata.st_ino)
                if identity not in self.seen_directories:
                    self.seen_directories.add(identity)
                    pending.append(child)

    def scan_file(self, path: Path, metadata: os.stat_result, label: str) -> None:
        identity = (metadata.st_dev, metadata.st_ino)
        if identity in self.seen_files or self.exhausted:
            return
        self.seen_files.add(identity)
        self.file_count += 1
        if self.file_count > MAX_FILES:
            self.fail(f"{label}: traversal exceeds the {MAX_FILES}-file scan bound")
            self.exhausted = True
            return
        if metadata.st_size > MAX_FILE_BYTES:
            self.fail(f"{label}: file exceeds the {MAX_FILE_BYTES}-byte per-file scan bound")
            self.exhausted = True
            return

        flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
        try:
            descriptor = os.open(path, flags)
            try:
                opened_metadata = os.fstat(descriptor)
                if not stat.S_ISREG(opened_metadata.st_mode) or (
                    opened_metadata.st_dev,
                    opened_metadata.st_ino,
                ) != identity:
                    self.fail(f"{label}: artifact changed type or identity while being read")
                    return
                payload = bytearray()
                while True:
                    chunk = os.read(descriptor, min(65536, MAX_FILE_BYTES + 1 - len(payload)))
                    if not chunk:
                        break
                    payload.extend(chunk)
                    if len(payload) > MAX_FILE_BYTES:
                        self.fail(
                            f"{label}: file grew beyond the {MAX_FILE_BYTES}-byte scan bound"
                        )
                        self.exhausted = True
                        return
            finally:
                os.close(descriptor)
        except OSError as error:
            self.fail(f"{label}: required file is unreadable: {error.strerror}")
            return

        self.total_bytes += len(payload)
        if self.total_bytes > MAX_TOTAL_BYTES:
            self.fail(f"{label}: scan exceeds the {MAX_TOTAL_BYTES}-byte aggregate bound")
            self.exhausted = True
            return

        content = bytes(payload)
        path_key = self.path_key(path)
        self.digests[path_key] = hashlib.sha256(content).digest()
        if path_key in self.remembered_paths:
            self.payloads[path_key] = content
        for hit in forbidden_hits(content):
            self.fail(f"{label}: forbidden {hit} value leaked into file content")


def require_kind(path: Path, directory: bool, label: str, state: ScanState) -> bool:
    state.inspect_path(path, label)
    try:
        metadata = os.lstat(path)
    except OSError as error:
        state.fail(f"{label}: required path is missing or unreadable: {error.strerror}")
        return False
    expected = stat.S_ISDIR(metadata.st_mode) if directory else stat.S_ISREG(metadata.st_mode)
    if not expected:
        state.fail(f"{label}: required {'directory' if directory else 'file'} has the wrong type")
        return False
    if not directory and metadata.st_size == 0:
        state.fail(f"{label}: required file is empty")
        return False
    return True


def parse_json_artifact(
    path: Path, label: str, state: ScanState
) -> object | None:
    payload = state.payloads.get(state.path_key(path))
    if payload is None:
        state.fail(f"{label}: required JSON artifact was not read")
        return None
    try:
        return json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        state.fail(f"{label}: required JSON artifact is not valid UTF-8 JSON")
        return None


def validate_fixture_artifacts(artifact_dir: Path, state: ScanState) -> None:
    label = "control-center artifacts"
    if not require_kind(artifact_dir, True, label, state):
        return

    required_directories = [
        artifact_dir / name for name in EXPECTED_FIXTURE_DIRECTORIES
    ]
    required_files = [artifact_dir / name for name in EXPECTED_FIXTURE_FILES]
    for directory in required_directories:
        require_kind(directory, True, label, state)
    for required_file in required_files:
        if require_kind(required_file, False, label, state):
            state.remembered_paths.add(state.path_key(required_file))
            state.scan(required_file, label)

    state.scan(artifact_dir, label)

    console_path = artifact_dir / "console.log"
    console = state.payloads.get(state.path_key(console_path), b"")
    if b"Configuration Loaded" not in console or b"FAIL:" in console:
        state.fail(f"{label}: console log is empty or records a failed fixture")

    diagnostic_path = artifact_dir / "diagnostic.txt"
    diagnostic = state.payloads.get(state.path_key(diagnostic_path), b"")
    if not diagnostic.startswith(b"Nagi Shell "):
        state.fail(f"{label}: safe diagnostic artifact is empty or malformed")

    snapshot_path = artifact_dir / "ipc-snapshot.json"
    snapshot = parse_json_artifact(snapshot_path, label, state)
    expected_snapshot = {
        "schemaVersion": 1,
        "controlCenter": {"visible": False, "loadedPageCount": 0},
        "pageInterest": {
            "wifi": False,
            "bluetooth": False,
            "wallpaper": False,
            "weatherResults": 0,
        },
        "privateState": {
            "notificationHistoryCount": 0,
            "wallpaperPreviewActive": False,
            "wifiSecretLength": 0,
            "wifiSsidLength": 0,
            "bluetoothSecretLength": 0,
            "bluetoothPrompt": "none",
        },
    }
    if snapshot is not None and snapshot != expected_snapshot:
        state.fail(f"{label}: safe IPC snapshot does not prove final cleanup")

    accessibility_path = artifact_dir / "accessibility.json"
    accessibility = parse_json_artifact(accessibility_path, label, state)
    expected_flows = {"wifi", "bluetooth-pin", "bluetooth-passkey"}
    if (
        not isinstance(accessibility, list)
        or len(accessibility) != len(expected_flows)
        or {
            record.get("flow")
            for record in accessibility
            if isinstance(record, dict)
        }
        != expected_flows
    ):
        state.fail(f"{label}: accessibility artifact does not cover every sensitive field")
    elif any(
        not isinstance(record, dict)
        or set(record)
        != {
            "flow",
            "objectName",
            "name",
            "description",
            "role",
            "passwordEdit",
        }
        or not isinstance(record["objectName"], str)
        or not record["objectName"]
        or not isinstance(record["name"], str)
        or not record["name"]
        or not isinstance(record["description"], str)
        or not record["description"]
        or record["role"] != "editableText"
        or record["passwordEdit"] is not True
        for record in accessibility
    ):
        state.fail(f"{label}: accessibility artifact contains malformed field metadata")


def validate_captures(capture_dir: Path, state: ScanState) -> None:
    label = "control-center captures"
    if not require_kind(capture_dir, True, label, state):
        return

    expected_paths = [capture_dir / name for name in EXPECTED_CAPTURES]
    for path in expected_paths:
        if require_kind(path, False, label, state):
            state.scan(path, label)

    try:
        entries = []
        with os.scandir(capture_dir) as iterator:
            for entry in iterator:
                if len(entries) >= MAX_ENTRIES:
                    state.fail(f"{label}: directory exceeds the {MAX_ENTRIES}-entry scan bound")
                    return
                entries.append(entry)
    except OSError as error:
        state.fail(f"{label}: capture directory is unreadable: {error.strerror}")
        return
    for entry in sorted(entries, key=lambda value: os.fsencode(value.name)):
        path = Path(entry.path)
        state.inspect_path(path, label)
        if entry.name.endswith(".png") and path not in expected_paths:
            state.scan(path, label)

    for first_name, second_name, flow in (
        ("privacy-wifi-a.png", "privacy-wifi-b.png", "Wi-Fi"),
        ("privacy-bluetooth-a.png", "privacy-bluetooth-b.png", "Bluetooth"),
    ):
        first = state.digests.get(state.path_key(capture_dir / first_name))
        second = state.digests.get(state.path_key(capture_dir / second_name))
        if first is not None and second is not None and first != second:
            state.fail(
                f"{label}: different-length {flow} secrets changed the cleaned rendered pixels"
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", action="append", default=[], metavar="PATH")
    parser.add_argument("--fixture-artifact-dir", metavar="PATH")
    parser.add_argument("--capture-dir", metavar="PATH")
    args = parser.parse_args()

    state = ScanState()
    if not args.root and not args.fixture_artifact_dir and not args.capture_dir:
        parser.error("at least one required scan target must be provided")
    if args.capture_dir and not args.fixture_artifact_dir:
        state.fail("control-center captures require the matching fixture artifact directory")

    if args.fixture_artifact_dir:
        validate_fixture_artifacts(Path(args.fixture_artifact_dir), state)
    if args.capture_dir:
        validate_captures(Path(args.capture_dir), state)
    for index, root_name in enumerate(args.root):
        state.scan(Path(root_name), f"root[{index + 1}]")

    if state.failures:
        for failure in state.failures:
            print(f"privacy-sweep: {failure}")
        return 1

    suffix = (
        "; Wi-Fi and Bluetooth cleaned captures are byte-identical"
        if args.capture_dir
        else ""
    )
    print(
        "privacy-sweep: forbidden corpus absent "
        f"from {state.file_count} files/{state.total_bytes} bytes{suffix}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
