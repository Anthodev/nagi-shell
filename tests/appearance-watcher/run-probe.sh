#!/usr/bin/env bash
# Issue #70 gate 4 wrapper: drives a synthetic kdeglobals through light,
# dark, accent removal, reduced motion, malformed values, and deletion using
# atomic renames, asserting event-first re-derivation for every transition.
set -uo pipefail

root="$(mktemp -d "${TMPDIR:-/tmp}/nagi-appearance.XXXXXX")"
config="$root/config"
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="$root/project"
log="$(mktemp "${TMPDIR:-/tmp}/nagi-appearance-log.XXXXXX")"
deadline=$((SECONDS + 60))
status=0
pid=""

mkdir -p "$config" "$project/qml"
cp "$dir/shell.qml" "$project/shell.qml"
cp "$dir/../../qml/KdeAppearanceAdapter.qml" "$project/qml/"
cat >"$config/kdeglobals" <<'EOF'
[General]
ColorScheme=BreezeLight
AccentColor=#3daee9
[KDE]
AnimationDurationFactor=1.00
EOF

write_variant() {
    printf '%s' "$1" >"$config/kdeglobals.new"
    mv -f "$config/kdeglobals.new" "$config/kdeglobals"
}

fail() {
    echo "appearance-watcher: $1" >&2
    status=1
}

await_pattern() {
    local pattern=$1
    while ((SECONDS < deadline)); do
        if grep -qE "$pattern" "$log" 2>/dev/null; then
            return 0
        fi
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 0.1
    done
    grep 'APPEARANCE ' "$log" >&2 || true
    fail "timed out waiting for pattern: $pattern"
    return 1
}

QT_QPA_PLATFORM='offscreen' XDG_CONFIG_HOME="$config" HOME="$root/home" \
    mkdir -p "$root/home"
QT_QPA_PLATFORM='offscreen' XDG_CONFIG_HOME="$config" HOME="$root/home" \
    qs -p "$project" >"$log" 2>&1 &
pid=$!

await_pattern 'APPEARANCE scheme=BreezeLight accent=#3DAEE9 motion=1$' || true

if ((status == 0)); then
    write_variant '[General]
ColorScheme=BreezeDark
[KDE]
AnimationDurationFactor=0
'
    await_pattern 'APPEARANCE scheme=BreezeDark accent=#[0-9A-F]{6} motion=0$'
fi

if ((status == 0)); then
    write_variant '[General]
ColorScheme=BreezeDark
AccentColor=not-a-color
[KDE]
AnimationDurationFactor=0.5
'
    await_pattern 'APPEARANCE scheme=BreezeDark accent=#[0-9A-F]{6} motion=0\.5$'
fi

if ((status == 0)); then
    write_variant '[General]
ColorScheme=BreezeDark
AccentColor=61,174,233,128
[KDE]
AnimationDurationFactor=0.75
'
    await_pattern 'APPEARANCE scheme=BreezeDark accent=#803DAEE9 motion=0\.75$'
fi

if ((status == 0)); then
    rm -f "$config/kdeglobals"
    await_pattern 'APPEARANCE scheme= accent=#[0-9A-F]{6} motion=1$'
fi

events=$(grep -c 'APPEARANCE ' "$log" || true)
if ((status == 0)) && ((events < 5)); then
    fail "expected at least 5 observed transitions, saw ${events}"
fi

if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
fi
wait "$pid" 2>/dev/null

if ((status != 0)); then
    tail -n 60 "$log" >&2
else
    grep -E 'PROBE |APPEARANCE ' "$log"
    echo "appearance-watcher: event-first kdeglobals observation verified (${events} transitions)"
fi

rm -f "$log"
rm -rf "$root"
exit "$status"
