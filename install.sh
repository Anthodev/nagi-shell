#!/usr/bin/env bash
# =============================================================================
#   Nagi Shell - installer
#
#   Installs the checked-out configuration and its native helpers into a
#   system or user location, registers the "Nagi Shell" section with
#   KGlobalAccel, creates a private default settings.conf for the invoking user,
#   installs the desktop launcher, and enables an ordered per-user systemd
#   service for the next login.
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
  -h, --help           Show this help

The script verifies prerequisites, offers to install anything missing,
builds the native helpers in this checkout, copies the shell tree into
--dest, generates a launcher wrapper and desktop entry, pre-registers the
"Nagi Shell" section in KDE keyboard settings, creates a private default
~/.config/nagi-shell/settings.conf for the invoking user, and enables its
per-user service for the next Plasma Wayland login. Existing V2 settings or
legacy theme.conf are preserved for runtime migration.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --dest) [ $# -ge 2 ] || log_fatal "--dest requires a value"; DEST="$2"; shift ;;
        --skip-packages) SKIP_PACKAGES=1 ;;
        --skip-shortcuts) SKIP_SHORTCUTS=1 ;;
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
# configuration lands in the invoking user's home, never in /root. The target
# user's XDG roots follow the same rule: explicit values passed through sudo
# win; when sudo strips them, the roots are recovered from the target user's
# systemd manager environment (the unit search path that manager really
# uses); otherwise the target user's home defaults apply — exactly as in an
# unprivileged run.
REAL_USER="${SUDO_USER:-$(id -un)}"
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
else
    REAL_HOME="${HOME}"
fi
real_user_config_home() {
    printf '%s' "${XDG_CONFIG_HOME:-${SUDO_MANAGER_CONFIG_HOME:-$REAL_HOME/.config}}"
}
real_user_state_home() {
    printf '%s' "${XDG_STATE_HOME:-${SUDO_MANAGER_STATE_HOME:-$REAL_HOME/.local/state}}"
}
run_as_real_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        local uid bus
        uid="$(id -u "$REAL_USER")"
        bus="/run/user/$uid/bus"
        runuser -u "$REAL_USER" -- env \
            HOME="$REAL_HOME" \
            XDG_CONFIG_HOME="$(real_user_config_home)" \
            XDG_STATE_HOME="$(real_user_state_home)" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
            XDG_RUNTIME_DIR="/run/user/$uid" \
            "$@"
    else
        "$@"
    fi
}

# Sudo normally strips XDG_CONFIG_HOME/XDG_STATE_HOME. When it does, ask the
# target user's manager to launch printenv so the manager's decoded values cross
# the privilege boundary as data, never as shell source. This is best-effort;
# the manager gate below still hard-fails when the user manager is unavailable.
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

USER_CONFIG_HOME="$(real_user_config_home)"
SYSTEMD_USER_DIR="$USER_CONFIG_HOME/systemd/user"
UNIT_FILE="$SYSTEMD_USER_DIR/nagi-shell.service"
LEGACY_AUTOSTART_FILE="$USER_CONFIG_HOME/autostart/io.github.Anthodev.NagiShell.desktop"

command -v systemctl >/dev/null 2>&1 ||
    log_fatal "systemctl is required to install the Nagi user service."
command -v timeout >/dev/null 2>&1 ||
    log_fatal "timeout is required to verify and control the Nagi user service."
if ! run_as_real_user timeout --signal=TERM 5 systemctl --user show-environment \
        >/dev/null 2>&1; then
    log_fatal "The per-user systemd manager is unavailable. Install from the logged-in Plasma user session; no autostart fallback is supported."
fi

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
MISSING_FONTS=""
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
# A missing Inter font is a prerequisite like any other: it joins
# MISSING_FONTS so the prompt below proposes the distribution package
# instead of only warning after the fact.
if [ "$FONT_OK" -eq 0 ]; then
    MISSING_FONTS=" inter"
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

# Inter package names verified for the mapped families; every other family
# receives manual instructions instead of a guessed package name.
font_package() {
    case "$FAMILY" in
        fedora) printf 'rsms-inter-fonts' ;;
        arch)   printf 'inter-font' ;;
        debian) printf 'fonts-inter' ;;
    esac
}

needs_anything=0
[ -n "$(printf '%s %s %s' "$MISSING_CMDS" "$MISSING_PKGS" "$MISSING_FONTS" | tr -d ' ')" ] && needs_anything=1
if [ "$QS_VERSION_OK" -eq 0 ]; then needs_anything=1; fi

if [ "$needs_anything" -eq 1 ] && [ "$SKIP_PACKAGES" -eq 0 ]; then
    echo
    echo "Missing components:$MISSING_CMDS$MISSING_PKGS$MISSING_FONTS"
    case "$FAMILY" in
        arch|fedora|debian)
            pkgs="$(family_packages)"
            if [ -n "$MISSING_FONTS" ]; then
                pkgs="$pkgs $(font_package)"
            fi
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
            if [ -n "$MISSING_FONTS" ]; then
                echo "Also install an Inter font package (no verified openSUSE package"
                echo "  name is recorded here; search with 'zypper se inter')."
            fi
            log_fatal "Install the requirements above and re-run this script."
            ;;
        *)
            echo
            echo "Unrecognized distribution family. Install manually:"
            echo "  1. Quickshell >= $QS_MIN_VERSION - per-distro instructions: $QUICKSHELL_DOCS"
            echo "  2. A C++20 toolchain, cmake, make, pkg-config"
            echo "  3. Development packages for Qt6 (Core, DBus, Gui, Widgets, Qml),"
            echo "     PipeWire, GIO/GLib, and KF6 GlobalAccel"
            if [ -n "$MISSING_FONTS" ]; then
                echo "  4. The Inter font family - install your distribution's Inter package"
            fi
            log_fatal "Install the requirements above and re-run this script."
            ;;
    esac
elif [ "$needs_anything" -eq 1 ]; then
    log_fatal "Missing:$MISSING_CMDS$MISSING_PKGS$MISSING_FONTS (re-run without --skip-packages to resolve)."
fi

# Re-verify the hard requirements after any installation attempt.
for cmd in c++ cmake make pkg-config qtpaths6 qs; do
    command -v "$cmd" >/dev/null 2>&1 ||
        log_fatal "'$cmd' is still missing after dependency handling."
done
pkg-config --exists Qt6Core Qt6DBus Qt6Gui Qt6Widgets Qt6Qml libpipewire-0.3 gio-unix-2.0 ||
    log_fatal "Qt6/PipeWire/GIO development modules are still incomplete (see pkg-config output)."

# Re-check the font after any installation attempt, mirroring the command
# re-verification above; keep the warning as the last-resort fallback for
# fontconfig setups the probe cannot confirm.
if [ "$FONT_OK" -eq 0 ] && command -v fc-match >/dev/null 2>&1; then
    [ "$(fc-match --format='%{family}' Inter 2>/dev/null)" = "Inter" ] && FONT_OK=1
fi
if [ "$FONT_OK" -eq 0 ]; then
    log_warn "Inter font still not found through Fontconfig. The UI falls back to another family; install your distribution's Inter package for the intended look (rsms-inter-fonts on Fedora, inter-font on Arch, fonts-inter on Debian)."
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
echo "  default config    : $USER_CONFIG_HOME/nagi-shell/settings.conf (created only if no V2 or legacy config exists)"
echo "  user service      : enabled; an active installed Nagi service is restarted"
echo "  notifications     : no inactive service is started in this session; active"
echo "                      Nagi upgrades resume after replacement; Plasma is untouched."
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
    make -s helper audio-helper easyeffects-status-helper connectivity-helper brightness-helper \
        gaming-performance-helper session-helper application-helper settings-helper \
        global-shortcut-helper \
        wallpaper-helper notification-plugin platform-plugin
)

# Required artifacts, relative to the checkout root (paths mirror what
# shell.qml resolves through Quickshell.shellPath("build/...")).
EXECUTABLE_ARTIFACTS="
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
"
DATA_ARTIFACTS="
build/nagi-kwin-workspace-consensus.js.in
"
for artifact in $EXECUTABLE_ARTIFACTS $DATA_ARTIFACTS; do
    [ -f "$SOURCE_DIR/$artifact" ] || log_fatal "Expected artifact is missing after build: $artifact"
done
log_ok "Native helpers built."

# --- install tree ---------------------------------------------------------------

INSTALL_WAS_UPGRADE=0
if [ -d "$DEST" ] || [ -e "$UNIT_FILE" ] || [ -L "$UNIT_FILE" ]; then
    INSTALL_WAS_UPGRADE=1
fi

SERVICE_WAS_ACTIVE=0
if [ -e "$UNIT_FILE" ] || [ -L "$UNIT_FILE" ]; then
    if run_as_real_user timeout --signal=TERM 5 \
            systemctl --user is-active --quiet nagi-shell.service; then
        SERVICE_WAS_ACTIVE=1
        log_info "Stopping the active Nagi user service for upgrade..."
        run_as_real_user timeout --signal=TERM 15 \
            systemctl --user stop nagi-shell.service ||
            log_fatal "Could not stop the active nagi-shell.service."
    else
        active_status=$?
        [ "$active_status" -ne 124 ] ||
            log_fatal "Timed out while checking whether nagi-shell.service is active."
        log_info "The installed Nagi user service is inactive; it will remain stopped until the next login."
    fi
fi

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
for artifact in $EXECUTABLE_ARTIFACTS; do
    priv "$DEST" mkdir -p "$DEST/$(dirname "$artifact")"
    priv "$DEST" cp -f "$SOURCE_DIR/$artifact" "$DEST/$artifact"
    priv "$DEST" chmod 0755 "$DEST/$artifact"
done
for artifact in $DATA_ARTIFACTS; do
    priv "$DEST" mkdir -p "$DEST/$(dirname "$artifact")"
    priv "$DEST" cp -f "$SOURCE_DIR/$artifact" "$DEST/$artifact"
    priv "$DEST" chmod 0644 "$DEST/$artifact"
done
log_ok "Shell tree installed."

escape_embedded_path() {
    local mode="$1"
    local value="$2"
    local result="" character index
    for ((index = 0; index < ${#value}; index += 1)); do
        character="${value:index:1}"
        case "$character" in
            \\) result+='\\' ;;
            '"') result+='\"' ;;
            '$')
                if [ "$mode" = "systemd" ]; then
                    # Hex quoting survives ExecStart expansion and decodes to a
                    # literal dollar in the executable path.
                    result+='\x24'
                else
                    result+='\$'
                fi
                ;;
            '`')
                if [ "$mode" = "systemd" ]; then
                    result+='`'
                else
                    result+='\`'
                fi
                ;;
            '%')
                if [ "$mode" = "shell" ]; then
                    result+='%'
                else
                    result+='%%'
                fi
                ;;
            $'\n'|$'\r')
                log_fatal "Installation paths must not contain line breaks."
                ;;
            *) result+="$character" ;;
        esac
    done
    printf '%s' "$result"
}

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
LAUNCHER_TEMPLATE="$SOURCE_DIR/packaging/nagi-shell.in"
[ -f "$LAUNCHER_TEMPLATE" ] || log_fatal "packaging/nagi-shell.in is missing from the checkout."
DEST_ESCAPED="$(escape_embedded_path shell "$DEST")"
LAUNCHER_TMP="$SOURCE_DIR/.nagi-launcher.tmp"
launcher_replacements=0
while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = 'NAGI_DEST="@NAGI_DEST@"' ]; then
        printf 'NAGI_DEST="%s"\n' "$DEST_ESCAPED"
        launcher_replacements=$((launcher_replacements + 1))
    else
        printf '%s\n' "$line"
    fi
done < "$LAUNCHER_TEMPLATE" > "$LAUNCHER_TMP"
[ "$launcher_replacements" -eq 1 ] ||
    log_fatal "packaging/nagi-shell.in has an invalid @NAGI_DEST@ contract."
priv "$BIN_PATH" mv "$LAUNCHER_TMP" "$BIN_PATH"
priv "$BIN_PATH" chmod 0755 "$BIN_PATH"
log_ok "Launcher wrapper installed at $BIN_PATH."

# --- desktop entry ---------------------------------------------------------------

SHARE_DIR="${DEST%/nagi-shell}"
APPLICATIONS_DIR="$SHARE_DIR/applications"
DESKTOP_SRC="$SOURCE_DIR/packaging/io.github.Anthodev.NagiShell.desktop"
[ -f "$DESKTOP_SRC" ] || log_fatal "packaging/io.github.Anthodev.NagiShell.desktop is missing from the checkout."
priv "$APPLICATIONS_DIR" mkdir -p "$APPLICATIONS_DIR"
DESKTOP_BIN_ESCAPED="$(escape_embedded_path desktop "$BIN_PATH")"
DESKTOP_TMP="$SOURCE_DIR/.nagi-desktop-entry.tmp"
desktop_replacements=0
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        Exec=*)
            printf 'Exec="%s" --control-center\n' "$DESKTOP_BIN_ESCAPED"
            desktop_replacements=$((desktop_replacements + 1))
            ;;
        *) printf '%s\n' "$line" ;;
    esac
done < "$DESKTOP_SRC" > "$DESKTOP_TMP"
[ "$desktop_replacements" -eq 1 ] ||
    log_fatal "The desktop template must contain exactly one Exec entry."
priv "$APPLICATIONS_DIR/io.github.Anthodev.NagiShell.desktop" \
    mv "$DESKTOP_TMP" "$APPLICATIONS_DIR/io.github.Anthodev.NagiShell.desktop"
if command -v update-desktop-database >/dev/null 2>&1; then
    priv "$APPLICATIONS_DIR" update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
fi
log_ok "Desktop entry installed at $APPLICATIONS_DIR/io.github.Anthodev.NagiShell.desktop."

# --- default user configuration ----------------------------------------------------

CONFIG_DIR="$USER_CONFIG_HOME/nagi-shell"
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

# --- ordered user service ------------------------------------------------------------

SERVICE_TEMPLATE="$SOURCE_DIR/packaging/nagi-shell.service.in"
[ -f "$SERVICE_TEMPLATE" ] ||
    log_fatal "packaging/nagi-shell.service.in is missing from the checkout."

if [ -e "$LEGACY_AUTOSTART_FILE" ] || [ -L "$LEGACY_AUTOSTART_FILE" ]; then
    if ! run_as_real_user rm -f -- "$LEGACY_AUTOSTART_FILE"; then
        priv "$LEGACY_AUTOSTART_FILE" rm -f -- "$LEGACY_AUTOSTART_FILE"
    fi
    log_info "Removed the legacy Nagi XDG autostart entry."
fi

run_as_real_user mkdir -p "$SYSTEMD_USER_DIR"
UNIT_TMP="$(run_as_real_user mktemp "$SYSTEMD_USER_DIR/.nagi-shell.service.XXXXXX")"
cleanup_unit_tmp() {
    if [ -n "${UNIT_TMP:-}" ]; then
        run_as_real_user rm -f -- "$UNIT_TMP" >/dev/null 2>&1 || true
    fi
}
trap cleanup_unit_tmp EXIT

SYSTEMD_BIN_ESCAPED="$(escape_embedded_path systemd "$BIN_PATH")"
unit_replacements=0
while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = 'ExecStart="@NAGI_BIN@" --session-service' ]; then
        printf 'ExecStart="%s" --session-service\n' "$SYSTEMD_BIN_ESCAPED"
        unit_replacements=$((unit_replacements + 1))
    else
        printf '%s\n' "$line"
    fi
done < "$SERVICE_TEMPLATE" > "$UNIT_TMP"
if [ "$unit_replacements" -ne 1 ]; then
    log_fatal "packaging/nagi-shell.service.in has an invalid @NAGI_BIN@ contract."
fi
run_as_real_user chmod 0644 "$UNIT_TMP"
run_as_real_user mv -f -- "$UNIT_TMP" "$UNIT_FILE"
UNIT_TMP=""
trap - EXIT

run_as_real_user timeout --signal=TERM 10 systemctl --user daemon-reload ||
    log_fatal "systemctl --user daemon-reload failed."
run_as_real_user timeout --signal=TERM 10 \
    systemctl --user enable nagi-shell.service ||
    log_fatal "Could not enable nagi-shell.service; no autostart fallback was installed."
if [ "$SERVICE_WAS_ACTIVE" -eq 1 ]; then
    run_as_real_user timeout --signal=TERM 40 \
        systemctl --user start nagi-shell.service ||
        log_fatal "The upgraded nagi-shell.service could not be restarted."
    log_ok "Restarted the previously active nagi-shell.service."
else
    log_ok "Enabled nagi-shell.service for the next Plasma Wayland login."
fi

# --- done -------------------------------------------------------------------------------

echo
if [ "$SERVICE_WAS_ACTIVE" -eq 1 ]; then
    log_ok "Nagi Shell upgraded and its active notification service was restored."
    echo "  plasmashell and every foreign notification owner were left untouched."
elif [ "$INSTALL_WAS_UPGRADE" -eq 1 ]; then
    log_ok "Nagi Shell upgraded with nagi-shell.service left inactive."
    echo "  No notification service was started; plasmashell and foreign owners were not contacted."
    echo "  Log out and back in to activate Nagi before plasmashell."
else
    log_ok "Nagi Shell installed without starting a notification service."
    echo "  The current notification owner was neither contacted nor changed."
    echo "  Log out and back in to start Nagi before plasmashell and activate notification delivery."
fi
printf '  Installed launcher: %q\n' "$BIN_PATH"
echo "  Open 'Nagi Control Center' from the application menu"
echo "  or run the installed launcher with --control-center."
