#!/usr/bin/env bash
# Issue #70 gate 3 wrapper: proves same-process singleton activation through
# `qs ipc call`, that --no-duplicate never activates or duplicates, and that
# the absent-instance path fails so a desktop entry can fall back to launch.
set -uo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log="$(mktemp "${TMPDIR:-/tmp}/nagi-ipc-log.XXXXXX")"
deadline=$((SECONDS + 60))
status=0
pid=""

fail() {
    echo "ipc-activation: $1" >&2
    status=1
}

qs -p "$dir" >"$log" 2>&1 &
pid=$!

ready=0
while ((SECONDS < deadline)); do
    if grep -q 'PROBE READY' "$log" 2>/dev/null; then
        ready=1
        break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
        break
    fi
    sleep 0.2
done

if ((ready != 1)); then
    fail "probe shell did not become ready"
fi

reply=""
if ((status == 0)); then
    reply="$(qs -p "$dir" ipc call nagi activate desktop-action 2>>"$log")"
    if [[ "$reply" != "count=1" ]]; then
        fail "first activation reply was '${reply:-none}', expected count=1"
    fi
fi

if ((status == 0)); then
    duplicate_exit=0
    timeout 15 qs -p "$dir" --no-duplicate >>"$log" 2>&1 || duplicate_exit=$?
    if ((duplicate_exit != 0)); then
        fail "--no-duplicate exited with ${duplicate_exit}"
    fi
fi

if ((status == 0)); then
    reply="$(qs -p "$dir" ipc call nagi activate again 2>>"$log")"
    if [[ "$reply" != "count=2" ]]; then
        fail "second activation reply was '${reply:-none}', expected count=2 in the original process"
    fi
fi

if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
fi
wait "$pid" 2>/dev/null

if qs -p "$dir" ipc call nagi activate ghost >/dev/null 2>&1; then
    fail "ipc call succeeded with no running instance; absent-instance fallback would never trigger"
fi

if ((status != 0)); then
    tail -n 60 "$log" >&2
else
    grep 'PROBE ' "$log"
    echo "ipc-activation: raise-existing, no-duplicate, and absent-instance contracts verified"
fi

rm -f "$log"
exit "$status"
