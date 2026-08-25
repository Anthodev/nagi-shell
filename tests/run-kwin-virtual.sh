#!/usr/bin/env bash
set -uo pipefail

usage() {
    cat <<'EOF'
Usage:
  run-kwin-virtual.sh [options] -- <command> [args...]

Options:
  --scale VALUE       Run one scale (default: 1).
  --matrix            Run the standard scale matrix: 1, 1.25, 1.5, 2.
  --outputs COUNT     Number of virtual outputs (default: 1).
  --width PIXELS      Virtual output width (default: 1280).
  --height PIXELS     Virtual output height (default: 720).
  --keep-on-failure   Preserve the private environment after a failed run.
  -h, --help          Show this help.
EOF
}

fail() {
    printf 'run-kwin-virtual: %s\n' "$*" >&2
    exit 2
}

require_value() {
    (($# >= 2)) || fail "$1 requires a value"
}

scale="1"
matrix=false
outputs="1"
width="1280"
height="720"
keep_on_failure=false
command_args=()

while (($# > 0)); do
    case "$1" in
    --scale)
        require_value "$@"
        scale="$2"
        shift 2
        ;;
    --matrix)
        matrix=true
        shift
        ;;
    --outputs)
        require_value "$@"
        outputs="$2"
        shift 2
        ;;
    --width)
        require_value "$@"
        width="$2"
        shift 2
        ;;
    --height)
        require_value "$@"
        height="$2"
        shift 2
        ;;
    --keep-on-failure)
        keep_on_failure=true
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    --)
        shift
        command_args=("$@")
        break
        ;;
    *)
        fail "unknown option: $1"
        ;;
    esac
done

((${#command_args[@]} > 0)) || fail "a command is required after --"
[[ "$outputs" =~ ^[1-9][0-9]*$ ]] || fail "--outputs must be a positive integer"
[[ "$width" =~ ^[1-9][0-9]*$ ]] || fail "--width must be a positive integer"
[[ "$height" =~ ^[1-9][0-9]*$ ]] || fail "--height must be a positive integer"
[[ "$scale" =~ ^([1-9][0-9]*(\.[0-9]+)?|0\.[0-9]*[1-9][0-9]*)$ ]] \
    || fail "--scale must be a positive number"

for binary in kwin_wayland dbus-run-session setsid mktemp; do
    command -v "$binary" >/dev/null || fail "required binary is unavailable: $binary"
done

kwin_binary="$(command -v kwin_wayland)"
dbus_binary="$(command -v dbus-run-session)"
setsid_binary="$(command -v setsid)"
base="$(mktemp -d "${TMPDIR:-/tmp}/nagi-kwin-virtual.XXXXXX")"
active_pid=""

remove_private_state() {
    local attempt
    for attempt in {1..40}; do
        if rm -rf -- "$base" 2>/dev/null && [[ ! -e "$base" ]]; then
            return 0
        fi
        sleep 0.05
    done
    return 1
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM

    if [[ -n "$active_pid" ]] && kill -0 "$active_pid" 2>/dev/null; then
        kill -TERM -- "-$active_pid" 2>/dev/null || true
        wait "$active_pid" 2>/dev/null || true
    fi

    if ((status != 0)) && $keep_on_failure; then
        printf 'run-kwin-virtual: preserved failed environment: %s\n' "$base" >&2
    elif ! remove_private_state; then
        printf 'run-kwin-virtual: failed to remove private environment: %s\n' "$base" >&2
        ((status == 0)) && status=1
    fi

    exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

write_session_launcher() {
    local launcher=$1
    {
        printf '#!/usr/bin/env bash\nset -euo pipefail\nexec'
        printf ' %q' "${command_args[@]}"
        printf '\n'
    } >"$launcher"
    chmod 0700 "$launcher"
}

run_one() {
    local current_scale=$1
    local label=${current_scale//./_}
    local root="$base/scale-$label"
    local runtime="$root/runtime"
    local launcher="$root/session-command"
    local status

    mkdir -p "$root/config" "$root/state" "$root/cache" "$root/data" "$root/home" "$runtime"
    chmod 0700 "$runtime"
    write_session_launcher "$launcher"

    printf 'run-kwin-virtual: scale=%s outputs=%s geometry=%sx%s root=%s\n' \
        "$current_scale" "$outputs" "$width" "$height" "$root"

    "$setsid_binary" /usr/bin/env \
        -u WAYLAND_DISPLAY \
        -u DISPLAY \
        -u DBUS_SESSION_BUS_ADDRESS \
        -u SSH_AUTH_SOCK \
        HOME="$root/home" \
        XDG_CONFIG_HOME="$root/config" \
        XDG_STATE_HOME="$root/state" \
        XDG_CACHE_HOME="$root/cache" \
        XDG_DATA_HOME="$root/data" \
        XDG_CONFIG_DIRS="/etc/xdg" \
        XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" \
        XDG_RUNTIME_DIR="$runtime" \
        XDG_SESSION_TYPE="wayland" \
        QT_QPA_PLATFORM="wayland" \
        QSG_RENDER_LOOP="${QSG_RENDER_LOOP:-basic}" \
        GTK_USE_PORTAL="0" \
        "$dbus_binary" -- \
        "$kwin_binary" \
        --virtual \
        --width "$width" \
        --height "$height" \
        --scale "$current_scale" \
        --output-count "$outputs" \
        --no-lockscreen \
        --no-global-shortcuts \
        --exit-with-session "$launcher" &
    active_pid=$!

    wait "$active_pid"
    status=$?
    active_pid=""

    if ((status != 0)); then
        printf 'run-kwin-virtual: scale %s failed with exit %s\n' \
            "$current_scale" "$status" >&2
    fi
    return "$status"
}

if $matrix; then
    scales=("1" "1.25" "1.5" "2")
else
    scales=("$scale")
fi

result=0
for current_scale in "${scales[@]}"; do
    run_one "$current_scale"
    status=$?
    if ((status != 0)) && ((result == 0)); then
        result=$status
    fi
done

exit "$result"
