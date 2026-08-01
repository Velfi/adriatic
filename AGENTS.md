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

## Player-facing UI copy

- Treat every visible string as product copy. Keep it terse, literal, and
  action-oriented.
- Every string must help the player act, identify something, or understand the
  current state. If a new string is not necessary, do not add one.
- Do not add ornamental subtitles, taglines, marketing-style feature callouts,
  or implementation terminology. Avoid generated-sounding summaries such as
  `A • B • C` unless the items are actual selectable values or useful state.
- Use concrete nouns and direct verbs. Buttons name the resulting action;
  prompts use `[input] to [action]`; status messages state what happened or
  what the player must do next.
- Preserve established game terms. Prefer deleting nonessential copy, and ask
  for review when a new player-facing concept needs a name.
