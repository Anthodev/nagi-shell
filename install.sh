#!/usr/bin/env bash
# =============================================================================
#   Nagi Shell - installer
#
#   Installs the checked-out configuration and its native helpers into a
#   system or user location, registers the "Nagi Shell" section with
#   KGlobalAccel so it appears in KDE shortcut settings immediately, creates
#   a private default settings.conf for the invoking user, and installs launcher files.
#
#   Works on any distribution running a KDE Plasma 6 Wayland session. Package
#   installation adapts to the detected distribution family; unmapped cases
#   receive manual instructions instead of guessed package names.
#
#   Idempotent: safe to re-run. Never overwrites settings.conf or legacy theme.conf.
# =============================================================================
set -euo pipefail

COMPONENT_ID="io.github.Anthodev.NagiShell"
QS_MIN_VERSION="0.3.0"
DEFAULT_DEST="/usr/share/nagi-shell"
QUICKSHELL_DOCS="https://quickshell.org/docs/v0.3.0/guide/install-setup"

DEST="$DEFAULT_DEST"
ASSUME_YES=0
SKIP_PACKAGES=0
SKIP_SHORTCUTS=0
AUTOSTART=1

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
  -y, --yes            Assume yes; do not ask for confirmation
      --dest DIR       Installation directory (default: $DEFAULT_DEST)
      --skip-packages  Never propose installing missing dependencies
      --skip-shortcuts Do not pre-register the KDE shortcut section
      --no-autostart   Do not register the launcher for session autostart
  -h, --help           Show this help

The script verifies prerequisites, offers to install anything missing,
builds the native helpers in this checkout, copies the shell tree into
--dest, generates a launcher wrapper and desktop entry, pre-registers the
"Nagi Shell" section in KDE keyboard settings, and creates a private default
~/.config/nagi-shell/settings.conf for the invoking user. Existing V2 settings
or legacy theme.conf are preserved for runtime migration.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --dest) [ $# -ge 2 ] || log_fatal "--dest requires a value"; DEST="$2"; shift ;;
        --skip-packages) SKIP_PACKAGES=1 ;;
        --skip-shortcuts) SKIP_SHORTCUTS=1 ;;
        --no-autostart) AUTOSTART=0 ;;
        -h|--help) usage; exit 0 ;;
        *) log_fatal "Unknown option: $1 (see --help)" ;;
    esac
    shift
done

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- environment gates --------------------------------------------------------

[ "$(uname -s)" = "Linux" ] || log_fatal "Linux is required."

case "${XDG_SESSION_TYPE:-}" in
    wayland) ;;
    "")
        [ -n "${WAYLAND_DISPLAY:-}" ] || log_fatal \
            "XDG_SESSION_TYPE is unset and WAYLAND_DISPLAY is not visible. Run this from your Plasma Wayland session."
        log_warn "XDG_SESSION_TYPE is unset; proceeding because WAYLAND_DISPLAY is visible."
        ;;
    *) log_fatal "A KDE Plasma Wayland session is required (current session type: ${XDG_SESSION_TYPE})." ;;
esac

case ",${XDG_CURRENT_DESKTOP:-}," in
    *,*KDE*,*) ;;
    *)
        [ -n "${KDE_FULL_SESSION:-}" ] || log_fatal \
            "No KDE Plasma session detected (XDG_CURRENT_DESKTOP='${XDG_CURRENT_DESKTOP:-unset}'). Start a Plasma Wayland session first."
        ;;
esac

[ -f "$SOURCE_DIR/shell.qml" ] && [ -f "$SOURCE_DIR/Makefile" ] &&
    [ -d "$SOURCE_DIR/src/global-shortcut" ] || log_fatal \
    "Run this script from a nagi-shell checkout (shell.qml, Makefile, and src/global-shortcut are required)."

# Single-writer guard.
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/nagi-shell-install.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || log_fatal "Another nagi-shell install is already running."

# --- privilege helpers --------------------------------------------------------

RUN_ROOT_PREFIX=()
if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 || log_fatal "root privileges are required and sudo is unavailable."
fi

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo -n "$@"
    fi
}

# Filesystem mutation helper: runs directly when the target is already
# writable, otherwise escalates through sudo (ticket normally cached below).
priv() {
    local target="$1"
    shift
    local probe="$target"
    while [ ! -e "$probe" ]; do
        probe="$(dirname "$probe")"
    done
    if [ "$(id -u)" -eq 0 ] || [ -w "$probe" ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Acquire a sudo ticket up front when the destination lives outside the
# invoking user's writable space, so later steps never stall on a prompt mid-run.
require_write_access() {
    [ "$(id -u)" -eq 0 ] && return 0
    local dir="$1"
    while [ ! -d "$dir" ]; do
        dir="$(dirname "$dir")"
    done
    if [ ! -w "$dir" ]; then
        log_info "Writing outside your home requires privileges; requesting sudo."
        sudo -v
    fi
}
require_write_access "$DEST"

# Resolve the human account even when running under sudo, so user-level
# configuration lands in the invoking user's home, never in /root.
REAL_USER="${SUDO_USER:-$(id -un)}"
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
else
    REAL_HOME="${HOME}"
fi
real_user_config_home() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        printf '%s/.config' "$REAL_HOME"
    else
        printf '%s' "${XDG_CONFIG_HOME:-$REAL_HOME/.config}"
    fi
}
real_user_state_home() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        printf '%s/.local/state' "$REAL_HOME"
    else
        printf '%s' "${XDG_STATE_HOME:-$REAL_HOME/.local/state}"
    fi
}
run_as_real_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        local uid bus
        uid="$(id -u "$REAL_USER")"
        bus="/run/user/$uid/bus"
        runuser -u "$REAL_USER" -- env \
            HOME="$REAL_HOME" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
            XDG_RUNTIME_DIR="/run/user/$uid" \
            "$@"
    else
        "$@"
    fi
}

# --- distribution family ------------------------------------------------------

detect_family() {
    local id="" id_like=""
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id="${ID:-}"
        id_like="${ID_LIKE:-}"
    fi
    case "$id" in
        arch|cachyos|endeavouros|manjaro|artix) echo arch; return ;;
        fedora|nobara|rhel|centos|almalinux|rocky|bazzite) echo fedora; return ;;
        debian|ubuntu|pop|mint|kali|zorin|elementary|deepin|devuan|raspbian) echo debian; return ;;
        opensuse-leap|opensuse-tumbleweed|sles) echo suse; return ;;
    esac
    case " $id_like " in
        *" arch "*) echo arch; return ;;
        *" fedora "*|*" rhel "*) echo fedora; return ;;
        *" debian "*|*" ubuntu "*) echo debian; return ;;
        *" suse "*) echo suse; return ;;
    esac
    if command -v pacman >/dev/null 2>&1; then echo arch
    elif command -v dnf >/dev/null 2>&1; then echo fedora
    elif command -v apt-get >/dev/null 2>&1; then echo debian
    elif command -v zypper >/dev/null 2>&1; then echo suse
    else echo unknown
    fi
}
FAMILY="$(detect_family)"

# --- prerequisite scan --------------------------------------------------------

MISSING_CMDS=""
MISSING_PKGS=""
# Both probes always return 0; absence is recorded in the globals so the
# surrounding set -e context never treats "tool present" as a failure.
note_missing_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        return 0
    fi
    MISSING_CMDS="$MISSING_CMDS $1"
}
note_missing_module() {
    if pkg-config --exists "$1" 2>/dev/null; then
        return 0
    fi
    MISSING_PKGS="$MISSING_PKGS $1"
}

QS_VERSION_OK=0
if command -v qs >/dev/null 2>&1; then
    qs_version="$(qs --version 2>/dev/null | sed -n 's/^Quickshell \([0-9][0-9.]*\).*/\1/p')"
    if [ -n "$qs_version" ]; then
        oldest="$(printf '%s\n%s\n' "$qs_version" "$QS_MIN_VERSION" | sort -V | head -n1)"
        [ "$oldest" = "$QS_MIN_VERSION" ] && QS_VERSION_OK=1
        if [ "$QS_VERSION_OK" -eq 0 ]; then
            log_warn "Quickshell $qs_version found but >= $QS_MIN_VERSION is required."
            MISSING_PKGS="$MISSING_PKGS quickshell"
        fi
    else
        MISSING_PKGS="$MISSING_PKGS quickshell"
    fi
else
    MISSING_PKGS="$MISSING_PKGS quickshell"
fi
for cmd in c++ cmake make pkg-config qtpaths6; do
    note_missing_cmd "$cmd"
done
for module in Qt6Core Qt6DBus Qt6Gui Qt6Widgets Qt6Qml libpipewire-0.3 gio-unix-2.0; do
    note_missing_module "$module"
done

FONT_OK=0
if command -v fc-match >/dev/null 2>&1; then
    [ "$(fc-match --format='%{family}' Inter 2>/dev/null)" = "Inter" ] && FONT_OK=1
fi

# Map missing pieces onto the detected distribution's package names.
family_packages() {
    case "$FAMILY" in
        arch)
            # Quickshell is in the official repositories; headers ship inside
            # the single Arch framework packages; qtpaths6/moc live under
            # /usr/lib/qt6/bin and are located below.
            printf 'base-devel cmake pkgconf qt6-base qt6-declarative kglobalaccel pipewire glib2'
            ;;
        fedora)
            printf 'gcc-c++ make pkgconf-pkg-config cmake qt6-qtbase-devel qt6-qtdeclarative-devel kf6-kglobalaccel-devel pipewire-devel glib2-devel'
            ;;
        debian)
            printf 'build-essential cmake pkg-config qt6-base-dev qt6-declarative-dev libkf6globalaccel-dev libpipewire-0.3-dev libglib2.0-dev'
            ;;
        suse)
            printf 'gcc-c++ make pkg-config cmake'
            ;;
    esac
}

needs_anything=0
[ -n "$(printf '%s %s' "$MISSING_CMDS" "$MISSING_PKGS" | tr -d ' ')" ] && needs_anything=1
if [ "$QS_VERSION_OK" -eq 0 ]; then needs_anything=1; fi

if [ "$needs_anything" -eq 1 ] && [ "$SKIP_PACKAGES" -eq 0 ]; then
    echo
    echo "Missing components:$MISSING_CMDS$MISSING_PKGS"
    case "$FAMILY" in
        arch|fedora|debian)
            pkgs="$(family_packages)"
            echo
            echo "The following distribution packages provide them ($FAMILY family):"
            echo "  $pkgs"
            case "$FAMILY:$MISSING_PKGS" in
                *:*quickshell*)
                    case "$FAMILY" in
                        fedora)
                            echo "  Quickshell comes from the COPR repository:"
                            echo "    sudo dnf copr enable errornointernet/quickshell"
                            echo "    sudo dnf install quickshell   (stable channel; never quickshell-git)"
                            ;;
                        debian)
                            echo "  Quickshell is packaged in Debian unstable/testing:"
                            echo "    sudo apt install quickshell"
                            echo "  On Ubuntu, enable the upstream PPA instead:"
                            echo "    sudo add-apt-repository ppa:avengemedia/danklinux && sudo apt update"
                            echo "    sudo apt install quickshell"
                            ;;
                        arch)
                            echo "  Quickshell is in the official repositories: pacman -S quickshell"
                            ;;
                    esac
                    ;;
            esac
            printf 'Install these packages now? [y/N]: '
            read -r answer
            case "${answer:-n}" in
                y|yes)
                    if [ "$(id -u)" -ne 0 ]; then
                        sudo -v
                    fi
                    case "$FAMILY" in
                        arch)
                            # shellcheck disable=SC2086
                            as_root pacman -Sy --needed --noconfirm $pkgs
                            ;;
                        fedora)
                            if printf '%s' "$MISSING_PKGS" | grep -qw quickshell; then
                                as_root dnf copr enable -y errornointernet/quickshell
                            fi
                            # shellcheck disable=SC2086
                            as_root dnf install -y $pkgs $(printf '%s' "$MISSING_PKGS" | tr ' ' '\n' | grep -x quickshell || true)
                            ;;
                        debian)
                            as_root apt-get update
                            # shellcheck disable=SC2086
                            as_root apt-get install -y $pkgs $(printf '%s' "$MISSING_PKGS" | tr ' ' '\n' | grep -x quickshell || true)
                            ;;
                    esac
                    log_ok "Package installation finished."
                    ;;
                *)
                    log_fatal "Aborted at user request. Install the packages above and re-run."
                    ;;
            esac
            ;;
        suse)
            echo
            echo "openSUSE: Quickshell is available from the OBS project"
            echo "  home:AvengeMedia:danklinux (see $QUICKSHELL_DOCS)."
            echo "Development tools to install manually (verify names with 'zypper se'):"
            echo "  $(family_packages) plus Qt6/KGlobalAccel/PipeWire/GLib development packages"
            echo "  such as qt6-base-devel qt6-declarative-devel kf6-kglobalaccel-devel pipewire-devel glib2-devel"
            log_fatal "Install the requirements above and re-run this script."
            ;;
        *)
            echo
            echo "Unrecognized distribution family. Install manually:"
            echo "  1. Quickshell >= $QS_MIN_VERSION - per-distro instructions: $QUICKSHELL_DOCS"
            echo "  2. A C++20 toolchain, cmake, make, pkg-config"
            echo "  3. Development packages for Qt6 (Core, DBus, Gui, Widgets, Qml),"
            echo "     PipeWire, GIO/GLib, and KF6 GlobalAccel"
            log_fatal "Install the requirements above and re-run this script."
            ;;
    esac
elif [ "$needs_anything" -eq 1 ]; then
    log_fatal "Missing:$MISSING_CMDS$MISSING_PKGS (re-run without --skip-packages to resolve)."
fi

# Re-verify the hard requirements after any installation attempt.
for cmd in c++ cmake make pkg-config qtpaths6 qs; do
    command -v "$cmd" >/dev/null 2>&1 ||
        log_fatal "'$cmd' is still missing after dependency handling."
done
pkg-config --exists Qt6Core Qt6DBus Qt6Gui Qt6Widgets Qt6Qml libpipewire-0.3 gio-unix-2.0 ||
    log_fatal "Qt6/PipeWire/GIO development modules are still incomplete (see pkg-config output)."

if [ "$FONT_OK" -eq 0 ]; then
    log_warn "Inter font not found through Fontconfig. The UI falls back to another family; install your distribution's Inter package for the intended look (rsms-inter-fonts on Fedora, inter-font on Arch, fonts-inter on Debian)."
fi

# Locate Qt host tools on distributions that do not put them on PATH.
QT_TOOL_PATH_FIX=""
if ! command -v qtpaths6 >/dev/null 2>&1; then
    for candidate in /usr/lib/qt6/bin /usr/lib64/qt6/bin /usr/lib/x86_64-linux-gnu/qt6/bin; do
        if [ -x "$candidate/qtpaths6" ]; then
            QT_TOOL_PATH_FIX="$candidate"
            break
        fi
    done
    [ -n "$QT_TOOL_PATH_FIX" ] || log_fatal "qtpaths6 was not found on PATH or in common Qt6 tool directories."
    log_info "Using Qt host tools from $QT_TOOL_PATH_FIX"
fi

# --- confirmation -------------------------------------------------------------

echo
echo "About to install Nagi Shell:"
echo "  destination       : $DEST"
echo "  launcher          : generated 'nagi-shell' wrapper on PATH"
echo "  desktop entry     : share/applications/io.github.Anthodev.NagiShell.desktop"
echo "  KDE shortcuts     : 'Nagi Shell' section registered in KGlobalAccel$([ "$SKIP_SHORTCUTS" -eq 1 ] && echo ' (skipped)')"
echo "  default config    : $(real_user_config_home)/nagi-shell/settings.conf (created only if no V2 or legacy config exists)"
echo "  notifications     : the wrapper hands org.freedesktop.Notifications from"
echo "                      plasmashell to Nagi while it runs; Plasma regains it on its next restart."
echo "  autostart         : launcher registered for session startup$([ "$AUTOSTART" -eq 0 ] && echo ' (skipped)')"
if [ "$(id -u)" -ne 0 ]; then
    echo "  privilege prompts : sudo will be used for '$DEST' and any approved packages"
fi
echo
if [ "$ASSUME_YES" -eq 0 ]; then
    printf 'Proceed with installation? [y/N]: '
    read -r answer
    case "${answer:-n}" in
        y|yes) ;;
        *) log_fatal "Installation aborted." ;;
    esac
fi

# --- build --------------------------------------------------------------------

log_info "Building native helpers in the checkout..."
(
    cd "$SOURCE_DIR"
    if [ -n "$QT_TOOL_PATH_FIX" ]; then
        PATH="$QT_TOOL_PATH_FIX:$PATH"
        export PATH
    fi
    # shellcheck disable=SC2086
    make -s helper audio-helper connectivity-helper brightness-helper \
        session-helper application-helper settings-helper global-shortcut-helper \
        wallpaper-helper notification-plugin platform-plugin
)

# Required artifacts, relative to the checkout root (paths mirror what
# shell.qml resolves through Quickshell.shellPath("build/...")).
ARTIFACTS="
build/nagi-kwin-virtual-desktops
build/nagi-pipewire-audio
build/nagi-brightness
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
"
for artifact in $ARTIFACTS; do
    [ -f "$SOURCE_DIR/$artifact" ] || log_fatal "Expected artifact is missing after build: $artifact"
done
log_ok "Native helpers built."

# --- install tree ---------------------------------------------------------------

STOP_OUTPUT=""
if [ -d "$DEST" ]; then
    STOP_OUTPUT="$(qs kill -p "$DEST" 2>&1 || true)"
    [ -n "$STOP_OUTPUT" ] && log_info "Stopped the previously installed instance."
fi

install_dir() {
    priv "$1" mkdir -p "$1"
    priv "$1" cp -a "$2/." "$1/"
}
log_info "Copying shell tree to $DEST ..."
priv "$DEST" mkdir -p "$DEST"
for item in shell.qml qml assets; do
    if [ -d "$SOURCE_DIR/$item" ]; then
        priv "$DEST" rm -rf "$DEST/$item"
        install_dir "$DEST/$item" "$SOURCE_DIR/$item"
    else
        priv "$DEST" cp -f "$SOURCE_DIR/$item" "$DEST/$item"
    fi
done
for artifact in $ARTIFACTS; do
    priv "$DEST" mkdir -p "$DEST/$(dirname "$artifact")"
    priv "$DEST" cp -f "$SOURCE_DIR/$artifact" "$DEST/$artifact"
    priv "$DEST" chmod 0755 "$DEST/$artifact"
done
log_ok "Shell tree installed."

# --- launcher wrapper -----------------------------------------------------------

case "$DEST" in
    /usr/*|/opt/*|/bin/*|/sbin/*) BIN_DIR="/usr/local/bin" ;;
    *) BIN_DIR="${XDG_BIN_HOME:-${XDG_DATA_HOME:-$REAL_HOME/.local/share}/../bin}"
       BIN_DIR="${BIN_DIR%/bin}/bin"
       [ "$BIN_DIR" = "/bin" ] && BIN_DIR="$REAL_HOME/.local/bin"
       ;;
esac
priv "$BIN_DIR" mkdir -p "$BIN_DIR"
BIN_DIR="$(cd "$BIN_DIR" && pwd)"
BIN_PATH="$BIN_DIR/nagi-shell"
priv "$BIN_PATH" tee "$BIN_PATH" >/dev/null <<WRAPPER
#!/bin/sh
# Nagi Shell launcher - generated by install.sh; safe to edit NAGI_DEST only.
NAGI_DEST="$DEST"

# Notification priority: Quickshell claims org.freedesktop.Notifications with a
# plain registerService (no ReplaceExisting flag), so an existing owner such as
# plasmashell keeps the name forever. A transient RequestName with
# REPLACE_EXISTING (2) | DO_NOT_QUEUE (4) forces the current owner to lose the
# name, and the short-lived caller releases it immediately; Quickshell's own
# service watcher then acquires the freed name while starting up below.
notif_owner="\$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \\
    org.freedesktop.DBus.GetNameOwner s org.freedesktop.Notifications 2>/dev/null || true)"
if [ -n "\$notif_owner" ]; then
    busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \\
        org.freedesktop.DBus.RequestName su org.freedesktop.Notifications 6 >/dev/null 2>&1 || true
fi

QML_IMPORT_PATH="\$NAGI_DEST/build/qml"
export QML_IMPORT_PATH
exec qs -p "\$NAGI_DEST" --no-duplicate "\$@"
WRAPPER
priv "$BIN_PATH" chmod 0755 "$BIN_PATH"
log_ok "Launcher wrapper installed at $BIN_PATH."

# --- desktop entry ---------------------------------------------------------------

SHARE_DIR="${DEST%/nagi-shell}"
APPLICATIONS_DIR="$SHARE_DIR/applications"
DESKTOP_SRC="$SOURCE_DIR/packaging/io.github.Anthodev.NagiShell.desktop"
[ -f "$DESKTOP_SRC" ] || log_fatal "packaging/io.github.Anthodev.NagiShell.desktop is missing from the checkout."
priv "$APPLICATIONS_DIR" mkdir -p "$APPLICATIONS_DIR"
sed "s|^Exec=.*|Exec=$BIN_PATH|" "$DESKTOP_SRC" > "$SOURCE_DIR/.nagi-desktop-entry.tmp"
priv "$APPLICATIONS_DIR/io.github.Anthodev.NagiShell.desktop" \
    mv "$SOURCE_DIR/.nagi-desktop-entry.tmp" "$APPLICATIONS_DIR/io.github.Anthodev.NagiShell.desktop"
if command -v update-desktop-database >/dev/null 2>&1; then
    priv "$APPLICATIONS_DIR" update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
fi
log_ok "Desktop entry installed at $APPLICATIONS_DIR/io.github.Anthodev.NagiShell.desktop."

# --- default user configuration ----------------------------------------------------

CONFIG_DIR="$(real_user_config_home)/nagi-shell"
CONFIG_FILE="$CONFIG_DIR/settings.conf"
LEGACY_CONFIG_FILE="$CONFIG_DIR/theme.conf"
SETTINGS_TEMPLATE="$SOURCE_DIR/packaging/settings.conf"
[ -f "$SETTINGS_TEMPLATE" ] || log_fatal "packaging/settings.conf is missing from the checkout."
if run_as_real_user test -e "$CONFIG_FILE" || run_as_real_user test -L "$CONFIG_FILE"; then
    log_info "Existing settings kept: $CONFIG_FILE"
elif run_as_real_user test -e "$LEGACY_CONFIG_FILE" || run_as_real_user test -L "$LEGACY_CONFIG_FILE"; then
    log_info "Legacy configuration kept for safe runtime migration: $LEGACY_CONFIG_FILE"
else
    run_as_real_user mkdir -p "$CONFIG_DIR"
    SETTINGS_BYTES="$(wc -c < "$SETTINGS_TEMPLATE")"
    if run_as_real_user "$SOURCE_DIR/build/nagi-settings" create "$CONFIG_DIR" "$SETTINGS_BYTES" \
        < "$SETTINGS_TEMPLATE"; then
        log_ok "Private default settings created at $CONFIG_FILE."
    elif run_as_real_user test -f "$CONFIG_FILE"; then
        log_info "A concurrently created settings file was kept: $CONFIG_FILE"
    else
        log_fatal "Default settings could not be created safely at $CONFIG_FILE."
    fi
fi

# --- KDE shortcut section -------------------------------------------------------------

SHORTCUT_HELPER="$DEST/build/global-shortcut/nagi-global-shortcut"
if [ "$SKIP_SHORTCUTS" -eq 1 ]; then
    log_info "Skipping shortcut registration (--skip-shortcuts). The section appears at first launch."
else
    log_info "Registering the 'Nagi Shell' section with KGlobalAccel..."
    set +e
    run_as_real_user timeout --signal=TERM 3 "$SHORTCUT_HELPER" </dev/null >/dev/null 2>&1
    rc=$?
    set -e
    case "$rc" in
        0|124)
            log_ok "Shortcut section registered. Manage bindings under System Settings -> Keyboard -> Shortcuts -> Nagi Shell."
            ;;
        3)
            log_info "An instance already owns the shortcut registration; section is present."
            ;;
        *)
            log_warn "Registration exited with status $rc; the section will appear at first launch instead."
            ;;
    esac
fi

# --- done -------------------------------------------------------------------------------

echo
log_ok "Nagi Shell installed."
echo "  Launch it from the application menu ('Nagi Shell'), by running: $BIN_PATH"
echo "  Or directly: qs -p $DEST --no-duplicate"
echo "  Session startup   : handled by the installed autostart entry$([ "$AUTOSTART" -eq 0 ] && echo ' (disabled; add it via System Settings -> Autostart)')"

if [ "$AUTOSTART" -eq 1 ]; then
    AUTOSTART_DIR="$(real_user_config_home)/autostart"
    AUTOSTART_FILE="$AUTOSTART_DIR/io.github.Anthodev.NagiShell.desktop"
    priv "$AUTOSTART_FILE" mkdir -p "$AUTOSTART_DIR"
    sed "s|^Exec=.*|Exec=$BIN_PATH|" "$DESKTOP_SRC" > "$SOURCE_DIR/.nagi-autostart.tmp"
    priv "$AUTOSTART_FILE" mv "$SOURCE_DIR/.nagi-autostart.tmp" "$AUTOSTART_FILE"
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        as_root chown -R "$REAL_USER:" "$AUTOSTART_DIR"
    fi
    log_ok "Session autostart registered at $AUTOSTART_FILE."
else
    log_info "Autostart not registered (--no-autostart). Start Nagi from the menu when wanted."
fi
