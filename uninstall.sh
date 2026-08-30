#!/usr/bin/env bash
# =============================================================================
#   Nagi Shell - uninstaller
#
#   Disables and stops the per-user service, removes the "Nagi Shell" shortcut
#   section from KGlobalAccel over D-Bus (never by editing raw config files),
#   removes the launcher wrapper, desktop entry, installation directory, and
#   the invoking user's nagi-shell configuration and state directories.
#
#   Idempotent: safe to re-run. Two bounded caches are intentionally retained:
#   the weather cache under Quickshell's cache directory and the wallpaper
#   thumbnail cache under the cache root (~/.cache/nagi-shell/). Both are
#   inert once the shell is gone; user cache data is never deleted here.
# =============================================================================
set -euo pipefail

COMPONENT_ID="io.github.Anthodev.NagiShell"
DEFAULT_DEST="/usr/share/nagi-shell"

DEST="$DEFAULT_DEST"
ASSUME_YES=0

log_info() { printf '[INFO]  %s\n' "$*"; }
log_ok()   { printf '[OK]    %s\n' "$*"; }
log_warn() { printf '[WARN]  %s\n' "$*" >&2; }
log_fatal() {
    printf '[FATAL] %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  -y, --yes        Assume yes; do not ask for confirmation
      --dest DIR   Installation directory to remove (default: $DEFAULT_DEST)
  -h, --help       Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --dest) [ $# -ge 2 ] || log_fatal "--dest requires a value"; DEST="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_fatal "Unknown option: $1 (see --help)" ;;
    esac
    shift
done

# --- privilege / user resolution -------------------------------------------------

REAL_USER="${SUDO_USER:-$(id -un)}"
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
else
    REAL_HOME="${HOME}"
fi
real_user_config_dir() {
    printf '%s/nagi-shell' "${XDG_CONFIG_HOME:-${SUDO_MANAGER_CONFIG_HOME:-$REAL_HOME/.config}}"
}
real_user_state_dir() {
    printf '%s/nagi-shell' "${XDG_STATE_HOME:-${SUDO_MANAGER_STATE_HOME:-$REAL_HOME/.local/state}}"
}
run_as_real_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        local uid
        uid="$(id -u "$REAL_USER")"
        runuser -u "$REAL_USER" -- env \
            HOME="$REAL_HOME" \
            XDG_CONFIG_HOME="$(dirname "$(real_user_config_dir)")" \
            XDG_STATE_HOME="$(dirname "$(real_user_state_dir)")" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            XDG_RUNTIME_DIR="/run/user/$uid" \
            "$@"
    else
        "$@"
    fi
}

# Sudo normally strips XDG_CONFIG_HOME/XDG_STATE_HOME. When it does, ask the
# target user's manager to launch printenv so the manager's decoded values cross
# the privilege boundary as data, never as shell source. This is best-effort,
# because uninstall must still complete explicit cleanup without the manager.
SUDO_MANAGER_CONFIG_HOME=""
SUDO_MANAGER_STATE_HOME=""
MANAGER_PRINTENV=""
manager_environment_root() {
    local variable="$1" output
    if ! output="$(
        run_as_real_user timeout --signal=TERM 5 \
            systemd-run --user --wait --pipe --quiet --collect \
            --service-type=exec "$MANAGER_PRINTENV" "$variable" \
            2>/dev/null &&
            printf '\034'
    )"; then
        return 1
    fi

    # The sentinel prevents command substitution from stripping whitespace at
    # the end of the value. Remove it and printenv's one record terminator.
    output="${output%$'\034'}"
    output="${output%$'\n'}"
    [ -n "$output" ] || return 1
    case "$output" in
        /*) printf '%s' "$output" ;;
        *)
            log_warn "Ignoring non-absolute $variable from the target user's systemd manager."
            return 1
            ;;
    esac
}
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] &&
        { [ -z "${XDG_CONFIG_HOME:-}" ] || [ -z "${XDG_STATE_HOME:-}" ]; }; then
    MANAGER_PRINTENV="$(type -P printenv 2>/dev/null || true)"
    manager_reader_available=0
    if command -v systemd-run >/dev/null 2>&1; then
        case "$MANAGER_PRINTENV" in
            /*) [ -x "$MANAGER_PRINTENV" ] && manager_reader_available=1 ;;
        esac
    fi
    if [ "$manager_reader_available" -eq 1 ]; then
        if [ -z "${XDG_CONFIG_HOME:-}" ]; then
            SUDO_MANAGER_CONFIG_HOME="$(
                manager_environment_root XDG_CONFIG_HOME || true
            )"
        fi
        if [ -z "${XDG_STATE_HOME:-}" ]; then
            SUDO_MANAGER_STATE_HOME="$(
                manager_environment_root XDG_STATE_HOME || true
            )"
        fi
    else
        log_warn "Could not safely read stripped XDG roots from the target user's systemd manager; using home defaults."
    fi
fi

USER_CONFIG_HOME="$(dirname "$(real_user_config_dir)")"
SYSTEMD_USER_DIR="$USER_CONFIG_HOME/systemd/user"
UNIT_FILE="$SYSTEMD_USER_DIR/nagi-shell.service"
WANTS_LINK="$SYSTEMD_USER_DIR/plasma-workspace-wayland.target.wants/nagi-shell.service"
LEGACY_AUTOSTART_FILE="$USER_CONFIG_HOME/autostart/io.github.Anthodev.NagiShell.desktop"

rm_root_or_local() {
    if [ ! -e "$1" ] && [ ! -L "$1" ]; then
        return 0
    fi
    if [ "$(id -u)" -eq 0 ] || [ -w "$(dirname "$1")" ]; then
        rm -rf -- "$1"
    elif command -v sudo >/dev/null 2>&1; then
        sudo rm -rf -- "$1"
    else
        log_warn "Cannot remove '$1' without sudo."
        return 1
    fi
}

# --- confirmation ------------------------------------------------------------------

echo "About to uninstall Nagi Shell:"
echo "  instance          : user service disabled and stopped; qs kill retained as fallback"
echo "  user service      : $UNIT_FILE and its target wants link removed"
echo "  KDE shortcuts     : 'Nagi Shell' section removed through the KGlobalAccel D-Bus API"
echo "  launcher          : bin/nagi-shell wrapper removed"
echo "  desktop entry     : share/applications/io.github.Anthodev.NagiShell.desktop removed"
echo "  installation      : $DEST removed"
echo "  configuration     : $(real_user_config_dir) removed"
echo "  application state : $(real_user_state_dir) removed (pins, recency, onboarding record)"
echo "  retained caches   : weather (Quickshell's cache directory) and wallpaper"
echo "                      thumbnail (~/.cache/nagi-shell/) caches stay on disk by design"
echo "  legacy autostart  : $LEGACY_AUTOSTART_FILE removed"
echo "  notifications     : one bounded plasmashell restart is offered only if the name is unowned"
echo
if [ "$ASSUME_YES" -eq 0 ]; then
    printf 'Proceed with uninstallation? [y/N]: '
    read -r answer
    case "${answer:-n}" in
        y|yes) ;;
        *) log_fatal "Uninstallation aborted." ;;
    esac
fi

# --- stop and unregister the running instance ----------------------------------------

if command -v systemctl >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
    if run_as_real_user timeout --signal=TERM 15 \
            systemctl --user disable --now nagi-shell.service; then
        log_info "Disabled and stopped nagi-shell.service."
    else
        log_warn "Could not disable/stop nagi-shell.service through the user manager; continuing with explicit cleanup."
    fi
else
    log_warn "systemctl or timeout is unavailable; continuing with explicit user-unit cleanup."
fi

if command -v qs >/dev/null 2>&1; then
    if run_as_real_user qs kill -p "$DEST" >/dev/null 2>&1; then
        log_info "Stopped the running Nagi Shell instance."
    fi
else
    log_warn "qs is unavailable; cannot use the process-stop fallback."
fi

rm_root_or_local "$UNIT_FILE"
rm_root_or_local "$WANTS_LINK"
rm_root_or_local "$LEGACY_AUTOSTART_FILE"
if command -v systemctl >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
    run_as_real_user timeout --signal=TERM 10 systemctl --user daemon-reload ||
        log_warn "The user manager is unavailable; removed unit files will be reloaded at the next login."
fi

# --- remove the KGlobalAccel section ---------------------------------------------------

remove_shortcut_section() {
    command -v busctl >/dev/null 2>&1 || { log_warn "busctl unavailable; skipping automated shortcut cleanup."; return 1; }

    local actions_json
    actions_json="$(run_as_real_user busctl --user call --json=short org.kde.kglobalaccel /kglobalaccel \
        org.kde.KGlobalAccel allActionsForComponent as 1 "$COMPONENT_ID" 2>/dev/null || true)"
    if [ -z "$actions_json" ] || [ "$actions_json" = "null" ] || [ "$actions_json" = "[]" ]; then
        log_info "'Nagi Shell' has no shortcuts registered with KGlobalAccel."
        return 0
    fi

    command -v python3 >/dev/null 2>&1 || {
        log_warn "python3 unavailable; cannot drive per-action unregistration."
        log_warn "Remove remaining entries manually under System Settings -> Keyboard -> Shortcuts -> Nagi Shell."
        return 1
    }

    # Feed each registered action back to unRegister through the same public
    # D-Bus API the daemon exposes; never touch kglobalshortcutsrc directly.
    local busctl_args
    while IFS= read -r busctl_args; do
        [ -n "$busctl_args" ] || continue
        # shellcheck disable=SC2086
        run_as_real_user busctl --user call org.kde.kglobalaccel /kglobalaccel \
            org.kde.KGlobalAccel unRegister $busctl_args >/dev/null 2>&1 ||
            log_warn "unRegister failed for: $busctl_args"
    done < <(printf '%s' "$actions_json" | python3 -c '
import json, shlex, sys
data = json.load(sys.stdin)
for action_id in data:
    print(" ".join(shlex.quote(part) for part in ["as", str(len(action_id))] + list(action_id)))
')

    local remaining
    remaining="$(run_as_real_user busctl --user call --json=short org.kde.kglobalaccel /kglobalaccel \
        org.kde.KGlobalAccel allActionsForComponent as 1 "$COMPONENT_ID" 2>/dev/null || true)"
    if [ -z "$remaining" ] || [ "$remaining" = "[]" ] || [ "$remaining" = "null" ]; then
        log_ok "'Nagi Shell' shortcut section removed from KDE keyboard settings."
    else
        log_warn "Some shortcut entries remain; remove them under System Settings -> Keyboard -> Shortcuts -> Nagi Shell."
        return 1
    fi
}

if run_as_real_user busctl --user call --json=short org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus.NameHasOwner s org.kde.kglobalaccel 2>/dev/null | grep -q true; then
    remove_shortcut_section || true
else
    log_info "KGlobalAccel is not reachable on this session bus; skipping shortcut cleanup."
fi

# --- remove files ------------------------------------------------------------------------

case "$DEST" in
    /usr/*|/opt/*|/bin/*|/sbin/*) BIN_PATH="/usr/local/bin/nagi-shell" ;;
    *) BIN_BASE="${XDG_BIN_HOME:-${XDG_DATA_HOME:-$REAL_HOME/.local/share}/../bin}"
       BIN_BASE="${BIN_BASE%/bin}/bin"
       [ "$BIN_BASE" = "/bin" ] && BIN_BASE="$REAL_HOME/.local/bin"
       if [ -d "$BIN_BASE" ]; then
           BIN_BASE="$(cd "$BIN_BASE" && pwd)"
       fi
       BIN_PATH="$BIN_BASE/nagi-shell"
       ;;
esac

SHARE_DIR="${DEST%/nagi-shell}"
rm_root_or_local "$BIN_PATH"
rm_root_or_local "$DEST"
rm_root_or_local "$SHARE_DIR/applications/io.github.Anthodev.NagiShell.desktop"
log_ok "Launcher, desktop entry, and installation directory removed."

CONFIG_DIR="$(real_user_config_dir)"
STATE_DIR="$(real_user_state_dir)"
if [ -e "$CONFIG_DIR" ] || [ -L "$CONFIG_DIR" ]; then
    rm_root_or_local "$CONFIG_DIR"
    log_ok "Configuration removed: $CONFIG_DIR"
fi
if [ -e "$STATE_DIR" ] || [ -L "$STATE_DIR" ]; then
    rm_root_or_local "$STATE_DIR"
    log_ok "Application state removed: $STATE_DIR"
fi



restore_notifications() {
    if ! command -v busctl >/dev/null 2>&1 ||
            ! command -v systemctl >/dev/null 2>&1 ||
            ! command -v timeout >/dev/null 2>&1; then
        log_info "Automatic Plasma notification reclaim is unavailable; log out and back in."
        return 0
    fi

    local owner_reply
    if ! owner_reply="$(run_as_real_user timeout --signal=TERM 5 \
            busctl --user call --json=short org.freedesktop.DBus \
            /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner \
            s org.freedesktop.Notifications 2>/dev/null)"; then
        log_info "Could not determine notification ownership; leaving the session untouched."
        return 0
    fi
    case "$owner_reply" in
        *true*)
            log_info "org.freedesktop.Notifications is owned by another service; leaving it untouched."
            return 0
            ;;
        *false*) ;;
        *)
            log_info "Notification ownership reply was not understood; leaving the session untouched."
            return 0
            ;;
    esac

    local plasma_units
    if ! plasma_units="$(run_as_real_user timeout --signal=TERM 5 \
            systemctl --user list-unit-files --no-legend \
            plasma-plasmashell.service 2>/dev/null)" ||
            [[ "$plasma_units" != *plasma-plasmashell.service* ]]; then
        log_info "plasma-plasmashell.service not found; log out and back in to reclaim notifications."
        return 0
    fi

    local answer
    if [ "$ASSUME_YES" -eq 1 ]; then
        answer=y
    else
        printf 'Notifications are unowned. Restart plasmashell once so Plasma can reclaim them? The desktop will blink. [Y/n]: '
        read -r answer
        case "${answer:-y}" in n|no) return 0 ;; esac
    fi

    if run_as_real_user timeout --signal=TERM 15 \
            systemctl --user try-restart plasma-plasmashell.service; then
        log_ok "Requested one bounded plasmashell restart for notification reclaim."
    else
        log_warn "plasmashell restart failed; log out and back in to reclaim notifications."
    fi
}
restore_notifications

echo
log_ok "Nagi Shell uninstalled."
