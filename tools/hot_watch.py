#!/usr/bin/env python3
"""Rebuild Adriatic hot targets while the hot host keeps the app alive."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys
import time


POLL_SECONDS = 0.25
SOURCE_SUFFIXES = {".c", ".h", ".odin", ".slang"}
WATCH_ROOTS = ("assets/shaders", "hot", "packages", "src")
WATCH_FILES = ("Makefile", "toolchain.mk")


def watched_files(root: Path, engine_root: Path) -> set[Path]:
    files = {root / path for path in WATCH_FILES}
    for relative_root in WATCH_ROOTS:
        directory = root / relative_root
        if not directory.is_dir():
            continue
        files.update(
            path
            for path in directory.rglob("*")
            if path.is_file() and path.suffix in SOURCE_SUFFIXES
        )

    engine_packages = (root / engine_root / "packages").resolve()
    if engine_packages.is_dir():
        files.update(
            path
            for path in engine_packages.rglob("*")
            if path.is_file() and path.suffix in SOURCE_SUFFIXES
        )
    return files


def snapshot(root: Path, engine_root: Path) -> dict[Path, tuple[int, int]]:
    result: dict[Path, tuple[int, int]] = {}
    for path in watched_files(root, engine_root):
        try:
            stat = path.stat()
        except FileNotFoundError:
            continue
        result[path] = (stat.st_mtime_ns, stat.st_size)
    return result


def changed_paths(
    before: dict[Path, tuple[int, int]], after: dict[Path, tuple[int, int]]
) -> set[Path]:
    paths = set(before) | set(after)
    return {path for path in paths if before.get(path) != after.get(path)}


def run_make(root: Path, make: str, targets: list[str]) -> bool:
    print(f"hot: rebuilding {' '.join(targets)}", flush=True)
    result = subprocess.run([make, "-C", str(root), *targets], check=False)
    if result.returncode != 0:
        print("hot: rebuild failed; running app stays alive", file=sys.stderr, flush=True)
        return False
    return True


def is_shader(path: Path, root: Path) -> bool:
    try:
        return path.is_relative_to(root / "assets" / "shaders")
    except AttributeError:
        return str(path).startswith(str(root / "assets" / "shaders"))


def is_host(path: Path, root: Path) -> bool:
    try:
        return path.is_relative_to(root / "hot")
    except AttributeError:
        return str(path).startswith(str(root / "hot"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--engine-root", type=Path, default=Path("../zelda-engine"))
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--make", default="make")
    args = parser.parse_args()

    root = args.root.resolve()
    engine_root = args.engine_root
    host = args.host.resolve()
    before = snapshot(root, engine_root)
    print("hot: watching Odin, engine, and shader sources; Ctrl-C stops", flush=True)
    process = subprocess.Popen([str(host)], cwd=host.parent)
    try:
        while True:
            if process.poll() is not None:
                return process.returncode

            time.sleep(POLL_SECONDS)
            after = snapshot(root, engine_root)
            changed = changed_paths(before, after)
            if not changed:
                continue

            shader_changed = any(is_shader(path, root) for path in changed)
            host_changed = any(is_host(path, root) for path in changed)
            app_changed = any(not is_shader(path, root) and not is_host(path, root) for path in changed)
            targets = []
            if app_changed:
                targets.append("hot-app")
            if shader_changed:
                targets.append("hot-shaders")
            if host_changed:
                targets.append("hot-host")
            run_make(root, args.make, targets)
            before = after
    except KeyboardInterrupt:
        print("", flush=True)
        return 130
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
