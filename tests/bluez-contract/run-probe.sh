#!/bin/sh
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/nagi-bluez-contract.XXXXXX")
cleanup_outer() {
    rm -rf -- "$fixture_root"
}
trap cleanup_outer EXIT HUP INT TERM

mkdir -p "$fixture_root/home" "$fixture_root/config" "$fixture_root/data" \
    "$fixture_root/state" "$fixture_root/cache" "$fixture_root/runtime"
chmod 700 "$fixture_root/runtime"

HOME="$fixture_root/home" \
XDG_CONFIG_HOME="$fixture_root/config" \
XDG_DATA_HOME="$fixture_root/data" \
XDG_STATE_HOME="$fixture_root/state" \
XDG_CACHE_HOME="$fixture_root/cache" \
XDG_RUNTIME_DIR="$fixture_root/runtime" \
dbus-run-session -- sh -eu -c '
    here=$1
    fixture_root=$2
    export DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS

    mock_pid=
    cleanup_inner() {
        if [ -n "$mock_pid" ]; then
            kill "$mock_pid" 2>/dev/null || true
            wait "$mock_pid" 2>/dev/null || true
        fi
    }
    trap cleanup_inner EXIT HUP INT TERM

    python3 -B "$here/mock_bluez.py" >"$fixture_root/mock.log" 2>&1 &
    mock_pid=$!
    gdbus wait --session --timeout 5 org.bluez
    python3 -B "$here/client_probe.py"
    wait "$mock_pid"
    mock_pid=
' sh "$here" "$fixture_root"
