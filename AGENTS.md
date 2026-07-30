# Adriatic contributor notes

- `zelda-engine` is a sibling dependency and must remain product-neutral.
- Keep product rules, assets, and presentation policy in this repository.
- Use the `zelda_engine` Odin collection instead of relative imports into the engine.
- When modifying Vulkan code, name every created or acquired Vulkan object immediately
  with `vk.SetDebugUtilsObjectNameEXT` (through the shared helper when available); for
  objects created before device-level function loading, name them at the first possible point.

## Validation profile

- When the user reports memory or rendering problems, reproduce with `make validation`
  before diagnosing or changing code. This profile enables Vulkan validation layers and
  ASAN.

## Compiler bugs

- If the compiler crashes, hangs, miscompiles, or produces clearly incorrect diagnostics,
  stop immediately and report the compiler version, command, evidence, and smallest
  reproducer. Do not work around the compiler bug or continue until given direction.

## Screenshot capture

- Build the app, then use its capture tool at `build/dev/adriatic capture`.
- Capture launches the macOS app briefly. In a sandboxed agent environment,
  allow GUI execution and sibling `../zelda-engine` build writes when prompted.

## Live editor control

- Use the project MCP server at
  `/Users/zelda/Documents/adriatic/tools/adriatic_mcp.py` to control a running
  Adriatic editor. It is a stdio MCP server and can also be launched with
  `make mcp`.
- The MCP communicates with the already-running game; do not restart the game
  to use it.
