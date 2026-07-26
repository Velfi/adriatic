#!/usr/bin/env python3
"""Request a screenshot from an already-running Adriatic game."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import tempfile
import time


REQUEST_ENV = "ADRIATIC_LIVE_CAPTURE_REQUEST"
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REQUEST = ROOT / "build/live-capture.request"


def file_signature(path: Path) -> tuple[int, int] | None:
    try:
        stat = path.stat()
    except FileNotFoundError:
        return None
    return stat.st_mtime_ns, stat.st_size


def write_request(request: Path, target: Path) -> None:
    request.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            dir=request.parent,
            prefix=f".{request.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
            temporary.write(f"{target}\n")
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_path, request)
    except Exception:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
        raise


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", required=True, type=Path, help="PNG path to write")
    parser.add_argument(
        "--request",
        type=Path,
        default=Path(os.environ.get(REQUEST_ENV, DEFAULT_REQUEST)),
        help=f"request file (default: ${REQUEST_ENV} or {DEFAULT_REQUEST})",
    )
    parser.add_argument("--timeout", type=float, default=30.0, help="seconds to wait")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    target = args.path.expanduser().resolve()
    request = args.request.expanduser().resolve()
    before = file_signature(target)

    target.parent.mkdir(parents=True, exist_ok=True)
    write_request(request, target)

    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        after = file_signature(target)
        if after is not None and after[1] > 0 and after != before:
            print(f"Screenshot: {target}")
            return 0
        time.sleep(0.05)

    print(
        f"error: timed out waiting for running game to write {target}; "
        f"request remains at {request}",
        flush=True,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
