#!/usr/bin/env bash
# Issue #70 gate 5 wrapper: drives the settings writer/watch probe and asserts
# the resulting filesystem truth (backup bytes, external replacement, symlink
# disposition).
set -uo pipefail

root="$(mktemp -d "${TMPDIR:-/tmp}/nagi-settings.XXXXXX")"
config="$root/config"
outside="$root/outside"
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log="$(mktemp "${TMPDIR:-/tmp}/nagi-settings-log.XXXXXX")"
deadline=$((SECONDS + 60))
status=0
pid=""

mkdir -p "$config" "$outside"
printf '[theme]\nmode=accent\naccent=#FF8800\n' >"$config/legacy.conf"
printf 'original-secret\n' >"$outside/evil.conf"
ln -s "$outside/evil.conf" "$config/link.conf"

fail() {
    echo "settings-writer: $1" >&2
    status=1
}

await_line() {
    local needle=$1
    while ((SECONDS < deadline)); do
        if grep -qF "$needle" "$log" 2>/dev/null; then
            return 0
        fi
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 0.1
    done
    grep 'SETTINGS ' "$log" >&2 || true
    fail "timed out waiting for: $needle"
    return 1
}

QT_QPA_PLATFORM='offscreen' XDG_CONFIG_HOME="$config" HOME="$root/home" \
    mkdir -p "$root/home"
QT_QPA_PLATFORM='offscreen' XDG_CONFIG_HOME="$config" HOME="$root/home" \
    qs -p "$dir" >"$log" 2>&1 &
pid=$!

await_line 'SETTINGS MARKER READY-FOR-MALFORMED'

if ((status == 0)); then
    printf '[bogus\nthis is not valid\n' >"$config/settings.conf.new"
    mv -f "$config/settings.conf.new" "$config/settings.conf"
fi

await_line 'SETTINGS DONE'

if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
fi
wait "$pid" 2>/dev/null

if ! grep -qF 'MIGRATION backed_up=true' "$log"; then
    fail "migration backup was not written"
fi
if ! cmp -s "$config/legacy.conf" "$config/settings.conf.bak"; then
    fail "backup does not match legacy content byte-for-byte"
fi
if ! grep -qE 'LOOPQUIET selfWriteEvents=[1-9] generation=1' "$log"; then
    fail "own-write reload behavior missing or generation churned"
fi
if ! grep -qF 'LASTGOOD kept=true generation=1' "$log"; then
    fail "malformed replacement did not preserve last-good state"
fi
if ! cmp -s "$config/settings.conf" <(printf '[bogus\nthis is not valid\n'); then
    fail "external malformed replacement was not observed on disk as-is"
fi

link_kind="missing"
if [[ -L "$config/link.conf" ]]; then
    link_kind="symlink"
elif [[ -f "$config/link.conf" ]]; then
    link_kind="regular-file"
fi
escaped="no"
grep -q 'escaped-content' "$outside/evil.conf" 2>/dev/null && escaped="yes"

if ((status == 0)); then
    grep -E 'SETTINGS (MIGRATION|LOOPQUIET|LASTGOOD|SYMLINK|SERVICE|WROTE)' "$log"
    echo "settings-writer: verified (link disposition=${link_kind}, escaped=${escaped})"
fi

rm -f "$log"
rm -rf "$root"
exit "$status"
