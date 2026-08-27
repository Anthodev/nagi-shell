#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: run.sh <helper> <image>" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
helper="$1"
image="$2"
state_root="$(mktemp -d "${TMPDIR:-/tmp}/nagi-wallpaper-service.XXXXXX")"
mock_pid=""

cleanup() {
    if [[ -n "$mock_pid" ]]; then
        kill "$mock_pid" 2>/dev/null || true
        wait "$mock_pid" 2>/dev/null || true
    fi
    rm -rf "$state_root"
}
trap cleanup EXIT

image_url="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve().as_uri())' "$image")"
preseed="[{\"activity\":\"act1\",\"screen\":0,\"plugin\":\"org.kde.image\",\"image\":\"$image_url\"},{\"activity\":\"act1\",\"screen\":1,\"plugin\":\"org.kde.potd\",\"image\":\"\"}]"
export MOCK_STATE_FILE="$state_root/state.json"
export MOCK_PRESEED="$preseed"
export MOCK_IMAGE_PLUGIN=1
export MOCK_PARTIAL_APPLY=1
export XDG_CACHE_HOME="$state_root/cache"
library_root="$state_root/library"
mkdir -p "$XDG_CACHE_HOME" "$library_root"
cp "$image" "$library_root/selected.png"

python3 "$repo_root/tests/wallpaper-write-contract/mock_plasmashell.py" &
mock_pid=$!
ready=0
for _ in $(seq 1 50); do
    if ! kill -0 "$mock_pid" 2>/dev/null; then
        wait "$mock_pid"
        echo "wallpaper-service: Plasma fixture exited during startup" >&2
        exit 1
    fi
    if python3 -c 'import dbus, sys; sys.exit(0 if dbus.SessionBus().name_has_owner("org.kde.plasmashell") else 1)'; then
        ready=1
        break
    fi
    sleep 0.05
done
if [[ "$ready" -ne 1 ]]; then
    echo "wallpaper-service: Plasma fixture did not acquire its private bus name" >&2
    exit 1
fi

python3 "$script_dir/probe.py" "$helper" "$image" "$library_root"
