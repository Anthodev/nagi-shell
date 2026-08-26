#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ${1:-} != "--inside-private-bus" ]]; then
    root="$(mktemp -d "${TMPDIR:-/tmp}/nagi-networkmanager-contract.XXXXXX")"
    trap 'rm -rf "$root"' EXIT
    mkdir -p "$root/home" "$root/config" "$root/data" "$root/state" "$root/cache" "$root/runtime"
    chmod 700 "$root/runtime"
    dbus-run-session -- env \
        HOME="$root/home" \
        XDG_CONFIG_HOME="$root/config" \
        XDG_DATA_HOME="$root/data" \
        XDG_STATE_HOME="$root/state" \
        XDG_CACHE_HOME="$root/cache" \
        XDG_RUNTIME_DIR="$root/runtime" \
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=$root/no-system-bus" \
        "$0" --inside-private-bus "$root"
    exit $?
fi

root=$2
mock_log="$root/mock.log"
probe_log="$root/probe.log"
mock_pid=""

cleanup() {
    if [[ -n "$mock_pid" ]] && kill -0 "$mock_pid" 2>/dev/null; then
        kill "$mock_pid" 2>/dev/null || true
    fi
    if [[ -n "$mock_pid" ]]; then
        wait "$mock_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

python3 "$dir/mock_service.py" >"$mock_log" 2>&1 &
mock_pid=$!

deadline=$((SECONDS + 10))
while ! grep -qFx READY "$mock_log" 2>/dev/null; do
    if ! kill -0 "$mock_pid" 2>/dev/null; then
        cat "$mock_log" >&2
        echo "networkmanager-contract: mock exited before readiness" >&2
        exit 1
    fi
    if ((SECONDS >= deadline)); then
        cat "$mock_log" >&2
        echo "networkmanager-contract: mock readiness timed out" >&2
        exit 1
    fi
    sleep 0.02
done

if ! timeout 15s python3 "$dir/probe.py" | tee "$probe_log"; then
    cat "$mock_log" >&2
    exit 1
fi

for point in 1 2 3 4 5 6 7 8; do
    grep -qE "^PASS ${point} " "$probe_log" || {
        echo "networkmanager-contract: missing PASS line for point ${point}" >&2
        exit 1
    }
done
[[ $(grep -c '^PASS ' "$probe_log") -eq 8 ]] || {
    echo "networkmanager-contract: expected exactly eight PASS lines" >&2
    exit 1
}

wait "$mock_pid"
mock_pid=""
echo "networkmanager-contract: verified on private session bus"
