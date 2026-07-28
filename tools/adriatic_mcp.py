#!/usr/bin/env python3
"""MCP control server for a running Adriatic game."""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parents[1]
REQUEST = Path(os.environ.get("ADRIATIC_LIVE_CONTROL_REQUEST", ROOT / "build/live-control.request"))
RESPONSE = Path(os.environ.get("ADRIATIC_LIVE_CONTROL_RESPONSE", ROOT / "build/live-control.response"))


def reply(request_id: object, result: object = None, error: object = None) -> None:
    message = {"jsonrpc": "2.0", "id": request_id}
    message["error" if error is not None else "result"] = error if error is not None else result
    print(json.dumps(message, separators=(",", ":")), flush=True)


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False, encoding="utf-8") as output:
        temporary = Path(output.name)
        output.write(text)
        output.flush()
        os.fsync(output.fileno())
    os.replace(temporary, path)


def live_control(command: str, *arguments: object, timeout: float = 5.0) -> dict[str, object]:
    fields = [command, *(str(argument) for argument in arguments)]
    if any(not field or "\t" in field or "\n" in field for field in fields):
        raise ValueError("live-control fields must be non-empty single-line values")
    request_id = uuid.uuid4().hex
    RESPONSE.unlink(missing_ok=True)
    write_atomic(REQUEST, "\t".join((request_id, *fields)) + "\n")
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            result = json.loads(RESPONSE.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError):
            time.sleep(0.025)
            continue
        if result.get("id") == request_id:
            RESPONSE.unlink(missing_ok=True)
            return result
        time.sleep(0.025)
    raise TimeoutError("timed out waiting for a running Adriatic game")


def focus_npc(name: str, timeout: float = 5.0) -> dict[str, object]:
    return focus("npc", name, timeout)


def focus_business(name: str, timeout: float = 5.0) -> dict[str, object]:
    return focus("business", name, timeout)


def focus(subject: str, name: str, timeout: float = 5.0) -> dict[str, object]:
    if not name.strip() or not all(character.isalnum() or character in " .'-" for character in name):
        raise ValueError("name must contain only letters, numbers, spaces, periods, apostrophes, or hyphens")
    return live_control(subject, name.strip(), timeout=timeout)


TOOLS = [
    {
        "name": "npc_focus",
        "title": "Focus NPC",
        "description": "Focus the running game's inspection camera on an NPC by name (case-insensitive).",
        "inputSchema": {
            "type": "object",
            "properties": {"name": {"type": "string", "description": "NPC display name, for example Zora or Dr Vesna."}},
            "required": ["name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "business_focus",
        "title": "Focus Business",
        "description": "Focus the running game's inspection camera on a business by name (case-insensitive).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                    "description": (
                        "Pane, Fortuna, Clinica, Post, or Aerodromo; prefix East or West "
                        "when the business has multiple locations."
                    ),
                },
            },
            "required": ["name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "terrain_brush_get",
        "title": "Get Terrain Brush",
        "description": "Read the active authoring tool and its brush, stamp, curve, or placement settings from the running terrain editor.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "terrain_brush_set",
        "title": "Set Terrain Brush",
        "description": "Select and configure any tool in the running terrain editor. Omitted settings are unchanged.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "tool": {
                    "type": "string",
                    "enum": [
                        "sculpt", "smooth", "paint", "formations", "foliage", "ridge", "cliff",
                        "building", "marina", "farm", "wreck", "climbing_leaves", "roads", "greek_assets",
                    ],
                },
                "radius": {"type": "number", "description": "Brush radius in metres."},
                "strength": {"type": "number", "description": "Brush strength, density, flow, or spread from 0 to 1."},
                "hardness": {"type": "number", "description": "Brush edge hardness from 0 to 1."},
                "width": {"type": "number", "description": "Ridge, cliff, or road width in metres."},
                "height": {"type": "number", "description": "Ridge or cliff height in metres."},
                "size": {"type": "number", "description": "Farm or wreck footprint size in metres, or Greek-asset scale."},
                "mode": {"type": "string", "enum": ["mass", "hedge"], "description": "Foliage brush mode."},
            },
            "minProperties": 1,
            "additionalProperties": False,
        },
    },
]


def handle(message: dict[str, object]) -> None:
    method = message.get("method")
    request_id = message.get("id")
    if method == "initialize":
        reply(request_id, {
            "protocolVersion": "2025-06-18",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "adriatic", "version": "1.0.0"},
        })
    elif method == "tools/list":
        reply(request_id, {"tools": TOOLS})
    elif method == "tools/call":
        params = message.get("params") or {}
        tool_name = params.get("name") if isinstance(params, dict) else None
        if tool_name not in {"npc_focus", "business_focus", "terrain_brush_get", "terrain_brush_set"}:
            reply(request_id, error={"code": -32602, "message": "unknown tool"})
            return
        arguments = params.get("arguments") or {}
        if not isinstance(arguments, dict):
            reply(request_id, error={"code": -32602, "message": "tool arguments must be an object"})
            return
        try:
            if tool_name in {"npc_focus", "business_focus"}:
                if set(arguments) != {"name"} or not isinstance(arguments["name"], str):
                    raise ValueError(f"{tool_name} requires only a string name")
                focus_tool = focus_npc if tool_name == "npc_focus" else focus_business
                result = focus_tool(arguments["name"])
            elif tool_name == "terrain_brush_get":
                if arguments:
                    raise ValueError("terrain_brush_get takes no arguments")
                result = live_control("terrain_brush_get")
            else:
                allowed = {"tool", "radius", "strength", "hardness", "width", "height", "size", "mode"}
                if not arguments or not set(arguments) <= allowed:
                    raise ValueError("terrain_brush_set requires one or more brush settings")
                tool = arguments.get("tool", "-")
                tools = {
                    "sculpt", "smooth", "paint", "formations", "foliage", "ridge", "cliff",
                    "building", "marina", "farm", "wreck", "climbing_leaves", "roads", "greek_assets",
                }
                if tool != "-" and tool not in tools:
                    raise ValueError("unknown terrain editor tool")
                values: list[object] = []
                for key in ("radius", "strength", "hardness", "width", "height", "size"):
                    value = arguments.get(key, "-")
                    if value != "-" and (isinstance(value, bool) or not isinstance(value, (int, float))):
                        raise ValueError(f"{key} must be a number")
                    values.append(value)
                mode = arguments.get("mode", "-")
                if mode not in {"-", "mass", "hedge"}:
                    raise ValueError("mode must be mass or hedge")
                result = live_control("terrain_brush_set", tool, *values, mode)
            reply(request_id, {"content": [{"type": "text", "text": json.dumps(result)}], "isError": not result.get("ok", False)})
        except (ValueError, TimeoutError, OSError) as exc:
            reply(request_id, {"content": [{"type": "text", "text": str(exc)}], "isError": True})
    elif request_id is not None:
        reply(request_id, error={"code": -32601, "message": "method not found"})


def main() -> None:
    for line in sys.stdin:
        try:
            handle(json.loads(line))
        except (json.JSONDecodeError, TypeError) as exc:
            reply(None, error={"code": -32700, "message": str(exc)})


if __name__ == "__main__":
    main()
