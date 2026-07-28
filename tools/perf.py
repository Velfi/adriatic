#!/usr/bin/env python3
"""Run configured Adriatic renderer benchmarks and enforce frame budgets."""

from __future__ import annotations

import argparse
import json
import platform
import statistics
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
RESULT_PREFIX = "BENCHMARK_RESULT "


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    result = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def git_state() -> dict[str, Any]:
    revision = subprocess.run(
        ["git", "rev-parse", "--short", "HEAD"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    dirty = subprocess.run(
        ["git", "status", "--short"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    return {"revision": revision, "dirty": dirty}


def run_once(executable: Path, name: str, scenario: dict[str, Any]) -> dict[str, Any]:
    window = scenario["window"]
    world = scenario["world"]
    command = [
        str(executable),
        "--benchmark",
        name,
        str(scenario["warmup_frames"]),
        str(scenario["sample_frames"]),
        str(window[0]),
        str(window[1]),
        str(world[0]),
        str(world[1]),
    ]
    completed = subprocess.run(
        command,
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    output = completed.stdout + "\n" + completed.stderr
    if completed.returncode != 0:
        raise RuntimeError(
            f"{name} exited with {completed.returncode}\n{output[-4000:]}"
        )
    for line in output.splitlines():
        if line.startswith(RESULT_PREFIX):
            result = json.loads(line[len(RESULT_PREFIX) :])
            result["command"] = command
            return result
    raise RuntimeError(f"{name} produced no benchmark result\n{output[-4000:]}")


def summarize(runs: list[dict[str, Any]], budgets: dict[str, float]) -> dict[str, Any]:
    summary = {
        "median_ms": statistics.median(run["median_ms"] for run in runs),
        "p95_ms": max(run["p95_ms"] for run in runs),
        "p99_ms": max(run["p99_ms"] for run in runs),
        "max_ms": max(run["max_ms"] for run in runs),
    }
    summary["median_fps"] = 1000.0 / max(summary["median_ms"], 0.000001)
    metric_keys = {
        "median": "median_ms",
        "p95": "p95_ms",
        "p99": "p99_ms",
        "max": "max_ms",
    }
    checks = {
        metric: {
            "value_ms": summary[key],
            "budget_ms": budgets[metric],
            "pass": summary[key] <= budgets[metric],
        }
        for metric, key in metric_keys.items()
    }
    summary["budget_checks"] = checks
    summary["pass"] = all(check["pass"] for check in checks.values())
    geometry_runs = [run["geometry"] for run in runs if "geometry" in run]
    if geometry_runs:
        summary["geometry"] = {
            "world_vertices_max": max(
                geometry["world_vertices"] for geometry in geometry_runs
            ),
            "world_unique_vertices_max": max(
                geometry.get("world_unique_vertices", geometry["world_vertices"])
                for geometry in geometry_runs
            ),
            "world_utilization_max": max(
                geometry["world_utilization"] for geometry in geometry_runs
            ),
            "road_vertices_max": max(
                geometry["road_vertices"] for geometry in geometry_runs
            ),
            "road_utilization_max": max(
                geometry["road_utilization"] for geometry in geometry_runs
            ),
            "foliage_vertices_max": max(
                geometry["foliage_vertices"] for geometry in geometry_runs
            ),
            "foliage_utilization_max": max(
                geometry["foliage_utilization"] for geometry in geometry_runs
            ),
        }
        summary["workload_present"] = any(
            summary["geometry"][metric] > 0
            for metric in (
                "world_vertices_max",
                "road_vertices_max",
                "foliage_vertices_max",
            )
        )
        # A renderer launch can succeed without acquiring a usable GPU in a
        # sandboxed macOS process. Reject that empty workload instead of
        # reporting implausibly tiny frame times as a passing benchmark.
        summary["pass"] &= summary["workload_present"]
        cache_runs = [
            geometry["caches"]
            for geometry in geometry_runs
            if isinstance(geometry.get("caches"), dict)
        ]
        if cache_runs:
            summary["caches"] = {
                key: max(int(cache.get(key, 0)) for cache in cache_runs)
                for key in cache_runs[0]
            }
    return summary


def command_run(args: argparse.Namespace) -> int:
    config_path = (ROOT / args.config).resolve()
    config = json.loads(config_path.read_text())
    if args.build:
        subprocess.run(["make", "release"], cwd=ROOT, check=True)
    executable = (ROOT / (args.executable or config["executable"])).resolve()
    if not executable.is_file():
        raise RuntimeError(f"benchmark executable not found: {executable}")

    configured = config["scenarios"]
    if args.scenario == "all":
        names = [name for name, value in configured.items() if value.get("enabled")]
    else:
        if args.scenario not in configured:
            raise RuntimeError(f"unknown scenario: {args.scenario}")
        names = [args.scenario]
    repetitions = args.repeat or config["repetitions"]
    results: dict[str, Any] = {
        "profile": config["profile"],
        "host": {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
        },
        "tree": git_state(),
        "repetitions": repetitions,
        "scenarios": {},
    }
    failed = False
    for name in names:
        scenario = deep_merge(config["defaults"], configured[name])
        runs = [run_once(executable, name, scenario) for _ in range(repetitions)]
        summary = summarize(runs, scenario["budgets_ms"])
        failed |= not summary["pass"]
        results["scenarios"][name] = {
            "description": scenario.get("description", ""),
            "configuration": {
                "warmup_frames": scenario["warmup_frames"],
                "sample_frames": scenario["sample_frames"],
                "window": scenario["window"],
                "world": scenario["world"],
                "budgets_ms": scenario["budgets_ms"],
            },
            "runs": runs,
            "summary": summary,
        }
        status = "PASS" if summary["pass"] else "FAIL"
        print(
            f"{status} {name}: median {summary['median_ms']:.3f} ms "
            f"p95 {summary['p95_ms']:.3f} ms p99 {summary['p99_ms']:.3f} ms "
            f"max {summary['max_ms']:.3f} ms ({summary['median_fps']:.1f} FPS)"
        )
        if "geometry" in summary:
            geometry = summary["geometry"]
            print(
                f"  geometry: world {geometry['world_vertices_max']:,} "
                f"(unique {geometry['world_unique_vertices_max']:,}, "
                f"{geometry['world_utilization_max'] * 100:.1f}%), "
                f"cards {geometry['foliage_vertices_max']:,} "
                f"({geometry['foliage_utilization_max'] * 100:.1f}%), "
                f"roads {geometry['road_vertices_max']:,} "
                f"({geometry['road_utilization_max'] * 100:.1f}%)"
            )
        if "caches" in summary:
            cache = summary["caches"]
            print(
                f"  caches: clipmap {cache['clipmap_generated']} generated / "
                f"{cache['clipmap_copied']} copied, grass {cache['grass_hits']} hits / "
                f"{cache['grass_misses']} misses, climbing leaves "
                f"{cache['climbing_leaf_builds']} builds / {cache['climbing_leaf_reuses']} reuse, "
                f"town mice {cache['town_mouse_builds']} builds / {cache['town_mouse_reuses']} reuse"
            )

    output_path = Path(args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(results, indent=2) + "\n")
    print(f"Results: {output_path}")
    return 1 if failed else 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    subcommands = result.add_subparsers(dest="command", required=True)
    run = subcommands.add_parser("run")
    run.add_argument("--scenario", default="all")
    run.add_argument("--repeat", type=int)
    run.add_argument("--output", required=True)
    run.add_argument("--config", default="perf/scenarios.json")
    run.add_argument("--executable")
    run.add_argument("--build", action="store_true")
    run.set_defaults(function=command_run)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        return args.function(args)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
