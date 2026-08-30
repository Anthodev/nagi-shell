#!/usr/bin/env bash
set -euo pipefail

export PYTHONDONTWRITEBYTECODE=1

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
budgets="$root/tests/stability/budgets.json"
sampler="$root/tests/stability/sample_process.py"
privacy_sweep="$root/tests/stability/privacy_sweep.py"
result_dir="$root/build/stability"
qs_bin="${QS:-qs}"
python_bin="${PYTHON:-python3}"

fail() {
    printf 'stability-performance: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: %s [--outputs 1|2|3|all]\n' "$0"
}

require_tools() {
    local tool
    for tool in "$qs_bin" "$python_bin" jq; do
        command -v "$tool" >/dev/null || fail "required tool is unavailable: $tool"
    done
    [[ -x "$root/build/nagi-settings" ]] || fail "build/nagi-settings is unavailable"
    [[ -x "$sampler" ]] || fail "sample_process.py is unavailable"
    [[ -x "$privacy_sweep" ]] || fail "privacy_sweep.py is unavailable"
    [[ -r "$budgets" ]] || fail "budgets.json is unavailable"
}

ipc_call() {
    "$qs_bin" -p "$root" ipc call nagi "$@" 2>>"$session_log"
}

snapshot() {
    local reply
    reply="$(ipc_call stabilitySnapshot)" || return 1
    printf '%s' "$reply"
}

snapshot_is_closed() {
    local expected_blur=$1
    jq -e --argjson outputs "$outputs" --arg expectedBlur "$expected_blur" \
        --slurpfile budget "$budgets" '
        ($budget[0]) as $b
        | keys == ["activeAdapterTimerCount", "appearanceRevision", "boundedCounts",
                   "configurationRevision", "connectivity", "controlCenter", "easyEffects",
                   "gpu", "islands", "media", "onboarding", "polkitDormant",
                   "processWideObjectIdentity", "resources", "wallpaper", "weatherSearch"]
        and (.islands | keys == ["count", "registryRevision"])
        and (.onboarding | keys == ["instantiatedWindowCount", "visible"])
        and (.controlCenter | keys == ["hiddenFocusLoopCount", "instantiatedWindowCount",
                                      "loadedPageCount", "pageAnimationCount",
                                      "pageInterestWorkCount", "pageOwnedActiveTimerCount",
                                      "pageOwnedWindowOrEffectCount", "resourceReleaseCount",
                                      "visible"])
        and (.wallpaper | keys == ["activeTimerCount", "pageInterest"])
        and (.connectivity | keys == ["activeTimerCount", "bluetoothManagerInterest",
                                     "wifiManagerInterest"])
        and (.weatherSearch | keys == ["allowed", "inFlight"])
        and (.media | keys == ["detailsVisible", "positionTimerRunning"])
        and (.easyEffects | keys == ["activeTimerCount", "interestCount", "interested"])
        and (.gpu | keys == ["extraProcessWideServiceEffectObjectCount",
                             "processWideServiceCount", "requestedKwinBlurRegionCount",
                             "shadowLayerCount", "visibleIslandCount"])
        and all(.gpu[]; type == "number" and floor == . and . >= 0)
        and (.resources | keys == ["applicationPins", "applicationRecency", "applications",
                                   "audioCandidates", "audioObjects", "bluetoothDevices",
                                   "brightnessDisplays", "controlCenterPages",
                                   "controlCenterWindows", "easyEffectsPresets", "islandSurfaces",
                                   "mediaPlayers", "notificationHistory", "notificationLive",
                                   "notificationPopups", "notificationRuntimePlugins",
                                   "notificationWatchers", "processWideServices", "trayItems",
                                   "trayTrackedItems",
                                   "virtualDesktops", "wallpaperApplyResults",
                                   "wallpaperDirectories", "wallpaperImages", "wallpaperPreview",
                                   "wallpaperScreens", "weatherDailyRows", "weatherHourlyRows",
                                   "weatherModels", "wifiNetworks"])
        and (.boundedCounts | keys == ["applicationPins", "applicationRecency",
                                      "bluetoothDevices", "brightnessDisplays",
                                      "easyEffectsPresets", "notificationHistory",
                                      "notificationLive", "trayTrackedItems",
                                      "wallpaperApplyResults", "wallpaperDirectories",
                                      "wallpaperImages", "wallpaperScreens", "weatherDailyRows",
                                      "weatherHourlyRows", "weatherModels", "wifiNetworks"])
        and (.configurationRevision | type == "number" and floor == . and . >= 0)
        and (.appearanceRevision | type == "number" and floor == . and . >= 0)
        and (.processWideObjectIdentity
             | type == "string" and test("^[0-9]+([.][0-9]+)*$"))
        and (.islands.count == $outputs)
        and (.islands.registryRevision | type == "number" and floor == . and . >= 0)
        and .onboarding.visible == false
        and .onboarding.instantiatedWindowCount == 1
        and .controlCenter.visible == false
        and .controlCenter.instantiatedWindowCount
            == $b.gpuStructural.closedControlCenterPageOwnedWindowsOrEffects
        and .controlCenter.loadedPageCount == $b.closedControlCenter.loadedPages
        and .controlCenter.pageInterestWorkCount == $b.closedControlCenter.pageInterestWork
        and .controlCenter.pageOwnedActiveTimerCount
            == $b.closedControlCenter.pageOwnedActiveTimers
        and .controlCenter.pageAnimationCount == $b.closedControlCenter.pageAnimations
        and .controlCenter.hiddenFocusLoopCount == $b.closedControlCenter.hiddenFocusLoops
        and .controlCenter.pageOwnedWindowOrEffectCount
            == $b.gpuStructural.closedControlCenterPageOwnedWindowsOrEffects
        and (.controlCenter.resourceReleaseCount
             | type == "number" and floor == . and . >= 0)
        and .wallpaper.pageInterest == false
        and .wallpaper.activeTimerCount == 0
        and .connectivity.wifiManagerInterest == false
        and .connectivity.bluetoothManagerInterest == false
        and .connectivity.activeTimerCount == 0
        and .weatherSearch.allowed == false
        and .weatherSearch.inFlight == false
        and .media.detailsVisible == false
        and .media.positionTimerRunning == false
        and .easyEffects.interested == false
        and .easyEffects.interestCount == $b.closedControlCenter.easyEffectsInterest
        and .easyEffects.activeTimerCount == 0
        and .activeAdapterTimerCount == $b.closedControlCenter.pageOwnedActiveTimers
        and all(.resources[]; type == "number" and floor == . and . >= 0)
        and (.resources.controlCenterWindows
             == $b.gpuStructural.closedControlCenterPageOwnedWindowsOrEffects)
        and (.resources.controlCenterPages == $b.closedControlCenter.loadedPages)
        and (.resources.notificationRuntimePlugins
             == $b.live.inProcessNotificationPluginCount)
        and all(.boundedCounts[];
                keys == ["count", "maximum"]
                and (.count | type == "number" and floor == . and . >= 0)
                and (.maximum | type == "number" and floor == . and . >= 0)
                and .count <= .maximum)
        and .gpu.visibleIslandCount == $outputs
        and .gpu.shadowLayerCount == .gpu.visibleIslandCount
        and .gpu.shadowLayerCount
            <= .gpu.visibleIslandCount * $b.gpuStructural.shadowLayersPerVisibleIslandMax
        and .gpu.requestedKwinBlurRegionCount
            <= .gpu.visibleIslandCount
               * $b.gpuStructural.requestedKwinBlurRegionsPerVisibleIslandMax
        and (($expectedBlur == "true"
              and .gpu.requestedKwinBlurRegionCount == .gpu.visibleIslandCount)
             or ($expectedBlur == "false" and .gpu.requestedKwinBlurRegionCount == 0)
             or $expectedBlur == "any")
        and .gpu.processWideServiceCount == .resources.processWideServices
        and .gpu.extraProcessWideServiceEffectObjectCount
            <= .gpu.processWideServiceCount
               * $b.gpuStructural.extraGpuOrEffectObjectsPerProcessWideService
        and .polkitDormant == true
    ' >/dev/null
}

wait_for_closed() {
    local expected_blur=$1 deadline=$((SECONDS + 30)) value last_value=""
    while ((SECONDS < deadline)); do
        if value="$(snapshot 2>/dev/null)"; then
            last_value=$value
            if printf '%s' "$value" | snapshot_is_closed "$expected_blur"; then
                printf '%s' "$value"
                return 0
            fi
        fi
        sleep 0.1
    done
    if [[ -n "$last_value" ]]; then
        printf '%s\n' "$last_value" \
            >"$result_dir/performance-${outputs}-closed-failure.json"
    fi
    return 1
}

wait_for_open() {
    local deadline=$((SECONDS + 15)) value
    while ((SECONDS < deadline)); do
        if value="$(snapshot 2>/dev/null)" \
                && printf '%s' "$value" | jq -e \
                    '.controlCenter.visible == true and .controlCenter.loadedPageCount == 1' \
                    >/dev/null; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

wait_for_revision() {
    local field=$1 previous=$2 expected_blur=$3
    local deadline=$((SECONDS + 15)) value current
    while ((SECONDS < deadline)); do
        if value="$(snapshot 2>/dev/null)"; then
            current="$(jq -er --arg field "$field" '.[$field]' <<<"$value")" || current=-1
            if [[ "$current" =~ ^[0-9]+$ ]] && ((current > previous)) \
                    && printf '%s' "$value" | snapshot_is_closed "$expected_blur"; then
                printf '%s' "$value"
                return 0
            fi
        fi
        sleep 0.1
    done
    return 1
}

write_setting_variant() {
    local key=$1 value=$2
    local config="$XDG_CONFIG_HOME/nagi-shell/settings.conf"
    local next="$XDG_RUNTIME_DIR/nagi-stability-settings.new" byte_count
    [[ -f "$config" ]] || fail "canonical settings were not created"
    "$python_bin" -B - "$config" "$next" "$key" "$value" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
key = sys.argv[3]
value = sys.argv[4]
data = source.read_bytes()
if len(data) > 32768:
    raise SystemExit("settings payload exceeds the production bound")
text = data.decode("utf-8")
pattern = re.compile(rf"^{re.escape(key)}=.*$", re.MULTILINE)
if len(pattern.findall(text)) != 1:
    raise SystemExit(f"settings key is missing or duplicated: {key}")
updated = pattern.sub(f"{key}={value}", text)
target.write_bytes(updated.encode("utf-8"))
target.chmod(0o600)
PY
    byte_count="$(wc -c <"$next")"
    "$root/build/nagi-settings" write "$XDG_CONFIG_HOME/nagi-shell" "$byte_count" \
        <"$next" >/dev/null
    rm -f -- "$next"
}

write_system_appearance_variant() {
    local next="$XDG_CONFIG_HOME/kdeglobals.new"
    cat >"$next" <<'EOF'
[General]
ColorScheme=BreezeDark
AccentColor=91,111,245

[KDE]
AnimationDurationFactor=0
EOF
    chmod 0600 "$next"
    mv -f -- "$next" "$XDG_CONFIG_HOME/kdeglobals"
}

observe_renderer() {
    local deadline=$((SECONDS + 15)) renderer
    while ((SECONDS < deadline)); do
        renderer="$({ "$python_bin" -B - "$session_log" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
try:
    data = path.read_bytes()
except OSError:
    raise SystemExit(1)
if len(data) > 4 * 1024 * 1024:
    raise SystemExit("renderer log exceeds bound")
text = data.decode("utf-8", errors="strict")
pattern = re.compile(
    r"qt[.]rhi[.]general: OpenGL VENDOR: .+? RENDERER: (.+?) VERSION: "
)
renderers = []
for line in text.splitlines():
    match = pattern.search(line)
    if match is None:
        continue
    raw = match.group(1).strip()
    lowered = raw.lower()
    for token in (
        "llvmpipe",
        "softpipe",
        "radeonsi",
        "zink",
        "virgl",
        "nouveau",
        "iris",
        "crocus",
        "nvidia",
    ):
        if token in lowered:
            renderers.append(token)
            break
    else:
        normalized = re.sub(r"[^a-z0-9._ -]", "", lowered).strip()
        if not normalized or len(normalized) > 96:
            raise SystemExit("unbounded renderer identity")
        renderers.append(f"other:{normalized}")
if not renderers or len(set(renderers)) != 1:
    raise SystemExit(1)
print(renderers[0])
PY
        } 2>>"$session_log")" && {
            printf '%s' "$renderer"
            return 0
        }
        sleep 0.1
    done
    return 1
}

fingerprint_matches() {
    local renderer=$1 output=$2
    local arch cpu distro plasma kwin quickshell
    arch="$(uname -m)"
    cpu="$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | sed -n '1p')"
    distro="$(. /etc/os-release && printf '%s %s' "${NAME:-}" "${VERSION_ID:-}")"
    plasma="$(plasmashell --version 2>/dev/null | sed -n 's/.* \([0-9][0-9.]*\)$/\1/p')"
    kwin="$(kwin_wayland --version 2>/dev/null | sed -n 's/.* \([0-9][0-9.]*\)$/\1/p')"
    quickshell="$($qs_bin --version 2>/dev/null | sed -n 's/^Quickshell \([0-9][0-9.]*\).*/\1/p')"
    "$python_bin" -B - "$budgets" "$output" "$arch" "$cpu" "$distro" "$plasma" \
        "$kwin" "$quickshell" "$renderer" <<'PY'
import json
import pathlib
import sys

budget_path = pathlib.Path(sys.argv[1])
output_path = pathlib.Path(sys.argv[2])
with budget_path.open(encoding="utf-8") as handle:
    expected = json.load(handle)["baseline"]["fingerprint"]
actual = dict(zip(
    ("architecture", "cpu", "distribution", "plasma", "kwin", "quickshell", "isolatedRenderer"),
    sys.argv[3:],
))
result = {"schemaVersion": 1, "actual": actual, "match": actual == expected}
output_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
raise SystemExit(0 if result["match"] else 1)
PY
}

runtime_identity() {
    "$python_bin" -B - "$shell_pid" <<'PY'
import json
import os
import pathlib
import sys

def process_identity(process_id):
    process = pathlib.Path("/proc") / str(process_id)
    stat = (process / "stat").read_text(encoding="utf-8").strip()
    close = stat.rfind(")")
    fields = stat[close + 2:].split()
    if close < 0 or len(fields) < 20:
        raise SystemExit("malformed process identity")
    return [int(process_id), int(fields[19])]


pid = int(sys.argv[1])
proc = pathlib.Path("/proc") / str(pid)
children = (proc / "task" / str(pid) / "children").read_text(encoding="utf-8").split()
rows = []
for token in children:
    name = os.path.basename(os.readlink(pathlib.Path("/proc") / token / "exe"))
    rows.append([name, *process_identity(token)])
print(json.dumps({"root": process_identity(pid), "helpers": sorted(rows)}, separators=(",", ":")))
PY
}

wait_for_runtime_identity() {
    local expected=$1 deadline=$((SECONDS + 15)) value
    while ((SECONDS < deadline)); do
        if value="$(runtime_identity 2>/dev/null)" && [[ "$value" == "$expected" ]]; then
            printf '%s' "$value"
            return 0
        fi
        sleep 0.1
    done
    return 1
}

cache_census() {
    local output=$1
    "$python_bin" -B - "$XDG_CACHE_HOME" "$output" <<'PY'
import hashlib
import json
import os
import pathlib
import stat
import sys

root = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
if not root.is_dir():
    raise SystemExit("private cache root is unavailable")
selected = []
selected_directories = []
wallpaper_files = 0
wallpaper_bytes = 0
weather_files = 0
for current, directories, files in os.walk(root, followlinks=False):
    directories.sort()
    files.sort()
    current_path = pathlib.Path(current)
    for name in directories:
        path = current_path / name
        if path.is_symlink():
            raise SystemExit("private cache contains a symlink")
        relative = path.relative_to(root).as_posix()
        if relative == "nagi-shell" or relative == "nagi-shell/wallpaper-v1" \
                or relative.startswith("nagi-shell/wallpaper-v1/"):
            selected_directories.append(relative)
    for name in files:
        path = current_path / name
        status = path.lstat()
        if not stat.S_ISREG(status.st_mode):
            raise SystemExit("private cache contains a non-regular file")
        relative = path.relative_to(root).as_posix()
        wallpaper = relative.startswith("nagi-shell/wallpaper-v1/")
        weather = name == "weather.json"
        if not wallpaper and not weather:
            continue
        if status.st_size > 64 * 1024 * 1024:
            raise SystemExit("bounded cache file exceeds scan limit")
        selected.append((relative, status.st_size, path))
        if wallpaper:
            wallpaper_files += 1
            wallpaper_bytes += status.st_size
        if weather:
            weather_files += 1
if len(selected) > 513 or len(selected_directories) > 514:
    raise SystemExit("bounded cache entry census exceeds limit")
digest = hashlib.sha256()
for relative in sorted(selected_directories):
    digest.update(b"D\0")
    digest.update(relative.encode("utf-8"))
    digest.update(b"\0")
total_bytes = 0
for relative, size, path in sorted(selected):
    digest.update(relative.encode("utf-8"))
    digest.update(b"\0")
    digest.update(str(size).encode("ascii"))
    digest.update(b"\0")
    data = path.read_bytes()
    if len(data) != size:
        raise SystemExit("bounded cache changed during census")
    total_bytes += size
    digest.update(data)
result = {
    "schemaVersion": 1,
    "directoryCount": len(selected_directories),
    "fileCount": len(selected),
    "totalBytes": total_bytes,
    "identityDigest": digest.hexdigest(),
    "wallpaperDiskEntries": wallpaper_files,
    "wallpaperDiskBytes": wallpaper_bytes,
    "weatherCacheFiles": weather_files,
    "withinExistingLimits": wallpaper_files <= 512
                            and wallpaper_bytes <= 64 * 1024 * 1024
                            and weather_files <= 1,
}
output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

run_sample() {
    local label=$1 duration=$2 mode=$3
    local output="$result_dir/performance-${outputs}-${label}.json"
    local -a args=(
        "$sampler"
        --pid "$shell_pid"
        --duration "$duration"
        --display-count "$outputs"
        --budgets "$budgets"
        --output "$output"
    )
    [[ "$fingerprint_match" == true ]] && args+=(--fingerprint-match)
    [[ "$mode" == structural ]] && args+=(--structural-only)
    "$python_bin" -B "${args[@]}"
}

write_variant_evidence() {
    local label=$1 baseline_snapshot=$2 current_snapshot=$3 baseline_identity=$4
    local current_identity=$5 expected_blur=$6 output=$7
    "$python_bin" -B - "$label" "$baseline_snapshot" "$current_snapshot" \
        "$baseline_identity" "$current_identity" "$expected_blur" "$output" <<'PY'
import json
import pathlib
import sys

label = sys.argv[1]
baseline = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
current = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
baseline_identity = json.loads(sys.argv[4])
current_identity = json.loads(sys.argv[5])
expected_blur = sys.argv[6]
output = pathlib.Path(sys.argv[7])
checks = {
    "rootIdentityStable": current_identity["root"] == baseline_identity["root"],
    "helperIdentityStable": current_identity["helpers"] == baseline_identity["helpers"],
    "registryRevisionStable": current["islands"]["registryRevision"]
                              == baseline["islands"]["registryRevision"],
    "resourceCountsStable": current["resources"] == baseline["resources"],
    "processWideObjectIdentityStable": current["processWideObjectIdentity"]
                                       == baseline["processWideObjectIdentity"],
    "surfaceCountStable": current["islands"]["count"] == baseline["islands"]["count"],
    "shadowCountExact": current["gpu"]["shadowLayerCount"]
                        == current["gpu"]["visibleIslandCount"],
    "blurCountExact": current["gpu"]["requestedKwinBlurRegionCount"]
                      == (current["gpu"]["visibleIslandCount"] if expected_blur == "true" else 0),
}
failures = [f"{label}: {name}" for name, passed in checks.items() if not passed]
result = {
    "schemaVersion": 1,
    "label": label,
    "checks": checks,
    "structuralStatus": "failed" if failures else "passed",
    "failures": failures,
    "configurationRevision": current["configurationRevision"],
    "appearanceRevision": current["appearanceRevision"],
}
output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
if failures:
    raise SystemExit("; ".join(failures))
PY
}

evaluate_soak() {
    local initial_snapshot=$1 final_snapshot=$2 initial_sample=$3 final_sample=$4
    local initial_cache=$5 final_cache=$6 initial_identity=$7 final_identity=$8 output=$9
    "$python_bin" -B - "$budgets" "$initial_snapshot" "$final_snapshot" "$initial_sample" \
        "$final_sample" "$initial_cache" "$final_cache" "$initial_identity" "$final_identity" \
        "$output" <<'PY'
import json
import pathlib
import sys

paths = [pathlib.Path(value) for value in sys.argv[1:8]]
budget, initial_snapshot, final_snapshot, initial_sample, final_sample, initial_cache, final_cache = [
    json.loads(path.read_text(encoding="utf-8")) for path in paths
]
initial_identity = json.loads(sys.argv[8])
final_identity = json.loads(sys.argv[9])
output = pathlib.Path(sys.argv[10])
soak = budget["soak"]
initial_rss = initial_sample["metrics"]["quickshellRssMedianKiB"]
final_rss = final_sample["metrics"]["quickshellRssMedianKiB"]
allowance = max(
    initial_rss * soak["finalSettledRssGrowthPercentMax"] / 100.0,
    soak["finalSettledRssGrowthKiBMax"],
)
growth = final_rss - initial_rss
checks = {
    "rootIdentityExact": initial_identity["root"] == final_identity["root"],
    "helperIdentityExact": initial_identity["helpers"] == final_identity["helpers"],
    "registryRevisionExact": initial_snapshot["islands"]["registryRevision"]
                             == final_snapshot["islands"]["registryRevision"],
    "objectModelCountsExact": initial_snapshot["resources"] == final_snapshot["resources"],
    "processWideObjectIdentityExact": initial_snapshot["processWideObjectIdentity"]
                                      == final_snapshot["processWideObjectIdentity"],
    "configurationRevisionExact": initial_snapshot["configurationRevision"]
                                  == final_snapshot["configurationRevision"],
    "appearanceRevisionExact": initial_snapshot["appearanceRevision"]
                               == final_snapshot["appearanceRevision"],
    "cacheIdentityAndCountsExact": initial_cache == final_cache,
    "cacheBoundsPreserved": initial_cache["withinExistingLimits"]
                            and final_cache["withinExistingLimits"],
    "initialHelperIdle": initial_sample["structuralStatus"] == "passed",
    "finalHelperIdle": final_sample["structuralStatus"] == "passed",
    "unusedQmlResourcesReleased":
        final_snapshot["controlCenter"]["resourceReleaseCount"]
        > initial_snapshot["controlCenter"]["resourceReleaseCount"],
    "settledRssGrowthWithinBudget": growth <= allowance,
}
failures = [name for name, passed in checks.items() if not passed]
result = {
    "schemaVersion": 1,
    "checks": checks,
    "initialSettledRssMedianKiB": initial_rss,
    "finalSettledRssMedianKiB": final_rss,
    "rssGrowthKiB": growth,
    "rssGrowthAllowanceKiB": allowance,
    "initialResources": initial_snapshot["resources"],
    "finalResources": final_snapshot["resources"],
    "initialCache": initial_cache,
    "finalCache": final_cache,
    "structuralStatus": "failed" if failures else "passed",
    "failures": failures,
}
output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
if failures:
    raise SystemExit("; ".join(failures))
PY
}

build_summary() {
    local output=$1 renderer=$2 fingerprint_file=$3 soak_file=$4 enabled_sample=$5
    local disabled_sample=$6
    shift 6
    "$python_bin" -B - "$output" "$renderer" "$fingerprint_file" "$soak_file" \
        "$enabled_sample" "$disabled_sample" "$@" <<'PY'
import json
import pathlib
import sys

output = pathlib.Path(sys.argv[1])
renderer = sys.argv[2]
fingerprint = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
soak = json.loads(pathlib.Path(sys.argv[4]).read_text(encoding="utf-8"))
samples = [json.loads(pathlib.Path(path).read_text(encoding="utf-8")) for path in sys.argv[5:7]]
variants = [json.loads(pathlib.Path(path).read_text(encoding="utf-8")) for path in sys.argv[7:]]
required_variants = {
    "system-source", "scheme", "accent", "motion", "radius", "opacity",
    "blur-enabled", "blur-disabled",
}
structural_failures = list(soak["failures"])
for sample in samples:
    if sample["structuralStatus"] != "passed":
        structural_failures.extend(sample["failures"])
for variant in variants:
    if variant["structuralStatus"] != "passed":
        structural_failures.extend(variant["failures"])
labels = {variant["label"] for variant in variants}
if labels != required_variants or len(variants) != len(required_variants):
    structural_failures.append("appearance/blur variant set is incomplete or duplicated")
numeric_failures = []
for sample in samples:
    if sample["numericStatus"] == "failed":
        numeric_failures.extend(sample["failures"])
if any(sample["numericStatus"] == "passed" for sample in samples):
    numeric_status = "passed" if all(sample["numericStatus"] == "passed" for sample in samples) else "failed"
else:
    numeric_status = "skipped"
failures = structural_failures + numeric_failures
helper_names = sorted(row["name"] for row in samples[0]["helpers"])
result = {
    "schemaVersion": 1,
    "displayCount": samples[0]["displayCount"],
    "observedRenderer": renderer,
    "fingerprintMatch": fingerprint["match"],
    "numericStatus": numeric_status,
    "structuralStatus": "failed" if structural_failures else "passed",
    "samples": [
        {
            "blur": "enabled" if index == 0 else "disabled",
            "numericStatus": sample["numericStatus"],
            "structuralStatus": sample["structuralStatus"],
            "metrics": sample["metrics"],
        }
        for index, sample in enumerate(samples)
    ],
    "helperNames": helper_names,
    "helperCount": len(helper_names),
    "resourceCounts": soak["finalResources"],
    "soak": {
        "checks": soak["checks"],
        "initialSettledRssMedianKiB": soak["initialSettledRssMedianKiB"],
        "finalSettledRssMedianKiB": soak["finalSettledRssMedianKiB"],
        "rssGrowthKiB": soak["rssGrowthKiB"],
        "rssGrowthAllowanceKiB": soak["rssGrowthAllowanceKiB"],
    },
    "variants": [{"label": row["label"], "checks": row["checks"]} for row in variants],
    "failures": failures,
}
output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
if failures:
    raise SystemExit("; ".join(failures))
PY
}

exercise_control_center_routes() {
    local cycles=$1 phase=$2
    local compact cycle route reply

    for compact in false true; do
        [[ "$(ipc_call stabilitySetControlCenterCompact "$compact")" == true ]] \
            || fail "$phase responsive mode selection was rejected"
        for ((cycle = 1; cycle <= cycles; cycle += 1)); do
            for route in "${routes[@]}"; do
                reply="$(ipc_call activate "$route")" || fail "$phase route activation failed: $route"
                [[ "$reply" == true ]] || fail "$phase route activation was rejected: $route"
                wait_for_open || fail "$phase route did not load exactly one page: $route"
                [[ "$(ipc_call stabilityCloseControlCenter)" == true ]] \
                    || fail "$phase Control Center close was rejected"
                wait_for_closed false >/dev/null \
                    || fail "$phase route retained hidden work after close: $route"
            done
        done
    done
}

run_inner() {
    outputs=$1
    session_log="$result_dir/performance-${outputs}.log"
    local deadline ready=0 initial_snapshot post_soak_snapshot current_snapshot
    local initial_identity post_soak_identity current_identity previous_revision soak_cycles sample_seconds
    local initial_snapshot_file="$result_dir/performance-${outputs}-initial-snapshot.json"
    local post_soak_snapshot_file="$result_dir/performance-${outputs}-post-soak-snapshot.json"
    local initial_cache_file="$result_dir/performance-${outputs}-initial-cache.json"
    local post_soak_cache_file="$result_dir/performance-${outputs}-post-soak-cache.json"
    local initial_sample_file="$result_dir/performance-${outputs}-initial-census.json"
    local post_soak_sample_file="$result_dir/performance-${outputs}-post-soak-census.json"
    local soak_file="$result_dir/performance-${outputs}-soak.json"
    local fingerprint_file="$result_dir/performance-${outputs}-fingerprint.json"
    local baseline_snapshot_file
    local -a routes=(control-center island appearance clock-date media weather notifications wifi bluetooth wallpaper displays about)
    local -a child_pids=() variant_files=()

    mkdir -p "$result_dir"
    : >"$session_log"
    export NAGI_STABILITY_PROBE=1
    export QML_IMPORT_PATH="$root/build/qml"
    export QSG_INFO=1
    export QT_LOGGING_RULES="qt.scenegraph.general=true;qt.rhi.general=true"
    mkdir -p "$XDG_STATE_HOME/nagi-shell"
    printf 'dismissed=1\n' >"$XDG_STATE_HOME/nagi-shell/onboarding.state"
    chmod 0600 "$XDG_STATE_HOME/nagi-shell/onboarding.state"

    "$qs_bin" -p "$root" --no-duplicate >"$session_log" 2>&1 &
    shell_pid=$!
    cleanup_inner() {
        local status=$?
        trap - EXIT INT TERM
        if [[ -r "/proc/$shell_pid/task/$shell_pid/children" ]]; then
            read -r -a child_pids <"/proc/$shell_pid/task/$shell_pid/children" || true
        fi
        "$qs_bin" kill -p "$root" >/dev/null 2>&1 || true
        if kill -0 "$shell_pid" 2>/dev/null; then
            kill -TERM "$shell_pid" 2>/dev/null || true
        fi
        wait "$shell_pid" 2>/dev/null || true
        local attempt child all_gone
        for attempt in {1..100}; do
            all_gone=true
            for child in "${child_pids[@]}"; do
                if [[ -e "/proc/$child" ]]; then
                    all_gone=false
                    break
                fi
            done
            $all_gone && break
            sleep 0.05
        done
        for child in "${child_pids[@]}"; do
            if [[ -e "/proc/$child" ]]; then
                printf 'stability-performance: residual direct helper after cleanup\n' >&2
                status=1
            fi
        done
        exit "$status"
    }
    trap cleanup_inner EXIT INT TERM

    deadline=$((SECONDS + 60))
    while ((SECONDS < deadline)); do
        if grep -q 'Configuration Loaded' "$session_log" 2>/dev/null; then
            ready=1
            break
        fi
        kill -0 "$shell_pid" 2>/dev/null || break
        sleep 0.1
    done
    ((ready == 1)) || fail "production shell did not report Configuration Loaded"

    observed_renderer="$(observe_renderer)" \
        || fail "the Quickshell render context did not report an observable renderer"
    [[ "$observed_renderer" == llvmpipe ]] \
        || [[ "${NAGI_ENFORCE_PERFORMANCE:-0}" != 1 ]] \
        || fail "forced certification requires observed llvmpipe rendering"
    if fingerprint_matches "$observed_renderer" "$fingerprint_file"; then
        fingerprint_match=true
    else
        fingerprint_match=false
        [[ "${NAGI_ENFORCE_PERFORMANCE:-0}" != 1 ]] \
            || fail "NAGI_ENFORCE_PERFORMANCE=1 requires the exact frozen fingerprint"
    fi

    initial_snapshot="$(wait_for_closed false)" || fail "initial closed snapshot retained hidden work"
    if [[ "${NAGI_STABILITY_EXTENDED:-0}" == 1 ]]; then
        soak_cycles="$(jq -er '.soak.extendedCycles | select(type == "number" and floor == . and . > 0)' "$budgets")"
        sample_seconds="$(jq -er '.baseline.sampleSeconds.isolatedExtended | select(type == "number" and . > 0)' "$budgets")"
    else
        soak_cycles="$(jq -er '.soak.cycles | select(type == "number" and floor == . and . > 0)' "$budgets")"
        sample_seconds="$(jq -er '.baseline.sampleSeconds.isolated | select(type == "number" and . > 0)' "$budgets")"
    fi

    exercise_control_center_routes 1 warm-up
    sleep "$(jq -r '.baseline.settleSeconds' "$budgets")"
    initial_snapshot="$(wait_for_closed false)" || fail "warmed settled snapshot retained hidden work"
    jq -e '.controlCenter.resourceReleaseCount >= 1' <<<"$initial_snapshot" >/dev/null \
        || fail "warm-up did not release unused QML resources before the initial census"
    printf '%s\n' "$initial_snapshot" >"$initial_snapshot_file"
    initial_identity="$(runtime_identity)" || fail "initial process identity census failed"
    cache_census "$initial_cache_file"
    run_sample initial-census 1 structural

    exercise_control_center_routes "$soak_cycles" soak
    [[ "$(ipc_call activate unknown-stability-route)" == false ]] \
        || fail "unknown route was accepted"

    sleep "$(jq -r '.baseline.settleSeconds' "$budgets")"
    post_soak_snapshot="$(wait_for_closed false)" \
        || fail "post-soak settled snapshot retained hidden work"
    printf '%s\n' "$post_soak_snapshot" >"$post_soak_snapshot_file"
    post_soak_identity="$(runtime_identity)" || fail "post-soak process identity census failed"
    cache_census "$post_soak_cache_file"
    run_sample post-soak-census 1 structural
    evaluate_soak "$initial_snapshot_file" "$post_soak_snapshot_file" "$initial_sample_file" \
        "$post_soak_sample_file" "$initial_cache_file" "$post_soak_cache_file" \
        "$initial_identity" "$post_soak_identity" "$soak_file" \
        || fail "soak counts, identities, caches, helper idle state, or RSS growth violated budget"
    baseline_snapshot_file=$post_soak_snapshot_file

    previous_revision="$(jq -r '.appearanceRevision' "$baseline_snapshot_file")"
    write_system_appearance_variant
    current_snapshot="$(wait_for_revision appearanceRevision "$previous_revision" false)" \
        || fail "system appearance replacement was not observed"
    printf '%s\n' "$current_snapshot" >"$result_dir/performance-${outputs}-variant-system-source-snapshot.json"
    current_identity="$(wait_for_runtime_identity "$post_soak_identity")" \
        || fail "system appearance replacement changed process/helper identity"
    variant_files+=("$result_dir/performance-${outputs}-variant-system-source.json")
    write_variant_evidence system-source "$baseline_snapshot_file" \
        "$result_dir/performance-${outputs}-variant-system-source-snapshot.json" \
        "$post_soak_identity" "$current_identity" false "${variant_files[-1]}"

    local label key value
    for label in scheme accent motion radius opacity; do
        case "$label" in
        scheme) key=scheme; value=system ;;
        accent) key=accent_mode; value=system ;;
        motion) key=motion; value=minimal ;;
        radius) key=outer_radius; value=28 ;;
        opacity) key=surface_opacity; value=0.89 ;;
        esac
        previous_revision="$(jq -r '.configurationRevision' <<<"$current_snapshot")"
        write_setting_variant "$key" "$value"
        current_snapshot="$(wait_for_revision configurationRevision "$previous_revision" false)" \
            || fail "$label settings replacement was not observed"
        printf '%s\n' "$current_snapshot" \
            >"$result_dir/performance-${outputs}-variant-${label}-snapshot.json"
        current_identity="$(wait_for_runtime_identity "$post_soak_identity")" \
            || fail "$label replacement changed process/helper identity"
        variant_files+=("$result_dir/performance-${outputs}-variant-${label}.json")
        write_variant_evidence "$label" "$baseline_snapshot_file" \
            "$result_dir/performance-${outputs}-variant-${label}-snapshot.json" \
            "$post_soak_identity" "$current_identity" false "${variant_files[-1]}"
    done

    previous_revision="$(jq -r '.configurationRevision' <<<"$current_snapshot")"
    write_setting_variant blur_enabled true
    current_snapshot="$(wait_for_revision configurationRevision "$previous_revision" true)" \
        || fail "blur-enabled settings replacement was not observed"
    printf '%s\n' "$current_snapshot" \
        >"$result_dir/performance-${outputs}-variant-blur-enabled-snapshot.json"
    current_identity="$(wait_for_runtime_identity "$post_soak_identity")" \
        || fail "blur-enabled replacement changed process/helper identity"
    variant_files+=("$result_dir/performance-${outputs}-variant-blur-enabled.json")
    write_variant_evidence blur-enabled "$baseline_snapshot_file" \
        "$result_dir/performance-${outputs}-variant-blur-enabled-snapshot.json" \
        "$post_soak_identity" "$current_identity" true "${variant_files[-1]}"
    sleep "$(jq -r '.baseline.settleSeconds' "$budgets")"
    run_sample blur-enabled "$sample_seconds" performance

    previous_revision="$(jq -r '.configurationRevision' <<<"$current_snapshot")"
    write_setting_variant blur_enabled false
    current_snapshot="$(wait_for_revision configurationRevision "$previous_revision" false)" \
        || fail "blur-disabled settings replacement was not observed"
    printf '%s\n' "$current_snapshot" \
        >"$result_dir/performance-${outputs}-variant-blur-disabled-snapshot.json"
    current_identity="$(wait_for_runtime_identity "$post_soak_identity")" \
        || fail "blur-disabled replacement changed process/helper identity"
    variant_files+=("$result_dir/performance-${outputs}-variant-blur-disabled.json")
    write_variant_evidence blur-disabled "$baseline_snapshot_file" \
        "$result_dir/performance-${outputs}-variant-blur-disabled-snapshot.json" \
        "$post_soak_identity" "$current_identity" false "${variant_files[-1]}"
    sleep "$(jq -r '.baseline.settleSeconds' "$budgets")"
    run_sample blur-disabled "$sample_seconds" performance
    printf '%s\n' "$current_snapshot" >"$result_dir/performance-${outputs}-snapshot.json"

    build_summary "$result_dir/performance-${outputs}-summary.json" "$observed_renderer" \
        "$fingerprint_file" "$soak_file" \
        "$result_dir/performance-${outputs}-blur-enabled.json" \
        "$result_dir/performance-${outputs}-blur-disabled.json" "${variant_files[@]}"

    "$python_bin" -B "$privacy_sweep" \
        --root "$XDG_CONFIG_HOME" \
        --root "$XDG_STATE_HOME" \
        --root "$XDG_CACHE_HOME" \
        --root "$XDG_DATA_HOME" \
        --root "$HOME" \
        --root "$session_log" \
        --root "$result_dir/performance-${outputs}-snapshot.json"
    if [[ "$(jq -r '.numericStatus' "$result_dir/performance-${outputs}-summary.json")" == skipped ]]; then
        printf 'stability-performance: outputs=%s structural gates passed; numeric ceilings skipped: fingerprint mismatch\n' "$outputs"
    else
        printf 'stability-performance: outputs=%s numeric and structural gates passed\n' "$outputs"
    fi
}

build_cross_output_summary() {
    local output=$1
    shift
    "$python_bin" -B - "$budgets" "$output" "$@" <<'PY'
import json
import pathlib
import sys

budget = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
output = pathlib.Path(sys.argv[2])
rows = [json.loads(pathlib.Path(path).read_text(encoding="utf-8")) for path in sys.argv[3:]]
rows.sort(key=lambda row: row["displayCount"])
checks = {}
checks["displaySetExact"] = [row["displayCount"] for row in rows] == [1, 2, 3]
checks["childStructuralGatesPassed"] = all(row["structuralStatus"] == "passed" for row in rows)
helper_counts = [row["helperCount"] for row in rows]
helper_names = [row["helperNames"] for row in rows]
expected_delta = budget["isolated"]["displayCountAddsHelpers"]
checks["displayHelperDeltaExact"] = max(helper_counts) - min(helper_counts) == expected_delta
checks["helperExecutableSetExact"] = all(names == helper_names[0] for names in helper_names)
numeric_statuses = [row["numericStatus"] for row in rows]
checks["numericStatusConsistent"] = len(set(numeric_statuses)) == 1
checks["presentationSurfaceCountExact"] = all(
    row["resourceCounts"]["islandSurfaces"] == row["displayCount"] for row in rows
)
checks["wallpaperScreenStateCountExact"] = all(
    row["resourceCounts"]["wallpaperScreens"] == row["displayCount"] for row in rows
)
process_wide = []
for row in rows:
    counts = dict(row["resourceCounts"])
    counts.pop("islandSurfaces")
    counts.pop("wallpaperScreens")
    process_wide.append(counts)
checks["displayAddsBoundedPerDisplayStateOnly"] = all(
    value == process_wide[0] for value in process_wide
)
fingerprint_match = all(row["fingerprintMatch"] for row in rows)
numeric_status = numeric_statuses[0] if checks["numericStatusConsistent"] else "mixed"
checks["observedRendererExact"] = all(
    row["observedRenderer"] == budget["baseline"]["fingerprint"]["isolatedRenderer"] for row in rows
)
failures = [name for name, passed in checks.items() if not passed]
result = {
    "schemaVersion": 1,
    "displayCounts": [row["displayCount"] for row in rows],
    "checks": checks,
    "fingerprintMatch": fingerprint_match,
    "numericStatus": numeric_status,
    "structuralStatus": "failed" if failures else "passed",
    "failures": failures,
}
output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
if failures:
    raise SystemExit("; ".join(failures))
PY
}

outputs_arg=all
if (($# > 0)); then
    [[ "$1" == --outputs && $# == 2 ]] || {
        usage >&2
        exit 64
    }
    outputs_arg=$2
fi
[[ "$outputs_arg" == all || "$outputs_arg" =~ ^[123]$ ]] || {
    usage >&2
    exit 64
}
require_tools

if [[ "${NAGI_STABILITY_INNER:-0}" == 1 ]]; then
    [[ "$outputs_arg" =~ ^[123]$ ]] || fail "inner probe requires one output count"
    run_inner "$outputs_arg"
    exit 0
fi

rm -rf -- "$result_dir"
mkdir -p "$result_dir"
if [[ "$outputs_arg" == all ]]; then
    output_counts=(1 2 3)
else
    output_counts=("$outputs_arg")
fi
for output_count in "${output_counts[@]}"; do
    env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe LP_NUM_THREADS=0 \
        MESA_SHADER_CACHE_DISABLE=true mesa_glthread=false GALLIUM_THREAD=0 \
        QSG_RHI_BACKEND=opengl QSG_RENDER_LOOP=basic \
        "$root/tests/run-kwin-virtual.sh" --outputs "$output_count" --scale 1 -- \
        env NAGI_STABILITY_INNER=1 \
        NAGI_ENFORCE_PERFORMANCE="${NAGI_ENFORCE_PERFORMANCE:-0}" \
        NAGI_STABILITY_EXTENDED="${NAGI_STABILITY_EXTENDED:-0}" \
        PYTHONDONTWRITEBYTECODE=1 \
        "$root/tests/stability/run-performance.sh" --outputs "$output_count"
done
if [[ "$outputs_arg" == all ]]; then
    build_cross_output_summary "$result_dir/performance-all-summary.json" \
        "$result_dir/performance-1-summary.json" \
        "$result_dir/performance-2-summary.json" \
        "$result_dir/performance-3-summary.json"
    if [[ "$(jq -r '.numericStatus' "$result_dir/performance-all-summary.json")" == skipped ]]; then
        printf 'stability-performance: all structural gates passed; numeric ceilings skipped: fingerprint mismatch\n'
    else
        printf 'stability-performance: all numeric and structural gates passed\n'
    fi
fi
