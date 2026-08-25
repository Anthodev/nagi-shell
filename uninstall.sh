#!/usr/bin/env bash
# =============================================================================
#   Nagi Shell - uninstaller
#
#   Stops the installed instance, removes the "Nagi Shell" shortcut section
#   from KGlobalAccel over D-Bus (never by editing raw config files), removes
#   the launcher wrapper, desktop entry, installation directory, and the
#   invoking user's nagi-shell configuration and state directories.
#
#   Idempotent: safe to re-run. The bounded weather cache under Quickshell's
#   cache directory is left in place (it is inert once the shell is gone).
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
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        printf '%s/.config/nagi-shell' "$REAL_HOME"
    else
        printf '%s/nagi-shell' "${XDG_CONFIG_HOME:-$REAL_HOME/.config}"
    fi
}
real_user_state_dir() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        printf '%s/.local/state/nagi-shell' "$REAL_HOME"
    else
        printf '%s/nagi-shell' "${XDG_STATE_HOME:-$REAL_HOME/.local/state}"
    fi
}
run_as_real_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        local uid
        uid="$(id -u "$REAL_USER")"
        runuser -u "$REAL_USER" -- env \
            HOME="$REAL_HOME" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            XDG_RUNTIME_DIR="/run/user/$uid" \
            "$@"
    else
        "$@"
    fi
}

# --- confirmation ------------------------------------------------------------------

echo "About to uninstall Nagi Shell:"
echo "  instance          : stopped ($DEST)"
echo "  KDE shortcuts     : 'Nagi Shell' section removed through the KGlobalAccel D-Bus API"
echo "  launcher          : bin/nagi-shell wrapper removed"
echo "  desktop entry     : share/applications/io.github.Anthodev.NagiShell.desktop removed"
echo "  installation      : $DEST removed"
echo "  configuration     : $(real_user_config_dir) removed"
echo "  application state : $(real_user_state_dir) removed (pins, recency, onboarding record)"
echo "  session autostart : ~/.config/autostart entry removed"
echo "  notifications     : plasmashell restart offered so Plasma reclaims org.freedesktop.Notifications"
echo
if [ "$ASSUME_YES" -eq 0 ]; then
    printf 'Proceed with uninstallation? [y/N]: '
    read -r answer
    case "${answer:-n}" in
        y|yes) ;;
        *) log_fatal "Uninstallation aborted." ;;
    esac
fi

# --- stop the running instance -------------------------------------------------------

if command -v qs >/dev/null 2>&1; then
    if run_as_real_user qs kill -p "$DEST" >/dev/null 2>&1; then
        log_info "Stopped the running Nagi Shell instance."
    fi
else
    log_warn "qs is unavailable; cannot stop a running instance cleanly."
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
rm_root_or_local() {
    if [ -e "$1" ]; then
        if [ -w "$(dirname "$1")" ]; then
            rm -rf -- "$1"
        else
            sudo rm -rf -- "$1"
        fi
    fi
}
rm_root_or_local "$BIN_PATH"
rm_root_or_local "$DEST"
rm_root_or_local "$SHARE_DIR/applications/io.github.Anthodev.NagiShell.desktop"
log_ok "Launcher, desktop entry, and installation directory removed."

CONFIG_DIR="$(real_user_config_dir)"
STATE_DIR="$(real_user_state_dir)"
if [ -e "$CONFIG_DIR" ]; then
    if [ -w "$(dirname "$CONFIG_DIR")" ]; then
        rm -rf -- "$CONFIG_DIR"
    else
            sudo rm -rf -- "$CONFIG_DIR"
    fi
    log_ok "Configuration removed: $CONFIG_DIR"
fi
if [ -e "$STATE_DIR" ]; then
    if [ -w "$(dirname "$STATE_DIR")" ]; then
        rm -rf -- "$STATE_DIR"
    else
            sudo rm -rf -- "$STATE_DIR"
    fi
    log_ok "Application state removed: $STATE_DIR"
fi


AUTOSTART_FILE="$(dirname "$(real_user_config_dir)")/autostart/io.github.Anthodev.NagiShell.desktop"
rm_root_or_local "$AUTOSTART_FILE"

restore_notifications() {
    command -v busctl >/dev/null 2>&1 || {
        log_info "busctl unavailable; log out and back in so Plasma reclaims notifications."
        return 0
    }
    if run_as_real_user busctl --user call --json=short org.freedesktop.DBus /org/freedesktop/DBus \
            org.freedesktop.DBus.NameHasOwner s org.freedesktop.Notifications 2>/dev/null | grep -q true; then
        log_info "org.freedesktop.Notifications is owned by another service; leaving it untouched."
        return 0
    fi
    if ! run_as_real_user systemctl --user list-unit-files --no-legend plasma-plasmashell.service 2>/dev/null | grep -q plasma; then
        log_info "plasma-plasmashell.service not found; restart plasmashell or log out and back in to reclaim notifications."
        return 0
    fi
    local answer
    if [ "$ASSUME_YES" -eq 1 ]; then
        answer=y
    else
        printf 'Restart plasmashell now so it reclaims notifications? The desktop will blink. [Y/n]: '
        read -r answer
        case "${answer:-y}" in n|no) return 0 ;; esac
    fi
    run_as_real_user systemctl --user try-restart plasma-plasmashell.service &&
        log_ok "plasmashell restarted; Plasma owns notification delivery again." ||
        log_warn "plasmashell restart failed; log out and back in to reclaim notifications."
}
restore_notifications

echo
log_ok "Nagi Shell uninstalled."
