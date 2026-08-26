#!/usr/bin/env bash
# Issue #70 gate 9 wrapper: private-session wallpaper write/readback probe.
# Phases exercise the documented evaluateScript path against the limited
# mock (plugin present, plugin absent) and absent-service classification.
# No host mutation.
set -uo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(mktemp -d "${TMPDIR:-/tmp}/nagi-wallpaper-write.XXXXXX")"
status=0

cleanup() {
    rm -rf "$root"
}
trap cleanup EXIT

fail() {
    echo "wallpaper-write-contract: $1" >&2
    status=1
}

preseed='[{"activity":"act1","screen":0,"plugin":"org.kde.image","image":"file:///old-a.png"},{"activity":"act1","screen":1,"plugin":"org.kde.potd","image":""},{"activity":"act2","screen":0,"plugin":"org.kde.image","image":"file:///other-activity.png"}]'

phase() {
    local plugin_enabled=$1
    local probe_filter=$2
    SCRIPT_DIR="$dir" ROOT="$root" PLUGIN_ENABLED="$plugin_enabled" \
        PRESEED="$preseed" STATE_FILE="$root/state-$plugin_enabled.json" \
        dbus-run-session -- bash -c '
            export XDG_CONFIG_HOME="$ROOT/config" XDG_DATA_HOME="$ROOT/data" \
                XDG_CACHE_HOME="$ROOT/cache" XDG_STATE_HOME="$ROOT/state" \
                HOME="$ROOT/home"
            mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$HOME"
            export MOCK_STATE_FILE="$STATE_FILE" MOCK_PRESEED="$PRESEED" MOCK_IMAGE_PLUGIN="$PLUGIN_ENABLED"
            python3 "$SCRIPT_DIR/mock_plasmashell.py" & mock=$!
            sleep 1
            python3 "$SCRIPT_DIR/probe.py"; rc=$?
            kill $mock 2>/dev/null
            exit $rc
        '
}

absent_phase() {
    dbus-run-session -- bash -c '
        export XDG_RUNTIME_DIR='"$root"'/runtime-absent
        mkdir -p "$XDG_RUNTIME_DIR"; chmod 0700 "$XDG_RUNTIME_DIR"
        python3 - <<PYEOF
import dbus
try:
    bus = dbus.SessionBus()
    bus.get_object("org.kde.plasmashell", "/PlasmaShell").EvaluateScript(
        "print(1)", dbus_interface="org.kde.PlasmaShell")
    print("FAIL 6: absent-service call unexpectedly succeeded")
except dbus.DBusException as error:
    name = error.get_dbus_name()
    ok = name in (
        "org.freedesktop.DBus.Error.ServiceUnknown",
        "org.freedesktop.DBus.Error.NameHasNoOwner",
    )
    print(("PASS" if ok else "FAIL") + f" 6: absent service classified ({name})")
PYEOF
    '
}

out="$(phase 1 '1|2|3|4')" || fail "main phase exited nonzero"
out_guard="$(phase 0 '5')" || true
out_absent="$(absent_phase)" || true

printf '%s\n' "$out" "$out_guard" "$out_absent"

all_out="$out
$out_guard
$out_absent"
passes=$(printf '%s\n' "$all_out" | grep -c '^PASS ' || true)
fails=$(printf '%s\n' "$out" "$out_absent" | grep -c '^FAIL ' || true)
if ((fails > 0)); then
    fail "${fails} main-phase contract point(s) failed"
fi
if ((passes < 6)); then
    fail "expected at least 6 PASS lines, saw ${passes}"
fi

echo "wallpaper-write-contract: ${passes} verified, ${fails} failed (renderer success remains a real-Plasma-only gap)"
exit "$status"
