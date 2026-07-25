# Adriatic contributor notes

- `zelda-engine` is a sibling dependency and must remain product-neutral.
- Keep product rules, assets, and presentation policy in this repository.
- Use the `zelda_engine` Odin collection instead of relative imports into the engine.
- When modifying Vulkan code, name every created or acquired Vulkan object immediately
  with `vk.SetDebugUtilsObjectNameEXT` (through the shared helper when available); for
  objects created before device-level function loading, name them at the first possible point.

## Screenshot capture

- Build the app, then use its capture CLI:
  `build/dev/adriatic capture <mode> /absolute/path/to/screenshot.png [target]`.
- Use `capture building` for a clean, eye-level architectural capture. It
  automatically selects and frames a façade; pass a zero-based architecture
  ordinal as the optional target, or use `cypress` for a close streetscape.
- Use `capture bougainvillea /absolute/output/directory [seed ...]` for the
  deterministic multi-seed bougainvillea matrix.
- Capture launches the macOS app briefly. In a sandboxed agent environment,
  allow GUI execution and sibling `../zelda-engine` build writes when prompted.
