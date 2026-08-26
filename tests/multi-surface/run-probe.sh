#!/usr/bin/env bash
# Issue #70 gate 1 wrapper: runs the multi-surface probe inside a disposable
# dbus-run-session + kwin_wayland --virtual session created by
# tests/run-kwin-virtual.sh, then verifies process-wide service uniqueness
# while the shell is still alive.
set -uo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log="$(mktemp "${TMPDIR:-/tmp}/nagi-multi-surface-log.XXXXXX")"
deadline=$((SECONDS + 120))
status=1
finished=0

qs -p "$dir" >"$log" 2>&1 &
pid=$!

while ((SECONDS < deadline)); do
    if grep -q 'PROBE DONE' "$log" 2>/dev/null; then
        finished=1
        break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
        break
    fi
    sleep 0.2
done

if ((finished == 1)) && ! grep -q 'PROBE FAIL' "$log"; then
    owner=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus GetConnectionUnixProcessID s org.freedesktop.Notifications \
        2>/dev/null | tr -dc '0-9')
    if [[ "$owner" == "$pid" ]]; then
        status=0
    else
        echo "multi-surface: org.freedesktop.Notifications owner is '${owner:-none}', expected probe pid ${pid}" >&2
    fi
fi

if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
fi
wait "$pid" 2>/dev/null

if ((status != 0)); then
    tail -n 60 "$log" >&2
else
    grep 'PROBE ' "$log"
fi

rm -f "$log"
exit "$status"
