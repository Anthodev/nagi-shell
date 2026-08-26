#!/usr/bin/env bash
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/nagi-control-center-activation.XXXXXX")"
record="$fixture/activation.state"
launcher="$fixture/nagi-shell"
status=0

cleanup() {
    qs kill -p "$fixture" >/dev/null 2>&1 || true
    rm -rf "$fixture"
}
trap cleanup EXIT

fail() {
    echo "control-center-activation: $1" >&2
    status=1
}

cp "$root/tests/control-center/activation-shell.qml" "$fixture/shell.qml"
sed "s|@NAGI_DEST@|$fixture|g" "$root/packaging/nagi-shell.in" >"$launcher"
chmod 0755 "$launcher"

export NAGI_ACTIVATION_RECORD="$record"
if ! "$launcher" --control-center; then
    fail "absent-instance launcher fallback failed"
fi

wait_for_count() {
    local expected="$1"
    local deadline=$((SECONDS + 10))
    while ((SECONDS < deadline)); do
        if [[ -f "$record" ]] && grep -qx "count=$expected" "$record"; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

if ! wait_for_count 1; then
    fail "absent shell did not start and activate the Control Center"
fi

if ((status == 0)) && ! "$launcher" --control-center; then
    fail "running-instance activation failed"
fi
if ((status == 0)) && ! wait_for_count 2; then
    fail "running activation did not reach the original process"
fi
if ((status == 0)) && ! grep -qx 'route=control-center' "$record"; then
    fail "launcher dispatched an unexpected route"
fi

extra_status=0
"$launcher" --control-center arbitrary >/dev/null 2>&1 || extra_status=$?
if ((extra_status != 64)); then
    fail "launcher accepted unbounded activation arguments"
fi

unknown_reply="$(qs -p "$fixture" ipc call nagi activate arbitrary 2>/dev/null || true)"
if [[ "$unknown_reply" != "false" ]]; then
    fail "IPC accepted an unknown route: ${unknown_reply:-no reply}"
fi

if ((status == 0)); then
    echo "control-center-activation: running, absent, bounded-route, and singleton contracts verified"
fi
exit "$status"
