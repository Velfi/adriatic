#!/usr/bin/env python3
"""MCP control server for a running Adriatic game."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
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


def selector_arguments(arguments: dict[str, object]) -> tuple[object, ...]:
    selector = arguments.get("selector")
    if not isinstance(selector, str) or not selector.strip():
        raise ValueError("selector must be a non-empty string")
    presentation = arguments.get("presentation", "fit")
    if presentation not in {"fit", "portrait", "profile", "overhead", "authored"}:
        raise ValueError("unknown selector presentation")
    pick = arguments.get("pick", "-")
    if pick != "-" and pick != "first" and (not isinstance(pick, int) or isinstance(pick, bool) or pick < 1):
        raise ValueError("pick must be first or a one-based positive integer")
    where = arguments.get("where", {})
    if not isinstance(where, dict) or len(where) > 8:
        raise ValueError("where must be an object with at most eight filters")
    filters: list[str] = []
    for key, value in where.items():
        if not isinstance(key, str) or not key or any(character in key for character in "=\t\n"):
            raise ValueError("filter keys must be non-empty single-line names")
        if isinstance(value, bool):
            encoded = "true" if value else "false"
        elif isinstance(value, (str, int, float)) and not isinstance(value, bool):
            encoded = str(value)
        else:
            raise ValueError(f"filter {key} must be a string, number, or boolean")
        if not encoded or any(character in encoded for character in "=\t\n"):
            raise ValueError(f"filter {key} has an invalid value")
        filters.append(f"{key}={encoded}")
    return selector.strip(), presentation, pick, *filters


TOOLS = [
    {
        "name": "mouse_emote_start",
        "title": "Start Mouse Emote",
        "description": "Start or replace a deterministic mouse emote in the running game.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "action": {"type": "string", "enum": [
                    "wave", "cheer", "bow", "point", "shrug", "sniff", "curious-head-tilt",
                    "surprised-recoil", "sit", "groom", "pick-up-hold", "sleep", "synthetic-test",
                ]},
                "handedness": {"type": "string", "enum": ["left", "right"], "default": "right"},
                "seed": {"type": "integer", "minimum": 0, "maximum": 4294967295, "default": 0},
                "loops": {"type": "integer", "minimum": 0, "maximum": 1000, "default": 0},
                "target": {
                    "type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3,
                    "description": "Optional world-space x, y, z attention target.",
                },
            },
            "required": ["action"],
            "additionalProperties": False,
        },
    },
    {
        "name": "mouse_emote_control",
        "title": "Control Mouse Emote",
        "description": "Freeze playback or scrub the active mouse emote to a normalized time.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "frozen": {"type": "boolean", "default": False},
                "scrub": {"type": ["number", "null"], "minimum": 0, "maximum": 1},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "mouse_emote_cancel",
        "title": "Cancel Mouse Emote",
        "description": "Blend the active mouse emote back to the procedural gameplay pose.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "regenerate_islands",
        "title": "Regenerate Both Default Islands",
        "description": "Replace the running authored world with freshly generated west and east default islands, towns, roads, and marinas.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "material_list",
        "title": "List BRDF Materials",
        "description": "List materials in the running Material Lab and report the active material.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "material_attach_map",
        "title": "Import and Attach Material Map",
        "description": "Import an agent-produced PNG into assets/materials/<material>/ and attach it as an albedo, specular, roughness, or normal map.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "material": {"type": "string"},
                "kind": {"type": "string", "enum": ["albedo", "specular", "roughness", "normal"]},
                "path": {
                    "type": "string",
                    "description": "PNG produced by the user's agent, including one derived from an input/reference texture.",
                },
                "save": {"type": "boolean", "default": True},
            },
            "required": ["material", "kind", "path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "material_create",
        "title": "Create BRDF Material",
        "description": "Create and select a named material in the running Adriatic Material Lab.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "base_color": {"type": "string", "pattern": "^#[0-9A-Fa-f]{6}$"},
                "metallic": {"type": "number", "minimum": 0, "maximum": 1},
                "roughness": {"type": "number", "minimum": 0.04, "maximum": 1},
            },
            "required": ["name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "audio_status",
        "title": "Get Audio Status",
        "description": "Read engine-audio stream, queue, gain, and global mute state from the running game.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "selector_query",
        "title": "Query Runtime Subjects",
        "description": "Dynamically query targetable subjects instantiated in the running game.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "selector": {"type": "string", "description": "Typed selector such as character:zora, vehicle, structure:42, or selection."},
                "where": {"type": "object", "description": "Optional equality filters such as name, type, resident, archetype, id, or available."},
            },
            "required": ["selector"],
            "additionalProperties": False,
        },
    },
    {
        "name": "selector_focus",
        "title": "Focus Runtime Subject",
        "description": "Resolve a typed selector and focus the running game's inspection camera on the matching subject.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "selector": {"type": "string", "description": "Typed selector such as character:zora, vehicle:postale, structure:42, or selection."},
                "where": {"type": "object", "description": "Optional equality filters."},
                "pick": {"oneOf": [{"type": "string", "const": "first"}, {"type": "integer", "minimum": 1}]},
                "presentation": {"type": "string", "enum": ["fit", "portrait", "profile", "overhead", "authored"], "default": "fit"},
            },
            "required": ["selector"],
            "additionalProperties": False,
        },
    },
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
                        "building", "marina", "farm", "wreck", "climbing_leaves", "roads", "ruins",
                    ],
                },
                "radius": {"type": "number", "description": "Brush radius in metres."},
                "strength": {"type": "number", "description": "Brush strength, density, flow, or spread from 0 to 1."},
                "hardness": {"type": "number", "description": "Brush edge hardness from 0 to 1."},
                "width": {"type": "number", "description": "Ridge, cliff, or road width in metres."},
                "height": {"type": "number", "description": "Ridge or cliff height in metres."},
                "size": {"type": "number", "description": "Farm or wreck footprint size in metres."},
                "mode": {"type": "string", "enum": ["mass", "hedge"], "description": "Foliage brush mode."},
            },
            "minProperties": 1,
            "additionalProperties": False,
        },
    },
]


def material_slug(name: str) -> str:
    slug = "".join(character.lower() if character.isalnum() else "-" for character in name)
    return "-".join(part for part in slug.split("-") if part) or "material"


def import_material_map(material: str, kind: str, source: Path) -> Path:
    destination = (ROOT / "assets" / "materials" / material_slug(material) / f"{kind}.png").resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.resolve() == destination:
        return destination
    temporary = destination.with_suffix(".png.tmp")
    try:
        shutil.copy2(source, temporary)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)
    return destination


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
        if tool_name not in {
            "audio_status", "npc_focus", "business_focus", "terrain_brush_get", "terrain_brush_set",
            "material_list", "material_create", "material_attach_map", "regenerate_islands",
            "selector_query", "selector_focus",
            "mouse_emote_start", "mouse_emote_control", "mouse_emote_cancel",
        }:
            reply(request_id, error={"code": -32602, "message": "unknown tool"})
            return
        arguments = params.get("arguments") or {}
        if not isinstance(arguments, dict):
            reply(request_id, error={"code": -32602, "message": "tool arguments must be an object"})
            return
        try:
            if tool_name == "regenerate_islands":
                if arguments:
                    raise ValueError("regenerate_islands takes no arguments")
                result = live_control("regenerate_islands", timeout=120)
            elif tool_name == "mouse_emote_start":
                allowed = {"action", "handedness", "seed", "loops", "target"}
                action = arguments.get("action")
                if set(arguments) - allowed or not isinstance(action, str):
                    raise ValueError("mouse_emote_start requires an action and known optional settings")
                handedness = arguments.get("handedness", "right")
                seed = arguments.get("seed", 0)
                loops = arguments.get("loops", 0)
                target = arguments.get("target")
                if handedness not in {"left", "right"}:
                    raise ValueError("handedness must be left or right")
                if isinstance(seed, bool) or not isinstance(seed, int) or not 0 <= seed <= 0xFFFFFFFF:
                    raise ValueError("seed must be an unsigned 32-bit integer")
                if isinstance(loops, bool) or not isinstance(loops, int) or not 0 <= loops <= 1000:
                    raise ValueError("loops must be between 0 and 1000")
                target_fields: tuple[object, object, object] = ("-", "-", "-")
                if target is not None:
                    if not isinstance(target, list) or len(target) != 3 or any(
                        isinstance(value, bool) or not isinstance(value, (int, float)) for value in target
                    ):
                        raise ValueError("target must contain three numbers")
                    target_fields = tuple(target)
                result = live_control("emote_start", action, handedness, seed, loops, *target_fields)
            elif tool_name == "mouse_emote_control":
                if set(arguments) - {"frozen", "scrub"}:
                    raise ValueError("mouse_emote_control received unknown settings")
                frozen = arguments.get("frozen", False)
                scrub = arguments.get("scrub")
                if not isinstance(frozen, bool):
                    raise ValueError("frozen must be a boolean")
                if scrub is not None and (isinstance(scrub, bool) or not isinstance(scrub, (int, float)) or not 0 <= scrub <= 1):
                    raise ValueError("scrub must be null or between 0 and 1")
                result = live_control("emote_control", str(frozen).lower(), "-" if scrub is None else scrub)
            elif tool_name == "mouse_emote_cancel":
                if arguments:
                    raise ValueError("mouse_emote_cancel takes no arguments")
                result = live_control("emote_cancel")
            elif tool_name == "audio_status":
                if arguments:
                    raise ValueError("audio_status takes no arguments")
                result = live_control("audio_status")
            elif tool_name == "material_list":
                if arguments:
                    raise ValueError("material_list takes no arguments")
                result = live_control("material_list")
            elif tool_name == "material_attach_map":
                allowed = {"material", "kind", "path", "save"}
                if not {"material", "kind", "path"} <= set(arguments) or not set(arguments) <= allowed:
                    raise ValueError("material_attach_map requires material, kind, and path")
                material, kind = arguments["material"], arguments["kind"]
                path = Path(str(arguments["path"])).expanduser().resolve()
                if not isinstance(material, str) or kind not in {"albedo", "specular", "roughness", "normal"}:
                    raise ValueError("invalid material or map kind")
                if not path.is_file() or path.suffix.lower() != ".png":
                    raise ValueError("path must identify an existing PNG")
                asset_path = import_material_map(material, kind, path)
                result = live_control("material_attach_map", material, kind, asset_path)
                result["source_path"] = str(path)
                result["asset_path"] = str(asset_path)
                if result.get("ok") and arguments.get("save", True):
                    result["saved"] = bool(live_control("material_save").get("ok"))
            elif tool_name == "material_create":
                allowed = {"name", "base_color", "metallic", "roughness"}
                if set(arguments) - allowed or not isinstance(arguments.get("name"), str):
                    raise ValueError("material_create requires a string name and optional BRDF settings")
                color = str(arguments.get("base_color", "#5F7F3A"))
                if len(color) != 7 or color[0] != "#":
                    raise ValueError("base_color must use #RRGGBB")
                channels = [int(color[index:index + 2], 16) for index in (1, 3, 5)]
                metallic = float(arguments.get("metallic", 0))
                roughness = float(arguments.get("roughness", 0.88))
                if not 0 <= metallic <= 1 or not 0.04 <= roughness <= 1:
                    raise ValueError("metallic or roughness is out of range")
                result = live_control("material_create", arguments["name"].strip(), *channels, metallic, roughness)
                if result.get("ok"):
                    result["saved"] = bool(live_control("material_save").get("ok"))
            elif tool_name in {"npc_focus", "business_focus"}:
                if set(arguments) != {"name"} or not isinstance(arguments["name"], str):
                    raise ValueError(f"{tool_name} requires only a string name")
                focus_tool = focus_npc if tool_name == "npc_focus" else focus_business
                result = focus_tool(arguments["name"])
            elif tool_name in {"selector_query", "selector_focus"}:
                allowed = {"selector", "where", "pick", "presentation"}
                if set(arguments) - allowed:
                    raise ValueError(f"{tool_name} received unknown arguments")
                fields = selector_arguments(arguments)
                result = live_control(tool_name, *fields)
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
                    "building", "marina", "farm", "wreck", "climbing_leaves", "roads", "ruins",
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
