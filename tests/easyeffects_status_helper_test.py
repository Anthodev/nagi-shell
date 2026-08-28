#!/usr/bin/env python3

import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def read_message(process: subprocess.Popen[str]) -> dict:
    line = process.stdout.readline()
    require(line != "", "helper closed before publishing the expected frame")
    return json.loads(line)


def start_helper(helper: str, runtime: Path) -> subprocess.Popen[str]:
    env = os.environ.copy()
    env["XDG_RUNTIME_DIR"] = str(runtime)
    env["XDG_DATA_HOME"] = str(runtime / "data")
    process = subprocess.Popen(
        [helper],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )
    require(read_message(process) == {"type": "ready"}, "helper publishes one ready frame")
    return process

def prepare_presets(runtime: Path, output: tuple[str, ...], input_: tuple[str, ...]) -> None:
    for pipeline, names in (("output", output), ("input", input_)):
        directory = runtime / "data/easyeffects" / pipeline
        directory.mkdir(parents=True, mode=0o700)
        for name in names:
            (directory / f"{name}.json").write_text("{}", encoding="utf-8")


def send(process: subprocess.Popen[str], message: dict) -> None:
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()


def stop_helper(process: subprocess.Popen[str]) -> None:
    if process.poll() is None:
        send(process, {"op": "shutdown"})
        process.wait(timeout=2)
    require(process.returncode == 0, f"helper exited with {process.returncode}: {process.stderr.read()}")


class FakeServer:
    def __init__(self, path: Path, responses: list[bytes | None]) -> None:
        self.path = path
        self.responses = responses
        self.commands: list[str] = []
        self.failure: BaseException | None = None
        self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.socket.bind(str(path))
        self.socket.listen(8)
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self) -> None:
        try:
            for response in self.responses:
                connection, _ = self.socket.accept()
                with connection:
                    payload = b""
                    while not payload.endswith(b"\n"):
                        chunk = connection.recv(256)
                        if not chunk:
                            break
                        payload += chunk
                    self.commands.append(payload.decode("utf-8").strip())
                    if response is None:
                        time.sleep(0.35)
                    elif response:
                        connection.sendall(response)
        except BaseException as error:
            self.failure = error
        finally:
            self.socket.close()

    def join(self) -> None:
        self.thread.join(timeout=2)
        require(not self.thread.is_alive(), "fake server completed every admitted connection")
        if self.failure is not None:
            raise self.failure


def assert_pipeline(message: dict, generation: int, pipeline: str, state: str, name: str = "") -> None:
    require(message.get("type") == "pipeline", f"helper publishes normalized pipeline frames: {message}")
    require(message.get("generation") == generation, "pipeline frame preserves the active generation")
    require(message.get("pipeline") == pipeline, "pipeline frame preserves output/input separation")
    require(message.get("state") == state, f"pipeline state is {state}")
    require(message.get("name", "") == name, "only a confirmed bounded name crosses the helper boundary")


def assert_presets(message: dict, generation: int, pipeline: str,
                   items: list[str], state: str = "ready") -> None:
    require(message == {
        "type": "presets",
        "generation": generation,
        "pipeline": pipeline,
        "state": state,
        "items": items,
    }, f"helper publishes bounded sorted {pipeline} preset names")

def assert_load(message: dict, generation: int, pipeline: str, state: str) -> None:
    require(message == {
        "type": "load",
        "generation": generation,
        "pipeline": pipeline,
        "state": state,
    }, f"helper publishes normalized {state} load result")


def test_confirmed_load(helper: str, runtime: Path) -> None:
    prepare_presets(runtime, ("Old", "Studio"), ("Voice",))
    server = FakeServer(runtime / "EasyEffectsServer", [b"Old\n", b"Voice\n", b"", b"Studio\n"])
    process = start_helper(helper, runtime)
    send(process, {"op": "interest", "generation": 4, "active": True})
    assert_pipeline(read_message(process), 4, "output", "lastLoaded", "Old")
    assert_pipeline(read_message(process), 4, "input", "lastLoaded", "Voice")
    assert_presets(read_message(process), 4, "output", ["Old", "Studio"])
    assert_presets(read_message(process), 4, "input", ["Voice"])

    send(process, {
        "op": "load",
        "generation": 4,
        "pipeline": "output",
        "name": "Studio",
    })
    confirmation = read_message(process)
    require(confirmation.get("type") == "pipeline",
            f"load confirmation failed after commands {server.commands}, server={server.failure}: {confirmation}")
    assert_pipeline(confirmation, 4, "output", "lastLoaded", "Studio")
    assert_load(read_message(process), 4, "output", "confirmed")
    send(process, {
        "op": "load",
        "generation": 4,
        "pipeline": "input",
        "name": "private/path",
    })
    assert_load(read_message(process), 4, "input", "invalid")
    stop_helper(process)
    server.join()
    require(server.commands == [
        "get_last_loaded_preset:output",
        "get_last_loaded_preset:input",
        "load_preset:output:Studio",
        "get_last_loaded_preset:output",
    ], "load uses one exact command and a fresh bounded confirmation read")

def test_mismatched_load(helper: str, runtime: Path) -> None:
    prepare_presets(runtime, ("Missing", "Old"), ("Voice",))
    server = FakeServer(
        runtime / "EasyEffectsServer",
        [b"Old\n", b"Voice\n", b"", b"Old\n", b"Old\n", b"Old\n"],
    )
    process = start_helper(helper, runtime)
    send(process, {"op": "interest", "generation": 5, "active": True})
    assert_pipeline(read_message(process), 5, "output", "lastLoaded", "Old")
    assert_pipeline(read_message(process), 5, "input", "lastLoaded", "Voice")
    assert_presets(read_message(process), 5, "output", ["Missing", "Old"])
    assert_presets(read_message(process), 5, "input", ["Voice"])
    send(process, {
        "op": "load",
        "generation": 5,
        "pipeline": "output",
        "name": "Missing",
    })
    assert_pipeline(read_message(process), 5, "output", "lastLoaded", "Old")
    assert_load(read_message(process), 5, "output", "mismatch")
    stop_helper(process)
    server.join()
    require(server.commands.count("load_preset:output:Missing") == 1
            and server.commands.count("get_last_loaded_preset:output") == 4,
            "mismatch confirms three times without resubmitting the load")

def test_visible_snapshot_and_refresh(helper: str, runtime: Path) -> None:
    prepare_presets(runtime, ("Cinema", "Studio"), ("Voice",))
    server = FakeServer(runtime / "EasyEffectsServer", [b"Studio\n", b"Voice\n", b"Cinema\n", b"\n"])
    process = start_helper(helper, runtime)
    time.sleep(0.05)
    require(server.commands == [], "hidden helper performs no socket work before interest")

    send(process, {"op": "interest", "generation": 7, "active": True})
    assert_pipeline(read_message(process), 7, "output", "lastLoaded", "Studio")
    assert_pipeline(read_message(process), 7, "input", "lastLoaded", "Voice")
    assert_presets(read_message(process), 7, "output", ["Cinema", "Studio"])
    assert_presets(read_message(process), 7, "input", ["Voice"])

    send(process, {"op": "refresh", "generation": 7})
    assert_pipeline(read_message(process), 7, "output", "lastLoaded", "Cinema")
    assert_pipeline(read_message(process), 7, "input", "none")
    assert_presets(read_message(process), 7, "output", ["Cinema", "Studio"])
    assert_presets(read_message(process), 7, "input", ["Voice"])
    send(process, {"op": "interest", "generation": 7, "active": False})
    stop_helper(process)
    server.join()
    require(
        server.commands
        == [
            "get_last_loaded_preset:output",
            "get_last_loaded_preset:input",
            "get_last_loaded_preset:output",
            "get_last_loaded_preset:input",
        ],
        "activation and explicit refresh issue exactly one fresh read per pipeline",
    )


def test_unreachable(helper: str, runtime: Path) -> None:
    process = start_helper(helper, runtime)
    send(process, {"op": "interest", "generation": 2, "active": True})
    assert_pipeline(read_message(process), 2, "output", "unavailable")
    assert_pipeline(read_message(process), 2, "input", "unavailable")
    assert_presets(read_message(process), 2, "output", [])
    assert_presets(read_message(process), 2, "input", [])
    stop_helper(process)


def test_invalid_and_timeout(helper: str, runtime: Path) -> None:
    server = FakeServer(runtime / "EasyEffectsServer", [b"one\ntwo\n", None])
    process = start_helper(helper, runtime)
    send(process, {"op": "interest", "generation": 3, "active": True})
    assert_pipeline(read_message(process), 3, "output", "invalid")
    assert_pipeline(read_message(process), 3, "input", "timeout")
    assert_presets(read_message(process), 3, "output", [])
    assert_presets(read_message(process), 3, "input", [])
    stop_helper(process)
    server.join()


def main() -> int:
    require(len(sys.argv) == 2, "usage: easyeffects_status_helper_test.py HELPER")
    helper = os.path.abspath(sys.argv[1])
    with tempfile.TemporaryDirectory(prefix="nagi-easyeffects-status-") as temp:
        root = Path(temp)
        os.chmod(root, 0o700)
        for name, test in (
            ("visible", test_visible_snapshot_and_refresh),
            ("unreachable", test_unreachable),
            ("invalid", test_invalid_and_timeout),
            ("load", test_confirmed_load),
            ("mismatch", test_mismatched_load),
        ):
            runtime = root / name
            runtime.mkdir(mode=0o700)
            test(helper, runtime)
    print("EasyEffects status helper lifecycle tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
