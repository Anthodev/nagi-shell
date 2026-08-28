#!/usr/bin/env bash
set -euo pipefail

if (($# != 1)); then
    echo "usage: run.sh <staged-control-center-fixture>" >&2
    exit 64
fi

fixture_dir="$1"
capture_dir="${NAGI_CONTROL_CENTER_CAPTURE_DIR:-}"
qs_bin="${QS:-qs}"

[[ -r "$fixture_dir/shell.qml" ]] || {
    echo "control-center: staged fixture is unavailable" >&2
    exit 1
}
[[ -n "$capture_dir" && -d "$capture_dir" ]] || {
    echo "control-center: capture directory is unavailable" >&2
    exit 1
}
[[ "$capture_dir" == "$fixture_dir" && "$capture_dir" != "/" ]] || {
    echo "control-center: capture and staged fixture directories must match" >&2
    exit 1
}
[[ -n "${NAGI_SETTINGS_HELPER:-}" && -x "$NAGI_SETTINGS_HELPER" ]] || {
    echo "control-center: settings helper is unavailable" >&2
    exit 1
}

artifact_dir="$capture_dir/privacy-artifacts"
rm -rf "$artifact_dir"
umask 077
mkdir -p \
    "$artifact_dir/home" \
    "$artifact_dir/xdg-cache" \
    "$artifact_dir/xdg-config" \
    "$artifact_dir/xdg-data" \
    "$artifact_dir/xdg-state"

export HOME="$artifact_dir/home"
export XDG_CACHE_HOME="$artifact_dir/xdg-cache"
export XDG_CONFIG_HOME="$artifact_dir/xdg-config"
export XDG_DATA_HOME="$artifact_dir/xdg-data"
export XDG_STATE_HOME="$artifact_dir/xdg-state"
export NAGI_CONTROL_CENTER_ARTIFACT_DIR="$artifact_dir"
export QT_ACCESSIBILITY=1

"$qs_bin" -p "$fixture_dir" --no-duplicate 2>&1 | tee "$artifact_dir/console.log"
