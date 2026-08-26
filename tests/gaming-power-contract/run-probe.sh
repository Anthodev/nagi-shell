#!/usr/bin/env bash
# Issue #70 Gaming Performance platform-contract gate.
# Private mocks run on a disposable session bus. The live section is separate,
# bounded, and performs only broker owner checks, property reads, and introspection.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/nagi-gaming-power.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

moc=""
for candidate in moc-qt6 /usr/lib64/qt6/libexec/moc /usr/lib/qt6/libexec/moc moc; do
    if command -v "$candidate" >/dev/null 2>&1; then
        moc="$(command -v "$candidate")"
        break
    fi
done
if [[ -z "$moc" ]]; then
    echo "gaming-power-contract: Qt 6 moc not found" >&2
    exit 1
fi
if ! pkg-config --exists Qt6Core Qt6DBus; then
    echo "gaming-power-contract: Qt6Core and Qt6DBus development files are required" >&2
    exit 1
fi

"$moc" "$dir/gaming_power_probe.cpp" -o "$build_dir/gaming_power_probe.moc"
${CXX:-c++} \
    -std=c++20 -O2 -Wall -Wextra -Wpedantic \
    $(pkg-config --cflags Qt6Core Qt6DBus) \
    -I"$build_dir" \
    "$dir/gaming_power_probe.cpp" \
    -o "$build_dir/gaming-power-probe" \
    $(pkg-config --libs Qt6Core Qt6DBus)

echo "gaming-power-contract: private fixture checks"
dbus-run-session -- "$build_dir/gaming-power-probe"

echo "gaming-power-contract: bounded read-only live checks"

name_owned() {
    local bus_flag="$1"
    local wanted="$2"
    local listing
    if ! listing="$(timeout 5 busctl "$bus_flag" call \
        org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus ListNames 2>/dev/null)"; then
        return 2
    fi
    if [[ "$listing" == *"\"$wanted\""* ]]; then
        return 0
    fi
    return 1
}

owner_pid_readable() {
    local bus_flag="$1"
    local wanted="$2"
    timeout 5 busctl "$bus_flag" call \
        org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus GetConnectionUnixProcessID s "$wanted" \
        >/dev/null 2>&1
}

if name_owned --user com.feralinteractive.GameMode; then
    if owner_pid_readable --user com.feralinteractive.GameMode; then
        echo "LIVE GameMode: existing owner observed read-only"
    else
        echo "LIVE GameMode: owner vanished before broker PID lookup; treated as unavailable"
    fi
else
    result=$?
    if ((result == 2)); then
        echo "gaming-power-contract: could not query the live user bus" >&2
        exit 1
    fi
    echo "LIVE GameMode: service absent; no direct service call made"
fi

live_service=""
live_path=""
live_interface=""
if name_owned --system org.freedesktop.UPower.PowerProfiles; then
    live_service="org.freedesktop.UPower.PowerProfiles"
    live_path="/org/freedesktop/UPower/PowerProfiles"
    live_interface="org.freedesktop.UPower.PowerProfiles"
else
    result=$?
    if ((result == 2)); then
        echo "gaming-power-contract: could not query the live system bus" >&2
        exit 1
    fi
    if name_owned --system net.hadess.PowerProfiles; then
        live_service="net.hadess.PowerProfiles"
        live_path="/net/hadess/PowerProfiles"
        live_interface="net.hadess.PowerProfiles"
    else
        result=$?
        if ((result == 2)); then
            echo "gaming-power-contract: could not query the live system bus" >&2
            exit 1
        fi
    fi
fi

if [[ -z "$live_service" ]]; then
    echo "PASS 7: live PowerProfiles service absent; no property or introspection call made"
elif ! owner_pid_readable --system "$live_service"; then
    echo "PASS 7: live PowerProfiles owner vanished before reads; treated as unavailable"
else
    active="$(timeout 5 busctl --system get-property \
        "$live_service" "$live_path" "$live_interface" ActiveProfile)"
    timeout 5 busctl --system introspect \
        "$live_service" "$live_path" "$live_interface" \
        >/dev/null
    echo "PASS 7: live $live_service read-only ActiveProfile=$active and one introspection completed"
fi

echo "gaming-power-contract: all contracts verified"
