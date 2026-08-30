#!/usr/bin/env python3
"""Bounded /proc sampler and frozen-budget validator for the stability gate."""

from __future__ import annotations

import argparse
import json
import math
import os
import statistics
import sys
import time
from pathlib import Path
from typing import Any

EXPECTED_ISOLATED_HELPERS = frozenset(
    {
        "nagi-applications",
        "nagi-brightness",
        "nagi-connectivity",
        "nagi-gaming-performance",
        "nagi-global-shortcut",
        "nagi-kwin-virtual-desktops",
        "nagi-session",
        "nagi-wallpaper",
    }
)
EXPECTED_LIVE_HELPERS = EXPECTED_ISOLATED_HELPERS | frozenset({"nagi-audio"})
TOP_LEVEL_BUDGET_KEYS = frozenset(
    {
        "schemaVersion",
        "baseline",
        "live",
        "isolated",
        "closedControlCenter",
        "idle",
        "soak",
        "framePacing",
        "gpuStructural",
        "enforcement",
        "knownExternalGaps",
    }
)
MAX_JSON_BYTES = 256 * 1024
CLOCK_TICKS = os.sysconf("SC_CLK_TCK")


class ProbeFailure(RuntimeError):
    pass


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return parsed


def positive_float(value: str) -> float:
    parsed = float(value)
    if not 0 < parsed <= 60:
        raise argparse.ArgumentTypeError("must be in (0, 60]")
    return parsed


def read_text(path: Path, maximum: int = 1024 * 1024) -> str:
    try:
        data = path.read_bytes()
    except OSError as error:
        raise ProbeFailure(f"required field unavailable: {path.name}") from error
    if len(data) > maximum:
        raise ProbeFailure(f"required field exceeds bound: {path.name}")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ProbeFailure(f"required field is not UTF-8: {path.name}") from error


def exact_object(value: Any, keys: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ProbeFailure(f"{label} fields are unknown or missing")
    return value


def finite_number(value: Any, label: str, *, minimum: float = 0) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ProbeFailure(f"{label} must be numeric")
    parsed = float(value)
    if not math.isfinite(parsed) or parsed < minimum:
        raise ProbeFailure(f"{label} is outside its valid range")
    return parsed


def integer(value: Any, label: str, *, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise ProbeFailure(f"{label} must be an integer >= {minimum}")
    return value


def boolean(value: Any, label: str) -> bool:
    if not isinstance(value, bool):
        raise ProbeFailure(f"{label} must be boolean")
    return value


def bounded_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value or len(value.encode("utf-8")) > 4096:
        raise ProbeFailure(f"{label} must be a bounded non-empty string")
    return value


def string_list(value: Any, label: str) -> list[str]:
    if not isinstance(value, list) or not value:
        raise ProbeFailure(f"{label} must be a non-empty list")
    result: list[str] = []
    for index, entry in enumerate(value):
        result.append(bounded_string(entry, f"{label}[{index}]"))
    if len(result) != len(set(result)):
        raise ProbeFailure(f"{label} contains duplicates")
    return result


def load_budgets(path: Path) -> dict[str, Any]:
    raw = read_text(path)
    if len(raw.encode("utf-8")) > MAX_JSON_BYTES:
        raise ProbeFailure("budget file exceeds bound")
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ProbeFailure("budget file is invalid JSON") from error
    exact_object(value, set(TOP_LEVEL_BUDGET_KEYS), "budget")
    if value["schemaVersion"] != 1:
        raise ProbeFailure("unsupported budget schema")

    baseline = exact_object(
        value["baseline"],
        {"sources", "fingerprint", "settleSeconds", "sampleSeconds"},
        "baseline budget",
    )
    sources = exact_object(
        baseline["sources"],
        {"issue70", "issue63Helpers", "issue71Displays"},
        "baseline source",
    )
    for key, source in sources.items():
        bounded_string(source, f"baseline source {key}")
    fingerprint = exact_object(
        baseline["fingerprint"],
        {
            "architecture",
            "cpu",
            "distribution",
            "plasma",
            "kwin",
            "quickshell",
            "isolatedRenderer",
        },
        "baseline fingerprint",
    )
    for key, entry in fingerprint.items():
        bounded_string(entry, f"baseline fingerprint {key}")
    if fingerprint["isolatedRenderer"] != "llvmpipe":
        raise ProbeFailure("the frozen isolated renderer must be llvmpipe")
    finite_number(baseline["settleSeconds"], "baseline settle seconds", minimum=0.001)
    sample_seconds = exact_object(
        baseline["sampleSeconds"],
        {"live", "isolated", "isolatedExtended"},
        "baseline sample window",
    )
    for key, entry in sample_seconds.items():
        finite_number(entry, f"baseline {key} sample seconds", minimum=0.001)
    if sample_seconds["isolatedExtended"] <= sample_seconds["isolated"]:
        raise ProbeFailure("extended isolated sample must exceed the standard sample")

    live = exact_object(
        value["live"],
        {
            "oneIsland",
            "persistentHelperCount",
            "inProcessNotificationPluginCount",
            "aggregateHelperRssKiBMax",
            "helpers",
        },
        "live budget",
    )
    live_one = exact_object(
        live["oneIsland"],
        {
            "quickshellCpuPercentOneCoreMax",
            "quickshellRssKiBMax",
            "warmStartupSecondsMax",
        },
        "live one-island budget",
    )
    for key, entry in live_one.items():
        finite_number(entry, f"live one-island {key}")
    if integer(live["persistentHelperCount"], "live helper count") != len(
        EXPECTED_LIVE_HELPERS
    ):
        raise ProbeFailure("live helper budget disagrees with the fixed helper allowlist")
    if integer(live["inProcessNotificationPluginCount"], "notification plugin count") != 1:
        raise ProbeFailure("the in-process notification plugin count must remain one")
    finite_number(live["aggregateHelperRssKiBMax"], "aggregate live helper RSS")
    helpers = exact_object(live["helpers"], set(EXPECTED_LIVE_HELPERS), "live helper budget")
    for name, entry in helpers.items():
        helper = exact_object(entry, {"rssKiBMax"}, f"live helper {name}")
        finite_number(helper["rssKiBMax"], f"live helper {name} RSS")

    isolated = exact_object(
        value["isolated"],
        {"persistentHelperCountWithoutPipeWire", "displayCountAddsHelpers", "displays"},
        "isolated budget",
    )
    if integer(
        isolated["persistentHelperCountWithoutPipeWire"], "isolated helper count"
    ) != len(EXPECTED_ISOLATED_HELPERS):
        raise ProbeFailure("isolated helper budget disagrees with the fixed helper allowlist")
    integer(isolated["displayCountAddsHelpers"], "display helper delta")
    displays = exact_object(isolated["displays"], {"1", "2", "3"}, "display budget")
    expected_metric_keys = {
        "quickshellCpuPercentOneCoreMax",
        "schedulingSlicesPerSecondMax",
        "quickshellRssKiBMax",
        "threadsMax",
    }
    for display_count, entry in displays.items():
        metrics = exact_object(entry, expected_metric_keys, f"display {display_count} budget")
        for key, number in metrics.items():
            finite_number(number, f"display {display_count} {key}")

    closed = exact_object(
        value["closedControlCenter"],
        {
            "loadedPages",
            "pageInterestWork",
            "pageOwnedActiveTimers",
            "pageAnimations",
            "hiddenFocusLoops",
            "easyEffectsInterest",
        },
        "closed Control Center budget",
    )
    for key, entry in closed.items():
        integer(entry, f"closed Control Center {key}")

    idle = exact_object(
        value["idle"],
        {
            "defaultHelperActivity",
            "eventDrivenHelperActivity",
            "allowedRecurringWork",
            "displayCountAddsBoundedPerDisplayStateOnly",
        },
        "idle budget",
    )
    default_helper_activity = exact_object(
        idle["defaultHelperActivity"],
        {"cpuTicksDeltaMax", "schedulingSlicesDeltaMax"},
        "default helper activity budget",
    )
    for key, entry in default_helper_activity.items():
        integer(entry, f"default helper activity {key}")
    event_driven_helper_activity = idle["eventDrivenHelperActivity"]
    if not isinstance(event_driven_helper_activity, dict):
        raise ProbeFailure("event-driven helper activity budgets must be an object")
    for helper_name, entry in event_driven_helper_activity.items():
        if not isinstance(helper_name, str) or not helper_name:
            raise ProbeFailure("event-driven helper activity name must be a non-empty string")
        helper_activity = exact_object(
            entry,
            {"cpuTicksDeltaMax", "schedulingSlicesDeltaMax"},
            f"{helper_name} activity budget",
        )
        for key, number in helper_activity.items():
            integer(number, f"{helper_name} activity {key}")
    if not boolean(
        idle["displayCountAddsBoundedPerDisplayStateOnly"],
        "bounded per-display state growth",
    ):
        raise ProbeFailure("display count must add bounded per-display state only")

    soak = exact_object(
        value["soak"],
        {
            "cycles",
            "extendedCycles",
            "countsReturnExactlyToPreCycle",
            "boundedCachesRemainWithinExistingLimits",
            "finalSettledRssGrowthPercentMax",
            "finalSettledRssGrowthKiBMax",
            "rssGrowthLimitUsesGreaterAllowance",
        },
        "soak budget",
    )
    integer(soak["cycles"], "soak cycles", minimum=1)
    integer(soak["extendedCycles"], "extended soak cycles", minimum=1)
    if soak["extendedCycles"] <= soak["cycles"]:
        raise ProbeFailure("extended soak cycles must exceed the standard soak")
    if not boolean(soak["countsReturnExactlyToPreCycle"], "exact soak count return"):
        raise ProbeFailure("soak counts must return exactly")
    if not boolean(soak["boundedCachesRemainWithinExistingLimits"], "bounded soak caches"):
        raise ProbeFailure("soak caches must retain their existing bounds")
    finite_number(soak["finalSettledRssGrowthPercentMax"], "soak RSS percent growth")
    finite_number(soak["finalSettledRssGrowthKiBMax"], "soak RSS KiB growth")
    if not boolean(soak["rssGrowthLimitUsesGreaterAllowance"], "soak RSS greater allowance"):
        raise ProbeFailure("soak RSS growth must use the greater frozen allowance")

    frame = exact_object(
        value["framePacing"],
        {
            "requiresHardwareCapableProbe",
            "intervalsWithinTwoRefreshPeriodsPercentMin",
            "intervalsAboveThreeRefreshPeriodsMax",
        },
        "frame-pacing budget",
    )
    if not boolean(frame["requiresHardwareCapableProbe"], "hardware frame-pacing requirement"):
        raise ProbeFailure("frame pacing must remain hardware-gated")
    finite_number(
        frame["intervalsWithinTwoRefreshPeriodsPercentMin"],
        "frame intervals within two periods",
    )
    integer(frame["intervalsAboveThreeRefreshPeriodsMax"], "frame intervals above three periods")

    gpu = exact_object(
        value["gpuStructural"],
        {
            "closedControlCenterPageOwnedWindowsOrEffects",
            "shadowLayersPerVisibleIslandMax",
            "requestedKwinBlurRegionsPerVisibleIslandMax",
            "extraGpuOrEffectObjectsPerProcessWideService",
        },
        "GPU structural budget",
    )
    for key, entry in gpu.items():
        integer(entry, f"GPU structural {key}")

    enforcement = exact_object(
        value["enforcement"],
        {
            "always",
            "exactFingerprint",
            "forceEnvironmentVariable",
            "forceEnvironmentValue",
            "liveProbePolicy",
        },
        "enforcement budget",
    )
    string_list(enforcement["always"], "always-enforced gates")
    string_list(enforcement["exactFingerprint"], "exact-fingerprint gates")
    bounded_string(enforcement["forceEnvironmentVariable"], "force environment variable")
    bounded_string(enforcement["forceEnvironmentValue"], "force environment value")
    bounded_string(enforcement["liveProbePolicy"], "live probe policy")
    string_list(value["knownExternalGaps"], "known external gaps")
    return value


def parse_stat(pid: int) -> tuple[int, int]:
    text = read_text(Path("/proc") / str(pid) / "stat", 65536).strip()
    close = text.rfind(")")
    if close < 0:
        raise ProbeFailure("malformed process stat")
    fields = text[close + 2 :].split()
    if len(fields) < 20:
        raise ProbeFailure("malformed process stat field count")
    try:
        return int(fields[11]) + int(fields[12]), int(fields[19])
    except ValueError as error:
        raise ProbeFailure("malformed process stat value") from error


def parse_status(pid: int) -> tuple[int, int]:
    values: dict[str, int] = {}
    for line in read_text(Path("/proc") / str(pid) / "status", 65536).splitlines():
        if line.startswith("VmRSS:") or line.startswith("Threads:"):
            parts = line.split()
            if len(parts) < 2:
                raise ProbeFailure("malformed process status value")
            try:
                values[parts[0].rstrip(":")] = int(parts[1])
            except ValueError as error:
                raise ProbeFailure("malformed process status value") from error
    if set(values) != {"VmRSS", "Threads"}:
        raise ProbeFailure("process RSS or thread count is missing")
    return values["VmRSS"], values["Threads"]


def parse_schedstat(pid: int) -> int:
    fields = read_text(Path("/proc") / str(pid) / "schedstat", 65536).split()
    if len(fields) < 3:
        raise ProbeFailure("malformed process schedstat")
    try:
        return int(fields[2])
    except ValueError as error:
        raise ProbeFailure("malformed process schedstat value") from error


def direct_children(pid: int) -> dict[str, int]:
    children_path = Path("/proc") / str(pid) / "task" / str(pid) / "children"
    tokens = read_text(children_path, 65536).split()
    result: dict[str, int] = {}
    for token in tokens:
        try:
            child_pid = int(token)
        except ValueError as error:
            raise ProbeFailure("malformed direct-child list") from error
        try:
            executable = os.path.basename(os.readlink(Path("/proc") / token / "exe"))
        except OSError as error:
            raise ProbeFailure("direct child exited during discovery") from error
        if executable in result:
            raise ProbeFailure(f"duplicate helper executable: {executable}")
        result[executable] = child_pid
    return result


def snapshot(pid: int, expected_children: dict[str, int] | None = None) -> dict[str, Any]:
    ticks, _ = parse_stat(pid)
    rss_kib, threads = parse_status(pid)
    slices = parse_schedstat(pid)
    children = direct_children(pid)
    if expected_children is not None and children != expected_children:
        raise ProbeFailure("direct helper identity changed during the sample")
    helper_metrics: dict[str, dict[str, int]] = {}
    for name, child_pid in children.items():
        child_ticks, _ = parse_stat(child_pid)
        child_rss, child_threads = parse_status(child_pid)
        child_slices = parse_schedstat(child_pid)
        helper_metrics[name] = {
            "cpuTicks": child_ticks,
            "rssKiB": child_rss,
            "threads": child_threads,
            "schedulingSlices": child_slices,
        }
    return {
        "cpuTicks": ticks,
        "rssKiB": rss_kib,
        "threads": threads,
        "schedulingSlices": slices,
        "helpers": helper_metrics,
    }


def thread_name_counts(pid: int) -> dict[str, int]:
    counts: dict[str, int] = {}
    task_root = Path("/proc") / str(pid) / "task"
    try:
        tasks = list(task_root.iterdir())
    except OSError as error:
        raise ProbeFailure("process thread census is unavailable") from error
    for task in tasks:
        name = read_text(task / "comm", 256).strip()
        counts[name] = counts.get(name, 0) + 1
    return dict(sorted(counts.items()))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", required=True, type=positive_int)
    parser.add_argument("--duration", required=True, type=positive_float)
    parser.add_argument("--display-count", required=True, type=int, choices=(1, 2, 3))
    parser.add_argument("--budgets", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--fingerprint-match", action="store_true")
    parser.add_argument("--structural-only", action="store_true")
    args = parser.parse_args()

    budgets = load_budgets(args.budgets)
    expected_count = budgets["isolated"]["persistentHelperCountWithoutPipeWire"]
    first_children = direct_children(args.pid)
    if set(first_children) != EXPECTED_ISOLATED_HELPERS or len(first_children) != expected_count:
        observed = ",".join(sorted(first_children))
        raise ProbeFailure(f"direct helper allowlist or count mismatch: {observed}")

    first = snapshot(args.pid, first_children)
    rss_samples: list[int] = [first["rssKiB"]]
    started = time.monotonic()
    deadline = started + args.duration
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        time.sleep(min(0.25, remaining))
        if not (Path("/proc") / str(args.pid)).exists():
            raise ProbeFailure("Quickshell exited during the sample")
        if direct_children(args.pid) != first_children:
            raise ProbeFailure("direct helper identity changed during the sample")
        rss_kib, _ = parse_status(args.pid)
        rss_samples.append(rss_kib)
    elapsed = time.monotonic() - started
    second = snapshot(args.pid, first_children)
    rss_samples.append(second["rssKiB"])

    cpu_ticks = second["cpuTicks"] - first["cpuTicks"]
    slices = second["schedulingSlices"] - first["schedulingSlices"]
    if cpu_ticks < 0 or slices < 0:
        raise ProbeFailure("monotonic process counter regressed")
    cpu_percent = cpu_ticks / CLOCK_TICKS / elapsed * 100.0
    slices_per_second = slices / elapsed
    thread_names = thread_name_counts(args.pid)
    if sum(thread_names.values()) != second["threads"]:
        raise ProbeFailure("thread set changed during census")
    metrics = {
        "durationSeconds": round(elapsed, 3),
        "quickshellCpuPercentOneCore": round(cpu_percent, 3),
        "schedulingSlicesPerSecond": round(slices_per_second, 3),
        "quickshellRssKiB": second["rssKiB"],
        "quickshellRssMedianKiB": statistics.median(rss_samples),
        "threads": second["threads"],
        "helperCount": len(first_children),
        "aggregateHelperRssKiB": sum(
            row["rssKiB"] for row in second["helpers"].values()
        ),
        "threadNameCounts": thread_names,
    }

    helper_rows = []
    structural_failures: list[str] = []
    default_helper_activity = budgets["idle"]["defaultHelperActivity"]
    event_driven_helper_activity = budgets["idle"]["eventDrivenHelperActivity"]
    for name in sorted(first_children):
        before = first["helpers"][name]
        after = second["helpers"][name]
        cpu_delta = after["cpuTicks"] - before["cpuTicks"]
        slice_delta = after["schedulingSlices"] - before["schedulingSlices"]
        activity_budget = event_driven_helper_activity.get(
            name, default_helper_activity
        )
        if cpu_delta < 0 or slice_delta < 0:
            structural_failures.append(f"{name} monotonic activity counter regressed")
        if cpu_delta > activity_budget["cpuTicksDeltaMax"]:
            structural_failures.append(f"{name} CPU activity exceeds its idle budget")
        if slice_delta > activity_budget["schedulingSlicesDeltaMax"]:
            structural_failures.append(
                f"{name} scheduling activity exceeds its idle budget"
            )
        helper_rows.append(
            {
                "name": name,
                "cpuTicksDelta": cpu_delta,
                "schedulingSlicesDelta": slice_delta,
                "rssKiB": after["rssKiB"],
                "threads": after["threads"],
            }
        )

    force_variable = budgets["enforcement"]["forceEnvironmentVariable"]
    force_value = budgets["enforcement"]["forceEnvironmentValue"]
    forced = os.environ.get(force_variable) == force_value
    if forced and not args.fingerprint_match:
        raise ProbeFailure("forced performance enforcement requires an exact fingerprint match")
    numeric_enforced = not args.structural_only and (args.fingerprint_match or forced)
    numeric_failures: list[str] = []
    if numeric_enforced:
        ceiling = budgets["isolated"]["displays"][str(args.display_count)]
        comparisons = (
            ("quickshellCpuPercentOneCore", "quickshellCpuPercentOneCoreMax"),
            ("schedulingSlicesPerSecond", "schedulingSlicesPerSecondMax"),
            ("quickshellRssKiB", "quickshellRssKiBMax"),
            ("threads", "threadsMax"),
        )
        for metric, maximum in comparisons:
            if metrics[metric] > ceiling[maximum]:
                numeric_failures.append(f"{metric} exceeds its frozen ceiling")

    failures = structural_failures + numeric_failures
    result = {
        "schemaVersion": 1,
        "displayCount": args.display_count,
        "fingerprintMatch": args.fingerprint_match,
        "numericEnforced": numeric_enforced,
        "numericStatus": (
            "failed"
            if numeric_failures
            else "passed"
            if numeric_enforced
            else "not-run"
            if args.structural_only
            else "skipped"
        ),
        "structuralStatus": "failed" if structural_failures else "passed",
        "metrics": metrics,
        "helpers": helper_rows,
        "failures": failures,
    }
    encoded = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if len(encoded.encode("utf-8")) > MAX_JSON_BYTES:
        raise ProbeFailure("result exceeds bound")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(encoded, encoding="utf-8")
    if failures:
        raise ProbeFailure("; ".join(failures))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProbeFailure as error:
        print(f"stability-sampler: {error}", file=sys.stderr)
        raise SystemExit(1)
