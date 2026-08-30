#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/nagi-notification-startup.XXXXXX")"
trap 'rm -rf -- "$SANDBOX"' EXIT

fail() {
    printf 'notification startup packaging test failed: %s\n' "$*" >&2
    exit 1
}

assert_file() {
    [ -f "$1" ] || fail "missing file: $1"
}

assert_absent() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        fail "unexpected path: $1"
    fi
}

assert_contains() {
    grep -Fq -- "$1" "$2" || fail "missing '$1' in $2"
}

assert_not_contains() {
    if grep -Fq -- "$1" "$2"; then
        fail "unexpected '$1' in $2"
    fi
}

assert_count() {
    local expected="$1"
    local needle="$2"
    local file="$3"
    local actual
    actual="$(grep -Fxc -- "$needle" "$file" || true)"
    [ "$actual" -eq "$expected" ] ||
        fail "expected $expected occurrences of '$needle' in $file, found $actual"
}

CHECKOUT="$SANDBOX/checkout"
FAKE_BIN="$SANDBOX/fake-bin"
HOME_DIR="$SANDBOX/home"
CONFIG_HOME="$SANDBOX/config"
STATE_HOME="$SANDBOX/state"
DATA_HOME="$SANDBOX/data"
CACHE_HOME="$SANDBOX/cache"
RUNTIME_DIR="$SANDBOX/runtime"
BIN_HOME="$SANDBOX/user bin 100%-\$cash/bin"
DEST="$SANDBOX/install tree 100%-\$dest/nagi-shell"
SHARE_ROOT="${DEST%/nagi-shell}"
BIN_PATH="$BIN_HOME/nagi-shell"
SYSTEMD_USER_DIR="$CONFIG_HOME/systemd/user"
UNIT_FILE="$SYSTEMD_USER_DIR/nagi-shell.service"
WANTS_LINK="$SYSTEMD_USER_DIR/plasma-workspace-wayland.target.wants/nagi-shell.service"
AUTOSTART_FILE="$CONFIG_HOME/autostart/io.github.Anthodev.NagiShell.desktop"
DESKTOP_FILE="$SHARE_ROOT/applications/io.github.Anthodev.NagiShell.desktop"
SYSTEMCTL_LOG="$SANDBOX/systemctl.log"
SYSTEMD_RUN_LOG="$SANDBOX/systemd-run.log"
BUSCTL_LOG="$SANDBOX/busctl.log"
TIMEOUT_LOG="$SANDBOX/timeout.log"
QS_LOG="$SANDBOX/qs.log"
QS_READY_FILE="$SANDBOX/qs.ready"
SERVICE_ACTIVE_FILE="$SANDBOX/service.active"
MAKE_LOG="$SANDBOX/make.log"

mkdir -p "$CHECKOUT/packaging" "$CHECKOUT/src/global-shortcut" \
    "$CHECKOUT/qml" "$CHECKOUT/assets" "$FAKE_BIN" "$HOME_DIR" \
    "$CONFIG_HOME" "$STATE_HOME" "$DATA_HOME" "$CACHE_HOME" "$RUNTIME_DIR"
chmod 0700 "$RUNTIME_DIR"
cp "$SOURCE_ROOT/install.sh" "$SOURCE_ROOT/uninstall.sh" "$CHECKOUT/"
cp "$SOURCE_ROOT/packaging/nagi-shell.in" \
    "$SOURCE_ROOT/packaging/nagi-shell.service.in" \
    "$SOURCE_ROOT/packaging/io.github.Anthodev.NagiShell.desktop" \
    "$SOURCE_ROOT/packaging/settings.conf" "$CHECKOUT/packaging/"
printf '%s\n' '// fixture shell' > "$CHECKOUT/shell.qml"
printf '%s\n' '# fixture Makefile' > "$CHECKOUT/Makefile"

EXECUTABLE_ARTIFACTS=(
    build/nagi-kwin-virtual-desktops
    build/nagi-pipewire-audio
    build/nagi-easyeffects-status
    build/nagi-brightness
    build/nagi-gaming-performance
    build/nagi-connectivity
    build/nagi-session
    build/nagi-applications
    build/nagi-settings
    build/global-shortcut/nagi-global-shortcut
    build/wallpaper/nagi-wallpaper
    build/qml/Nagi/Notifications/libnaginotificationsplugin.so
    build/qml/Nagi/Notifications/qmldir
    build/qml/Nagi/Platform/libnagiplatformplugin.so
    build/qml/Nagi/Platform/qmldir
)
for artifact in "${EXECUTABLE_ARTIFACTS[@]}"; do
    mkdir -p "$CHECKOUT/$(dirname "$artifact")"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$CHECKOUT/$artifact"
    chmod 0755 "$CHECKOUT/$artifact"
done
cat > "$CHECKOUT/build/nagi-settings" <<'EOF_SETTINGS_HELPER'
#!/bin/sh
set -eu
[ "${1:-}" = "create" ] && [ "$#" -eq 3 ] || exit 64
directory="$2"
expected_bytes="$3"
mkdir -p "$directory"
umask 077
temporary="$directory/.settings.conf.$$"
cat > "$temporary"
actual_bytes="$(wc -c < "$temporary")"
[ "$actual_bytes" -eq "$expected_bytes" ] || exit 1
mv "$temporary" "$directory/settings.conf"
EOF_SETTINGS_HELPER
chmod 0755 "$CHECKOUT/build/nagi-settings"
printf '%s\n' '// workspace consensus fixture' \
    > "$CHECKOUT/build/nagi-kwin-workspace-consensus.js.in"

cat > "$FAKE_BIN/systemctl" <<'EOF_SYSTEMCTL'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "${SYSTEMCTL_LOG:?}"
[ "${SYSTEMCTL_MANAGER_AVAILABLE:-1}" = "1" ] || exit 1
case "$*" in
    '--user show-environment')
        if [ -n "${SYSTEMCTL_MANAGER_ENV_FILE:-}" ] && [ -f "$SYSTEMCTL_MANAGER_ENV_FILE" ]; then
            cat "$SYSTEMCTL_MANAGER_ENV_FILE"
        fi
        exit 0
        ;;
    '--user is-active --quiet nagi-shell.service')
        [ -f "${SERVICE_ACTIVE_FILE:?}" ]
        exit
        ;;
    '--user stop nagi-shell.service')
        rm -f -- "${QS_READY_FILE:?}" "${SERVICE_ACTIVE_FILE:?}"
        exit 0
        ;;
    '--user daemon-reload')
        exit 0
        ;;
    '--user enable nagi-shell.service')
        wants="${XDG_CONFIG_HOME:?}/systemd/user/plasma-workspace-wayland.target.wants"
        mkdir -p "$wants"
        ln -sfn ../nagi-shell.service "$wants/nagi-shell.service"
        exit 0
        ;;
    '--user start nagi-shell.service')
        touch "${QS_READY_FILE:?}" "${SERVICE_ACTIVE_FILE:?}"
        exit 0
        ;;
    '--user disable --now nagi-shell.service')
        rm -f -- "${XDG_CONFIG_HOME:?}/systemd/user/plasma-workspace-wayland.target.wants/nagi-shell.service"
        rm -f -- "${QS_READY_FILE:?}" "${SERVICE_ACTIVE_FILE:?}"
        exit 0
        ;;
    '--user list-unit-files --no-legend plasma-plasmashell.service')
        printf '%s\n' 'plasma-plasmashell.service enabled enabled'
        exit 0
        ;;
    '--user try-restart plasma-plasmashell.service')
        exit 0
        ;;
esac
printf 'unexpected fake systemctl invocation: %s\n' "$*" >&2
exit 64
EOF_SYSTEMCTL
cat > "$FAKE_BIN/systemd-run" <<'EOF_SYSTEMD_RUN'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "${SYSTEMD_RUN_LOG:?}"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --user|--wait|--pipe|--quiet|--collect|--service-type=exec) shift ;;
        --) shift; break ;;
        *) break ;;
    esac
done
[ "$#" -eq 2 ] || exit 64
case "$1" in
    */printenv) ;;
    *) exit 64 ;;
esac
case "$2" in
    XDG_CONFIG_HOME)
        [ "${SYSTEMD_RUN_MANAGER_CONFIG_HOME+x}" = x ] || exit 1
        printf '%s\n' "$SYSTEMD_RUN_MANAGER_CONFIG_HOME"
        ;;
    XDG_STATE_HOME)
        [ "${SYSTEMD_RUN_MANAGER_STATE_HOME+x}" = x ] || exit 1
        printf '%s\n' "$SYSTEMD_RUN_MANAGER_STATE_HOME"
        ;;
    *) exit 64 ;;
esac
EOF_SYSTEMD_RUN

cat > "$FAKE_BIN/busctl" <<'EOF_BUSCTL'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "${BUSCTL_LOG:?}"
case "$*" in
    *'NameHasOwner s org.kde.kglobalaccel'*)
        printf '%s\n' '{"type":"b","data":false}'
        ;;
    *'NameHasOwner s org.freedesktop.Notifications'*)
        if [ "${BUS_OWNER_STATE:-unowned}" = "foreign" ]; then
            printf '%s\n' '{"type":"b","data":true}'
        else
            printf '%s\n' '{"type":"b","data":false}'
        fi
        ;;
    *'allActionsForComponent'*)
        printf '%s\n' '[]'
        ;;
    *)
        printf 'unexpected fake busctl invocation: %s\n' "$*" >&2
        exit 64
        ;;
esac
EOF_BUSCTL

cat > "$FAKE_BIN/timeout" <<'EOF_TIMEOUT'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "${TIMEOUT_LOG:?}"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --signal=*) shift ;;
        --) shift; break ;;
        [0-9]*|[0-9]*s) shift; break ;;
        *) break ;;
    esac
done
[ "$#" -gt 0 ] || exit 64
exec "$@"
EOF_TIMEOUT

cat > "$FAKE_BIN/qs" <<'EOF_QS'
#!/bin/sh
set -eu
{
    printf 'qs'
    for argument in "$@"; do
        printf '\t%s' "$argument"
    done
    printf '\n'
} >> "${QS_LOG:?}"
if [ "${1:-}" = "--version" ]; then
    printf '%s\n' 'Quickshell 0.3.1'
    exit 0
fi
if [ "${1:-}" = "kill" ]; then
    rm -f -- "${QS_READY_FILE:?}"
    exit 0
fi
case " $* " in
    *' ipc call nagi activate control-center '*)
        [ -f "${QS_READY_FILE:?}" ]
        exit
        ;;
esac
case " $* " in
    *' --no-duplicate '*) touch "${QS_READY_FILE:?}" ;;
esac
exit 0
EOF_QS

cat > "$FAKE_BIN/pkg-config" <<'EOF_PKG_CONFIG'
#!/bin/sh
exit 0
EOF_PKG_CONFIG
cat > "$FAKE_BIN/fc-match" <<'EOF_FC_MATCH'
#!/bin/sh
printf '%s' 'Inter'
EOF_FC_MATCH
cat > "$FAKE_BIN/make" <<'EOF_MAKE'
#!/bin/sh
printf '%s\n' "$*" >> "${MAKE_LOG:?}"
exit 0
EOF_MAKE
cat > "$FAKE_BIN/sudo" <<'EOF_SUDO'
#!/bin/sh
set -eu
case "${1:-}" in
    -v) exit 0 ;;
    -n) shift ;;
esac
exec "$@"
EOF_SUDO
for command_name in c++ cmake qtpaths6 update-desktop-database; do
    cat > "$FAKE_BIN/$command_name" <<'EOF_NOOP'
#!/bin/sh
exit 0
EOF_NOOP
done
chmod 0755 "$FAKE_BIN"/*

: > "$SYSTEMCTL_LOG"
: > "$SYSTEMD_RUN_LOG"
: > "$BUSCTL_LOG"
: > "$TIMEOUT_LOG"
: > "$QS_LOG"
: > "$MAKE_LOG"

BASE_ENV=(
    "PATH=$FAKE_BIN:/usr/bin:/bin"
    "HOME=$HOME_DIR"
    "XDG_CONFIG_HOME=$CONFIG_HOME"
    "XDG_STATE_HOME=$STATE_HOME"
    "XDG_DATA_HOME=$DATA_HOME"
    "XDG_CACHE_HOME=$CACHE_HOME"
    "XDG_RUNTIME_DIR=$RUNTIME_DIR"
    "XDG_BIN_HOME=$BIN_HOME"
    "XDG_SESSION_TYPE=wayland"
    "XDG_CURRENT_DESKTOP=KDE"
    "KDE_FULL_SESSION=1"
    "DBUS_SESSION_BUS_ADDRESS=unix:path=$SANDBOX/private-bus"
    "SYSTEMCTL_LOG=$SYSTEMCTL_LOG"
    "SYSTEMD_RUN_LOG=$SYSTEMD_RUN_LOG"
    "BUSCTL_LOG=$BUSCTL_LOG"
    "TIMEOUT_LOG=$TIMEOUT_LOG"
    "QS_LOG=$QS_LOG"
    "QS_READY_FILE=$QS_READY_FILE"
    "SERVICE_ACTIVE_FILE=$SERVICE_ACTIVE_FILE"
    "MAKE_LOG=$MAKE_LOG"
    "SYSTEMCTL_MANAGER_AVAILABLE=1"
    "BUS_OWNER_STATE=unowned"
)

run_install() {
    env -u SUDO_USER "${BASE_ENV[@]}" \
        bash "$CHECKOUT/install.sh" --yes --skip-packages --skip-shortcuts \
        --dest "$DEST"
}

HELP_OUTPUT="$SANDBOX/help.out"
bash "$CHECKOUT/install.sh" --help > "$HELP_OUTPUT"
assert_not_contains '--no-autostart' "$HELP_OUTPUT"

mkdir -p "$(dirname "$AUTOSTART_FILE")"
printf '%s\n' '[Desktop Entry]' > "$AUTOSTART_FILE"
INSTALL_OUTPUT="$SANDBOX/install.out"
run_install > "$INSTALL_OUTPUT" 2>&1

assert_file "$UNIT_FILE"
assert_file "$BIN_PATH"
assert_file "$DESKTOP_FILE"
assert_file "$DEST/build/nagi-kwin-workspace-consensus.js.in"
[ "$(stat -c '%a' "$UNIT_FILE")" = "644" ] || fail 'user unit mode is not 0644'
[ "$(stat -c '%a' "$DEST/build/nagi-kwin-workspace-consensus.js.in")" = "644" ] ||
    fail 'workspace consensus template was installed as executable'
[ -L "$WANTS_LINK" ] || fail 'nagi-shell.service is not enabled'
[ "$(readlink "$WANTS_LINK")" = '../nagi-shell.service' ] || fail 'unexpected wants link target'
assert_absent "$AUTOSTART_FILE"
assert_contains 'Log out and back in' "$INSTALL_OUTPUT"
assert_contains 'current notification owner was neither contacted nor changed' "$INSTALL_OUTPUT"

ESCAPED_BIN="$(printf '%s' "$BIN_PATH" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\x24/g' -e 's/%/%%/g')"
EXPECTED_UNIT="$SANDBOX/expected-nagi-shell.service"
cat > "$EXPECTED_UNIT" <<EOF_EXPECTED_UNIT
[Unit]
Description=Nagi Shell
PartOf=graphical-session.target
After=plasma-kwin_wayland.service
Before=plasma-plasmashell.service xdg-desktop-autostart.target
StartLimitIntervalSec=60s
StartLimitBurst=3

[Service]
Type=dbus
BusName=org.freedesktop.Notifications
ExecStart="$ESCAPED_BIN" --session-service
Restart=on-failure
RestartSec=250ms
TimeoutStartSec=30s
TimeoutStopSec=10s
Slice=session.slice

[Install]
WantedBy=plasma-workspace-wayland.target
EOF_EXPECTED_UNIT
cmp -s "$EXPECTED_UNIT" "$UNIT_FILE" || fail 'rendered user unit differs from the frozen contract'
EXPECTED_DESKTOP_EXEC="Exec=\"$SANDBOX/user bin 100%%-\\\$cash/bin/nagi-shell\" --control-center"
assert_contains "$EXPECTED_DESKTOP_EXEC" "$DESKTOP_FILE"

ANALYZE_OUTPUT="$SANDBOX/systemd-analyze.out"
command -v systemd-analyze >/dev/null 2>&1 || fail 'systemd-analyze is required'
if ! env HOME="$HOME_DIR" XDG_CONFIG_HOME="$CONFIG_HOME" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
        systemd-analyze --user verify "$UNIT_FILE" > "$ANALYZE_OUTPUT" 2>&1; then
    cat "$ANALYZE_OUTPUT" >&2
    fail 'systemd-analyze rejected the rendered user unit'
fi

unit_count="$(find "$SYSTEMD_USER_DIR" -type f -name nagi-shell.service | wc -l)"
[ "$unit_count" -eq 1 ] || fail "expected one installed nagi-shell.service, found $unit_count"
activation_file="$(find "$DEST" "$CONFIG_HOME" "$DATA_HOME" -type f \
    -path '*/dbus-1/services/*' -print -quit)"
[ -z "$activation_file" ] || fail "unexpected D-Bus activation file: $activation_file"
assert_not_contains 'RequestName' "$BIN_PATH"
assert_not_contains 'GetNameOwner' "$BIN_PATH"
assert_count 0 '--user is-active --quiet nagi-shell.service' "$SYSTEMCTL_LOG"
assert_count 0 '--user stop nagi-shell.service' "$SYSTEMCTL_LOG"
assert_count 1 '--user daemon-reload' "$SYSTEMCTL_LOG"
assert_count 1 '--user enable nagi-shell.service' "$SYSTEMCTL_LOG"
assert_count 0 '--user start nagi-shell.service' "$SYSTEMCTL_LOG"
assert_not_contains 'plasma-plasmashell.service' "$SYSTEMCTL_LOG"
[ ! -s "$BUSCTL_LOG" ] || fail 'installer contacted D-Bus during fresh install'

rm -f -- "$SERVICE_ACTIVE_FILE" "$QS_READY_FILE"
: > "$SYSTEMCTL_LOG"
: > "$BUSCTL_LOG"
INACTIVE_UPGRADE_OUTPUT="$SANDBOX/upgrade-inactive.out"
run_install > "$INACTIVE_UPGRADE_OUTPUT" 2>&1
assert_count 1 '--user is-active --quiet nagi-shell.service' "$SYSTEMCTL_LOG"
assert_count 0 '--user stop nagi-shell.service' "$SYSTEMCTL_LOG"
assert_count 0 '--user start nagi-shell.service' "$SYSTEMCTL_LOG"
assert_count 1 '--user daemon-reload' "$SYSTEMCTL_LOG"
assert_count 1 '--user enable nagi-shell.service' "$SYSTEMCTL_LOG"
assert_not_contains 'plasma-plasmashell.service' "$SYSTEMCTL_LOG"
assert_contains 'upgraded with nagi-shell.service left inactive' \
    "$INACTIVE_UPGRADE_OUTPUT"
assert_contains 'No notification service was started' "$INACTIVE_UPGRADE_OUTPUT"
assert_contains 'Log out and back in' "$INACTIVE_UPGRADE_OUTPUT"
[ ! -s "$BUSCTL_LOG" ] || fail 'inactive upgrade contacted the current notification owner'

: > "$SYSTEMCTL_LOG"
: > "$QS_LOG"
rm -f -- "$QS_READY_FILE"
env -u SUDO_USER "${BASE_ENV[@]}" "$BIN_PATH" --session-service
[ ! -s "$SYSTEMCTL_LOG" ] ||
    fail '--session-service recursively invoked systemctl'
expected_session_service="$(printf 'qs\t-p\t%s\t--no-duplicate' "$DEST")"
assert_contains "$expected_session_service" "$QS_LOG"

: > "$SYSTEMCTL_LOG"
: > "$QS_LOG"
rm -f -- "$QS_READY_FILE"
env -u SUDO_USER "${BASE_ENV[@]}" "$BIN_PATH"
assert_count 1 '--user start nagi-shell.service' "$SYSTEMCTL_LOG"
[ ! -s "$QS_LOG" ] || fail 'plain installed launch bypassed nagi-shell.service'

: > "$QS_LOG"
rm -f -- "$QS_READY_FILE"
env -u SUDO_USER "${BASE_ENV[@]}" "$BIN_PATH" --fixture-plain
expected_plain="$(printf 'qs\t-p\t%s\t--no-duplicate\t--fixture-plain' "$DEST")"
assert_contains "$expected_plain" "$QS_LOG"

: > "$SYSTEMCTL_LOG"
: > "$QS_LOG"
rm -f -- "$QS_READY_FILE"
env -u SUDO_USER "${BASE_ENV[@]}" "$BIN_PATH" --control-center
assert_count 1 '--user start nagi-shell.service' "$SYSTEMCTL_LOG"
unexpected_direct_start="$(printf 'qs\t-p\t%s\t--no-duplicate' "$DEST")"
assert_not_contains "$unexpected_direct_start" "$QS_LOG"

mv "$UNIT_FILE" "$UNIT_FILE.saved"
: > "$SYSTEMCTL_LOG"
: > "$QS_LOG"
rm -f -- "$QS_READY_FILE"
env -u SUDO_USER "${BASE_ENV[@]}" "$BIN_PATH" --control-center
mv "$UNIT_FILE.saved" "$UNIT_FILE"
[ ! -s "$SYSTEMCTL_LOG" ] || fail 'checkout fallback invoked systemctl without an installed unit'
expected_fallback="$(printf 'qs\t-p\t%s\t--no-duplicate' "$DEST")"
assert_contains "$expected_fallback" "$QS_LOG"

mkdir -p "$(dirname "$AUTOSTART_FILE")"
printf '%s\n' '[Desktop Entry]' > "$AUTOSTART_FILE"
: > "$SYSTEMCTL_LOG"
: > "$BUSCTL_LOG"
[ -f "$SERVICE_ACTIVE_FILE" ] || fail 'active-upgrade fixture was not active'
ACTIVE_UPGRADE_OUTPUT="$SANDBOX/upgrade-active.out"
run_install > "$ACTIVE_UPGRADE_OUTPUT" 2>&1
EXPECTED_ACTIVE_UPGRADE_LOG="$SANDBOX/expected-active-upgrade-systemctl.log"
cat > "$EXPECTED_ACTIVE_UPGRADE_LOG" <<'EOF_ACTIVE_UPGRADE_LOG'
--user show-environment
--user is-active --quiet nagi-shell.service
--user stop nagi-shell.service
--user daemon-reload
--user enable nagi-shell.service
--user start nagi-shell.service
EOF_ACTIVE_UPGRADE_LOG
cmp -s "$EXPECTED_ACTIVE_UPGRADE_LOG" "$SYSTEMCTL_LOG" ||
    fail 'active upgrade did not perform one ordered stop and start'
assert_contains 'upgraded and its active notification service was restored' \
    "$ACTIVE_UPGRADE_OUTPUT"
assert_contains 'plasmashell and every foreign notification owner were left untouched' \
    "$ACTIVE_UPGRADE_OUTPUT"
assert_not_contains 'current notification owner was neither contacted nor changed' \
    "$ACTIVE_UPGRADE_OUTPUT"
assert_not_contains 'nagi-shell.service left inactive' "$ACTIVE_UPGRADE_OUTPUT"
assert_absent "$AUTOSTART_FILE"
[ ! -s "$BUSCTL_LOG" ] || fail 'active upgrade contacted a notification owner'

: > "$SYSTEMCTL_LOG"
: > "$BUSCTL_LOG"
: > "$TIMEOUT_LOG"
UNINSTALL_OUTPUT="$SANDBOX/uninstall-unowned.out"
printf 'y\ny\n' | env -u SUDO_USER "${BASE_ENV[@]}" \
    bash "$CHECKOUT/uninstall.sh" --dest "$DEST" > "$UNINSTALL_OUTPUT" 2>&1
assert_absent "$UNIT_FILE"
assert_absent "$WANTS_LINK"
assert_absent "$AUTOSTART_FILE"
assert_absent "$BIN_PATH"
assert_absent "$DEST"
assert_absent "$DESKTOP_FILE"
assert_count 1 '--user disable --now nagi-shell.service' "$SYSTEMCTL_LOG"
assert_count 1 '--user daemon-reload' "$SYSTEMCTL_LOG"
assert_count 1 '--user try-restart plasma-plasmashell.service' "$SYSTEMCTL_LOG"
assert_count 1 '--signal=TERM 15 systemctl --user try-restart plasma-plasmashell.service' "$TIMEOUT_LOG"
restart_prompt_count="$(grep -Fo 'Notifications are unowned. Restart plasmashell once' "$UNINSTALL_OUTPUT" | wc -l)"
[ "$restart_prompt_count" -eq 1 ] || fail 'unowned uninstall did not offer exactly one Plasma reclaim'

: > "$SYSTEMCTL_LOG"
: > "$BUSCTL_LOG"
run_install > "$SANDBOX/reinstall.out" 2>&1
: > "$SYSTEMCTL_LOG"
: > "$BUSCTL_LOG"
FOREIGN_OUTPUT="$SANDBOX/uninstall-foreign.out"
env -u SUDO_USER "${BASE_ENV[@]}" BUS_OWNER_STATE=foreign \
    bash "$CHECKOUT/uninstall.sh" --yes --dest "$DEST" > "$FOREIGN_OUTPUT" 2>&1
assert_count 0 '--user try-restart plasma-plasmashell.service' "$SYSTEMCTL_LOG"
assert_not_contains 'Notifications are unowned.' "$FOREIGN_OUTPUT"
assert_contains 'owned by another service; leaving it untouched' "$FOREIGN_OUTPUT"
assert_absent "$UNIT_FILE"
assert_absent "$WANTS_LINK"

mkdir -p "$(dirname "$WANTS_LINK")" "$(dirname "$AUTOSTART_FILE")" "$DEST" "$BIN_HOME"
printf '%s\n' '[Service]' > "$UNIT_FILE"
ln -s ../nagi-shell.service "$WANTS_LINK"
printf '%s\n' '[Desktop Entry]' > "$AUTOSTART_FILE"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$BIN_PATH"
chmod 0755 "$BIN_PATH"
: > "$SYSTEMCTL_LOG"
env -u SUDO_USER "${BASE_ENV[@]}" SYSTEMCTL_MANAGER_AVAILABLE=0 BUS_OWNER_STATE=foreign \
    bash "$CHECKOUT/uninstall.sh" --yes --dest "$DEST" > "$SANDBOX/uninstall-no-manager.out" 2>&1
assert_absent "$UNIT_FILE"
assert_absent "$WANTS_LINK"
assert_absent "$AUTOSTART_FILE"
assert_count 1 '--user disable --now nagi-shell.service' "$SYSTEMCTL_LOG"
assert_count 1 '--user daemon-reload' "$SYSTEMCTL_LOG"

NO_MANAGER_HOME="$SANDBOX/no-manager-home"
NO_MANAGER_CONFIG="$SANDBOX/no-manager-config"
NO_MANAGER_STATE="$SANDBOX/no-manager-state"
NO_MANAGER_DATA="$SANDBOX/no-manager-data"
NO_MANAGER_RUNTIME="$SANDBOX/no-manager-runtime"
NO_MANAGER_BIN="$SANDBOX/no-manager-bin/bin"
NO_MANAGER_DEST="$SANDBOX/no-manager-install/nagi-shell"
mkdir -p "$NO_MANAGER_HOME" "$NO_MANAGER_CONFIG" "$NO_MANAGER_STATE" \
    "$NO_MANAGER_DATA" "$NO_MANAGER_RUNTIME"
chmod 0700 "$NO_MANAGER_RUNTIME"
: > "$MAKE_LOG"
set +e
env -u SUDO_USER "${BASE_ENV[@]}" \
    HOME="$NO_MANAGER_HOME" XDG_CONFIG_HOME="$NO_MANAGER_CONFIG" \
    XDG_STATE_HOME="$NO_MANAGER_STATE" XDG_DATA_HOME="$NO_MANAGER_DATA" \
    XDG_RUNTIME_DIR="$NO_MANAGER_RUNTIME" XDG_BIN_HOME="$NO_MANAGER_BIN" \
    SYSTEMCTL_MANAGER_AVAILABLE=0 \
    bash "$CHECKOUT/install.sh" --yes --skip-packages --skip-shortcuts \
    --dest "$NO_MANAGER_DEST" > "$SANDBOX/install-no-manager.out" 2>&1
no_manager_status=$?
set -e
[ "$no_manager_status" -ne 0 ] || fail 'install succeeded without a user systemd manager'
assert_contains 'per-user systemd manager is unavailable' "$SANDBOX/install-no-manager.out"
assert_absent "$NO_MANAGER_DEST"
assert_absent "$NO_MANAGER_CONFIG/systemd/user/nagi-shell.service"
[ ! -s "$MAKE_LOG" ] || fail 'manager-unavailable install built or mutated the shell tree'

# --- sudo/SUDO_USER scenario ---------------------------------------------------
# A root+SUDO_USER run must resolve the same target-user roots an unprivileged
# run would: unit, default config, legacy autostart migration, launcher unit
# detection, and uninstall all target the XDG_CONFIG_HOME passed through sudo,
# and nothing may appear under the target user's default home or the (decoy)
# root home. The sandbox stays unprivileged: a shadowing `id` reports uid 0,
# `getent` serves a fixture passwd entry, and `runuser` simply drops the
# escalation syntax.

SUDO_USER_NAME="nagi-sudo-fixture"
SUDO_REAL_HOME="$SANDBOX/sudo-real-home"
SUDO_DECOY_ROOT_HOME="$SANDBOX/sudo-decoy-root-home"
SUDO_CONFIG_HOME="$SANDBOX/sudo-config-home"
SUDO_STATE_HOME="$SANDBOX/sudo-state-home"
SUDO_DATA_HOME="$SANDBOX/sudo-data-home"
SUDO_CACHE_HOME="$SANDBOX/sudo-cache-home"
SUDO_RUNTIME="$SANDBOX/sudo-runtime"
SUDO_BIN_HOME="$SANDBOX/sudo bin 100%-\$home/bin"
SUDO_DEST="$SANDBOX/sudo install tree 100%-\$dest/nagi-shell"
SUDO_SHARE_ROOT="${SUDO_DEST%/nagi-shell}"
SUDO_BIN_PATH="$SUDO_BIN_HOME/nagi-shell"
SUDO_UNIT_FILE="$SUDO_CONFIG_HOME/systemd/user/nagi-shell.service"
SUDO_WANTS_LINK="$SUDO_CONFIG_HOME/systemd/user/plasma-workspace-wayland.target.wants/nagi-shell.service"
SUDO_AUTOSTART_FILE="$SUDO_CONFIG_HOME/autostart/io.github.Anthodev.NagiShell.desktop"
SUDO_DESKTOP_FILE="$SUDO_SHARE_ROOT/applications/io.github.Anthodev.NagiShell.desktop"
SUDO_FAKE_ROOT_BIN="$SANDBOX/sudo-fake-root-bin"

mkdir -p "$SUDO_FAKE_ROOT_BIN" "$SUDO_REAL_HOME" "$SUDO_CONFIG_HOME" \
    "$SUDO_STATE_HOME" "$SUDO_DATA_HOME" "$SUDO_CACHE_HOME" "$SUDO_RUNTIME"
chmod 0700 "$SUDO_RUNTIME"

cat > "$SUDO_FAKE_ROOT_BIN/id" <<EOF_SUDO_ID
#!/bin/sh
set -eu
case "\${1:-}" in
    -u)
        if [ "\$#" -ge 2 ]; then
            printf '%s\n' '4242'
        else
            printf '%s\n' '0'
        fi
        ;;
    -un)
        printf '%s\n' '$SUDO_USER_NAME'
        ;;
    *)
        exec /usr/bin/id "\$@"
        ;;
esac
EOF_SUDO_ID
cat > "$SUDO_FAKE_ROOT_BIN/getent" <<EOF_SUDO_GETENT
#!/bin/sh
set -eu
if [ "\${1:-}" = passwd ] && [ "\$#" -eq 2 ] && [ "\$2" = '$SUDO_USER_NAME' ]; then
    printf '%s\n' '$SUDO_USER_NAME:x:4242:4242:fixture:$SUDO_REAL_HOME:/bin/sh'
else
    exec /usr/bin/getent "\$@"
fi
EOF_SUDO_GETENT
cat > "$SUDO_FAKE_ROOT_BIN/runuser" <<'EOF_SUDO_RUNUSER'
#!/bin/sh
set -eu
[ "${1:-}" = "-u" ] && [ "$#" -ge 3 ] || exit 64
shift 2
[ "${1:-}" = "--" ] || exit 64
shift
exec "$@"
EOF_SUDO_RUNUSER
chmod 0755 "$SUDO_FAKE_ROOT_BIN/id" "$SUDO_FAKE_ROOT_BIN/getent" \
    "$SUDO_FAKE_ROOT_BIN/runuser"

SUDO_ENV=()
for base_entry in "${BASE_ENV[@]}"; do
    case "$base_entry" in
        PATH=*) SUDO_ENV+=("PATH=$SUDO_FAKE_ROOT_BIN:$FAKE_BIN:/usr/bin:/bin") ;;
        HOME=*) SUDO_ENV+=("HOME=$SUDO_DECOY_ROOT_HOME") ;;
        XDG_CONFIG_HOME=*) SUDO_ENV+=("XDG_CONFIG_HOME=$SUDO_CONFIG_HOME") ;;
        XDG_STATE_HOME=*) SUDO_ENV+=("XDG_STATE_HOME=$SUDO_STATE_HOME") ;;
        XDG_DATA_HOME=*) SUDO_ENV+=("XDG_DATA_HOME=$SUDO_DATA_HOME") ;;
        XDG_CACHE_HOME=*) SUDO_ENV+=("XDG_CACHE_HOME=$SUDO_CACHE_HOME") ;;
        XDG_RUNTIME_DIR=*) SUDO_ENV+=("XDG_RUNTIME_DIR=$SUDO_RUNTIME") ;;
        XDG_BIN_HOME=*) SUDO_ENV+=("XDG_BIN_HOME=$SUDO_BIN_HOME") ;;
        *) SUDO_ENV+=("$base_entry") ;;
    esac
done
SUDO_ENV+=("SUDO_USER=$SUDO_USER_NAME")

mkdir -p "$(dirname "$SUDO_AUTOSTART_FILE")"
printf '%s\n' '[Desktop Entry]' > "$SUDO_AUTOSTART_FILE"
: > "$SYSTEMCTL_LOG"
: > "$BUSCTL_LOG"
SUDO_INSTALL_OUTPUT="$SANDBOX/sudo-install.out"
env "${SUDO_ENV[@]}" bash "$CHECKOUT/install.sh" --yes --skip-packages \
    --skip-shortcuts --dest "$SUDO_DEST" > "$SUDO_INSTALL_OUTPUT" 2>&1

assert_file "$SUDO_UNIT_FILE"
[ "$(stat -c '%a' "$SUDO_UNIT_FILE")" = "644" ] ||
    fail 'sudo scenario user unit mode is not 0644'
[ -L "$SUDO_WANTS_LINK" ] ||
    fail 'sudo install did not enable nagi-shell.service in the custom root'
assert_file "$SUDO_BIN_PATH"
assert_file "$SUDO_DESKTOP_FILE"
assert_file "$SUDO_CONFIG_HOME/nagi-shell/settings.conf"
assert_absent "$SUDO_AUTOSTART_FILE"
assert_contains 'Log out and back in' "$SUDO_INSTALL_OUTPUT"
assert_count 1 '--user daemon-reload' "$SYSTEMCTL_LOG"
assert_count 1 '--user enable nagi-shell.service' "$SYSTEMCTL_LOG"
# No state may land under the target user's default roots or the root home.
assert_absent "$SUDO_REAL_HOME/.config"
assert_absent "$SUDO_REAL_HOME/.local"
assert_absent "$SUDO_DECOY_ROOT_HOME"

: > "$SYSTEMCTL_LOG"
: > "$QS_LOG"
rm -f -- "$QS_READY_FILE"
env "${SUDO_ENV[@]}" "$SUDO_BIN_PATH"
assert_count 1 '--user start nagi-shell.service' "$SYSTEMCTL_LOG"
[ ! -s "$QS_LOG" ] || fail 'sudo scenario plain launch bypassed nagi-shell.service'

: > "$SYSTEMCTL_LOG"
: > "$BUSCTL_LOG"
: > "$TIMEOUT_LOG"
SUDO_UNINSTALL_OUTPUT="$SANDBOX/sudo-uninstall.out"
env "${SUDO_ENV[@]}" bash "$CHECKOUT/uninstall.sh" --yes --dest "$SUDO_DEST" \
    > "$SUDO_UNINSTALL_OUTPUT" 2>&1
assert_absent "$SUDO_UNIT_FILE"
assert_absent "$SUDO_WANTS_LINK"
assert_absent "$SUDO_AUTOSTART_FILE"
assert_absent "$SUDO_BIN_PATH"
assert_absent "$SUDO_DEST"
assert_absent "$SUDO_DESKTOP_FILE"
assert_absent "$SUDO_CONFIG_HOME/nagi-shell"
assert_absent "$SUDO_STATE_HOME/nagi-shell"
assert_count 1 '--user disable --now nagi-shell.service' "$SYSTEMCTL_LOG"
assert_count 1 '--user daemon-reload' "$SYSTEMCTL_LOG"
assert_count 1 '--user try-restart plasma-plasmashell.service' "$SYSTEMCTL_LOG"
assert_count 1 '--signal=TERM 15 systemctl --user try-restart plasma-plasmashell.service' \
    "$TIMEOUT_LOG"
assert_absent "$SUDO_REAL_HOME/.config"
assert_absent "$SUDO_REAL_HOME/.local"

# --- sudo with stripped environment scenario -------------------------------------
# The common `sudo ./install.sh` case: sudo strips XDG_CONFIG_HOME and
# XDG_STATE_HOME entirely. The scripts must recover the target user's decoded
# roots through the systemd manager, even when show-environment uses shell
# quoting for whitespace and metacharacters. The launcher must still find the
# unit in the manager's actual search path.

MANAGER_INJECTION_MARKER="$SANDBOX/manager-environment-injection"
SUDO_MGR_CONFIG_HOME="$SANDBOX/sudo manager config"$'\t'"100%-\$cash-'single'-\"double\"-\\backslash-\$(touch \"$MANAGER_INJECTION_MARKER\")"
SUDO_MGR_STATE_HOME="$SANDBOX/sudo manager state"$'\t'"100%-\$state-'single'-\"double\"-\\backslash"
SUDO_MGR_RUNTIME="$SANDBOX/sudo-manager-runtime"
SUDO_MGR_BIN_HOME="$SANDBOX/sudo mgr bin 100%-\$home/bin"
SUDO_MGR_DEST="$SANDBOX/sudo mgr install tree 100%-\$dest/nagi-shell"
SUDO_MGR_SHARE_ROOT="${SUDO_MGR_DEST%/nagi-shell}"
SUDO_MGR_BIN_PATH="$SUDO_MGR_BIN_HOME/nagi-shell"
SUDO_MGR_UNIT_FILE="$SUDO_MGR_CONFIG_HOME/systemd/user/nagi-shell.service"
SUDO_MGR_WANTS_LINK="$SUDO_MGR_CONFIG_HOME/systemd/user/plasma-workspace-wayland.target.wants/nagi-shell.service"
SUDO_MGR_DESKTOP_FILE="$SUDO_MGR_SHARE_ROOT/applications/io.github.Anthodev.NagiShell.desktop"

mkdir -p "$SUDO_MGR_CONFIG_HOME" "$SUDO_MGR_STATE_HOME" "$SUDO_MGR_RUNTIME"
chmod 0700 "$SUDO_MGR_RUNTIME"

SUDO_MANAGER_ENV_FILE="$SANDBOX/sudo-manager-environment"
printf 'XDG_CONFIG_HOME=%q\nXDG_STATE_HOME=%q\n' \
    "$SUDO_MGR_CONFIG_HOME" "$SUDO_MGR_STATE_HOME" > "$SUDO_MANAGER_ENV_FILE"
# A compromised/malformed response must remain data; sourcing the response
# would execute this command-shaped record.
printf 'UNTRUSTED=$(touch %q)\n' "$MANAGER_INJECTION_MARKER" \
    >> "$SUDO_MANAGER_ENV_FILE"
assert_contains 'XDG_CONFIG_HOME=$' "$SUDO_MANAGER_ENV_FILE"
assert_contains 'XDG_STATE_HOME=$' "$SUDO_MANAGER_ENV_FILE"

SUDO_STRIPPED_ENV=()
for sudo_entry in "${SUDO_ENV[@]}"; do
    case "$sudo_entry" in
        XDG_CONFIG_HOME=*|XDG_STATE_HOME=*|XDG_BIN_HOME=*) ;;
        *) SUDO_STRIPPED_ENV+=("$sudo_entry") ;;
    esac
done
SUDO_STRIPPED_ENV+=("SYSTEMCTL_MANAGER_ENV_FILE=$SUDO_MANAGER_ENV_FILE")
SUDO_STRIPPED_ENV+=("SYSTEMD_RUN_MANAGER_CONFIG_HOME=$SUDO_MGR_CONFIG_HOME")
SUDO_STRIPPED_ENV+=("SYSTEMD_RUN_MANAGER_STATE_HOME=$SUDO_MGR_STATE_HOME")
SUDO_STRIPPED_ENV+=("XDG_BIN_HOME=$SUDO_MGR_BIN_HOME")

: > "$SYSTEMCTL_LOG"
: > "$SYSTEMD_RUN_LOG"
: > "$BUSCTL_LOG"
SUDO_MGR_INSTALL_OUTPUT="$SANDBOX/sudo-manager-install.out"
(
    cd "$SANDBOX"
    env "${SUDO_STRIPPED_ENV[@]}" bash "$CHECKOUT/install.sh" --yes --skip-packages \
        --skip-shortcuts --dest "$SUDO_MGR_DEST"
) > "$SUDO_MGR_INSTALL_OUTPUT" 2>&1

assert_file "$SUDO_MGR_UNIT_FILE"
[ -L "$SUDO_MGR_WANTS_LINK" ] ||
    fail 'stripped-env sudo install ignored the manager XDG root'
assert_file "$SUDO_MGR_BIN_PATH"
assert_file "$SUDO_MGR_DESKTOP_FILE"
assert_file "$SUDO_MGR_CONFIG_HOME/nagi-shell/settings.conf"
assert_absent "$SUDO_REAL_HOME/.config"
assert_absent "$SUDO_REAL_HOME/.local"
assert_absent "$SUDO_DECOY_ROOT_HOME"
assert_absent "$MANAGER_INJECTION_MARKER"
MANAGER_PRINTENV_PATH="$(
    PATH="$SUDO_FAKE_ROOT_BIN:$FAKE_BIN:/usr/bin:/bin" type -P printenv
)"
assert_count 1 "--user --wait --pipe --quiet --collect --service-type=exec $MANAGER_PRINTENV_PATH XDG_CONFIG_HOME" \
    "$SYSTEMD_RUN_LOG"
assert_count 1 "--user --wait --pipe --quiet --collect --service-type=exec $MANAGER_PRINTENV_PATH XDG_STATE_HOME" \
    "$SYSTEMD_RUN_LOG"

: > "$SYSTEMCTL_LOG"
: > "$QS_LOG"
rm -f -- "$QS_READY_FILE"
env XDG_CONFIG_HOME="$SUDO_MGR_CONFIG_HOME" "${SUDO_STRIPPED_ENV[@]}" "$SUDO_MGR_BIN_PATH"
assert_count 1 '--user start nagi-shell.service' "$SYSTEMCTL_LOG"
[ ! -s "$QS_LOG" ] || fail 'stripped-env sudo scenario launch bypassed nagi-shell.service'

: > "$SYSTEMCTL_LOG"
: > "$BUSCTL_LOG"
: > "$TIMEOUT_LOG"
mkdir -p "$SUDO_MGR_STATE_HOME/nagi-shell"
printf '%s\n' 'state fixture' > "$SUDO_MGR_STATE_HOME/nagi-shell/fixture"
(
    cd "$SANDBOX"
    env "${SUDO_STRIPPED_ENV[@]}" bash "$CHECKOUT/uninstall.sh" --yes \
        --dest "$SUDO_MGR_DEST"
) > "$SANDBOX/sudo-manager-uninstall.out" 2>&1
assert_absent "$SUDO_MGR_UNIT_FILE"
assert_absent "$SUDO_MGR_WANTS_LINK"
assert_absent "$SUDO_MGR_BIN_PATH"
assert_absent "$SUDO_MGR_DEST"
assert_absent "$SUDO_MGR_DESKTOP_FILE"
assert_absent "$SUDO_MGR_CONFIG_HOME/nagi-shell"
assert_absent "$SUDO_MGR_STATE_HOME/nagi-shell"
assert_count 1 '--user disable --now nagi-shell.service' "$SYSTEMCTL_LOG"
assert_count 1 '--user daemon-reload' "$SYSTEMCTL_LOG"
assert_count 1 '--user try-restart plasma-plasmashell.service' "$SYSTEMCTL_LOG"
assert_absent "$SUDO_REAL_HOME/.config"
assert_absent "$SUDO_REAL_HOME/.local"
assert_absent "$MANAGER_INJECTION_MARKER"
assert_count 2 "--user --wait --pipe --quiet --collect --service-type=exec $MANAGER_PRINTENV_PATH XDG_CONFIG_HOME" \
    "$SYSTEMD_RUN_LOG"
assert_count 2 "--user --wait --pipe --quiet --collect --service-type=exec $MANAGER_PRINTENV_PATH XDG_STATE_HOME" \
    "$SYSTEMD_RUN_LOG"

# --- non-absolute manager roots ------------------------------------------------
# XDG roots must be absolute. A malformed manager environment therefore falls
# back to the target user's home defaults for both install and uninstall.
SUDO_INVALID_CWD="$SANDBOX/sudo-invalid-manager-cwd"
SUDO_INVALID_CONFIG="relative manager config"$'\t'"100%-\$cash-'single'-\"double\"-\\backslash"
SUDO_INVALID_STATE="relative manager state"$'\t'"100%-\$state"
SUDO_INVALID_BIN_HOME="$SANDBOX/sudo invalid manager bin/bin"
SUDO_INVALID_DEST="$SANDBOX/sudo invalid manager install/nagi-shell"
SUDO_INVALID_SHARE_ROOT="${SUDO_INVALID_DEST%/nagi-shell}"
SUDO_INVALID_BIN_PATH="$SUDO_INVALID_BIN_HOME/nagi-shell"
SUDO_INVALID_CONFIG_HOME="$SUDO_REAL_HOME/.config"
SUDO_INVALID_STATE_HOME="$SUDO_REAL_HOME/.local/state"
SUDO_INVALID_UNIT_FILE="$SUDO_INVALID_CONFIG_HOME/systemd/user/nagi-shell.service"
SUDO_INVALID_WANTS_LINK="$SUDO_INVALID_CONFIG_HOME/systemd/user/plasma-workspace-wayland.target.wants/nagi-shell.service"
SUDO_INVALID_DESKTOP_FILE="$SUDO_INVALID_SHARE_ROOT/applications/io.github.Anthodev.NagiShell.desktop"
mkdir -p "$SUDO_INVALID_CWD"

SUDO_INVALID_MANAGER_ENV_FILE="$SANDBOX/sudo-invalid-manager-environment"
printf 'XDG_CONFIG_HOME=%q\nXDG_STATE_HOME=%q\n' \
    "$SUDO_INVALID_CONFIG" "$SUDO_INVALID_STATE" \
    > "$SUDO_INVALID_MANAGER_ENV_FILE"
assert_contains 'XDG_CONFIG_HOME=$' "$SUDO_INVALID_MANAGER_ENV_FILE"
assert_contains 'XDG_STATE_HOME=$' "$SUDO_INVALID_MANAGER_ENV_FILE"

SUDO_INVALID_ENV=()
for sudo_entry in "${SUDO_STRIPPED_ENV[@]}"; do
    case "$sudo_entry" in
        SYSTEMCTL_MANAGER_ENV_FILE=*|SYSTEMD_RUN_MANAGER_CONFIG_HOME=*|\
            SYSTEMD_RUN_MANAGER_STATE_HOME=*|XDG_BIN_HOME=*) ;;
        *) SUDO_INVALID_ENV+=("$sudo_entry") ;;
    esac
done
SUDO_INVALID_ENV+=("SYSTEMCTL_MANAGER_ENV_FILE=$SUDO_INVALID_MANAGER_ENV_FILE")
SUDO_INVALID_ENV+=("SYSTEMD_RUN_MANAGER_CONFIG_HOME=$SUDO_INVALID_CONFIG")
SUDO_INVALID_ENV+=("SYSTEMD_RUN_MANAGER_STATE_HOME=$SUDO_INVALID_STATE")
SUDO_INVALID_ENV+=("XDG_BIN_HOME=$SUDO_INVALID_BIN_HOME")

: > "$SYSTEMCTL_LOG"
: > "$SYSTEMD_RUN_LOG"
: > "$BUSCTL_LOG"
SUDO_INVALID_INSTALL_OUTPUT="$SANDBOX/sudo-invalid-manager-install.out"
(
    cd "$SUDO_INVALID_CWD"
    env "${SUDO_INVALID_ENV[@]}" bash "$CHECKOUT/install.sh" --yes --skip-packages \
        --skip-shortcuts --dest "$SUDO_INVALID_DEST"
) > "$SUDO_INVALID_INSTALL_OUTPUT" 2>&1

assert_contains "Ignoring non-absolute XDG_CONFIG_HOME from the target user's systemd manager." \
    "$SUDO_INVALID_INSTALL_OUTPUT"
assert_contains "Ignoring non-absolute XDG_STATE_HOME from the target user's systemd manager." \
    "$SUDO_INVALID_INSTALL_OUTPUT"
assert_file "$SUDO_INVALID_UNIT_FILE"
[ -L "$SUDO_INVALID_WANTS_LINK" ] ||
    fail 'invalid manager roots did not fall back to the target home'
assert_file "$SUDO_INVALID_CONFIG_HOME/nagi-shell/settings.conf"
assert_file "$SUDO_INVALID_BIN_PATH"
assert_file "$SUDO_INVALID_DESKTOP_FILE"
assert_absent "$SUDO_INVALID_CWD/$SUDO_INVALID_CONFIG"
assert_absent "$SUDO_INVALID_CWD/$SUDO_INVALID_STATE"
assert_absent "$SUDO_DECOY_ROOT_HOME"

mkdir -p "$SUDO_INVALID_STATE_HOME/nagi-shell"
printf '%s\n' 'state fixture' > "$SUDO_INVALID_STATE_HOME/nagi-shell/fixture"
: > "$SYSTEMCTL_LOG"
: > "$BUSCTL_LOG"
: > "$TIMEOUT_LOG"
SUDO_INVALID_UNINSTALL_OUTPUT="$SANDBOX/sudo-invalid-manager-uninstall.out"
(
    cd "$SUDO_INVALID_CWD"
    env "${SUDO_INVALID_ENV[@]}" bash "$CHECKOUT/uninstall.sh" --yes \
        --dest "$SUDO_INVALID_DEST"
) > "$SUDO_INVALID_UNINSTALL_OUTPUT" 2>&1

assert_contains "Ignoring non-absolute XDG_CONFIG_HOME from the target user's systemd manager." \
    "$SUDO_INVALID_UNINSTALL_OUTPUT"
assert_contains "Ignoring non-absolute XDG_STATE_HOME from the target user's systemd manager." \
    "$SUDO_INVALID_UNINSTALL_OUTPUT"
assert_absent "$SUDO_INVALID_UNIT_FILE"
assert_absent "$SUDO_INVALID_WANTS_LINK"
assert_absent "$SUDO_INVALID_CONFIG_HOME/nagi-shell"
assert_absent "$SUDO_INVALID_STATE_HOME/nagi-shell"
assert_absent "$SUDO_INVALID_BIN_PATH"
assert_absent "$SUDO_INVALID_DEST"
assert_absent "$SUDO_INVALID_DESKTOP_FILE"
assert_absent "$SUDO_INVALID_CWD/$SUDO_INVALID_CONFIG"
assert_absent "$SUDO_INVALID_CWD/$SUDO_INVALID_STATE"
assert_count 2 "--user --wait --pipe --quiet --collect --service-type=exec $MANAGER_PRINTENV_PATH XDG_CONFIG_HOME" \
    "$SYSTEMD_RUN_LOG"
assert_count 2 "--user --wait --pipe --quiet --collect --service-type=exec $MANAGER_PRINTENV_PATH XDG_STATE_HOME" \
    "$SYSTEMD_RUN_LOG"

printf '%s\n' 'notification startup packaging tests passed'
