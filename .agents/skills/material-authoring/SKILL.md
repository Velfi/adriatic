---
name: material-authoring
description: Create and refine texture-backed BRDF materials in Adriatic by coordinating the in-game Material Lab, agent-owned image generation or editing, reference textures, and the Adriatic MCP material tools. Use when a user asks to make, texture, edit, inspect, save, or manage an Adriatic material; generate or derive albedo, specular, roughness, or normal maps; transform an input texture into material maps; or attach agent-produced PNG maps to a Material Lab material.
---

# Material Authoring

Use the user's image-generation-capable agent to create or transform texture maps, then use Adriatic MCP only to import and attach finished PNGs. Never synthesize texture pixels inside Adriatic or its MCP server.

## Workflow

1. Ensure Adriatic is running with the Material Lab open:

   ```text
   build/dev/adriatic --lab material
   ```

2. Call `material_list` through the Adriatic MCP to resolve the exact target material. Do not guess names. If it does not exist, call `material_create` with its name, base color, metallic value, and roughness before generating maps.

3. Determine the requested map kinds:

   - `albedo`: color only; avoid baked lighting, highlights, shadows, and ambient occlusion.
   - `specular`: grayscale reflectance; lighter means stronger reflection.
   - `roughness`: grayscale microsurface variation; white is rough, black is smooth.
   - `normal`: tangent-space RGB normal map; use +Y/OpenGL orientation unless the user requests otherwise.

4. Generate or edit the map with the agent's available image-generation skill/tool.

   - For a new texture, ask for a square, seamless, tileable, orthographic surface with no perspective or directional lighting.
   - For an input/reference texture, include the source image and preserve its material identity and feature placement unless the user asks for reinterpretation.
   - When deriving multiple maps from one input, keep every map registered to the same crop, scale, rotation, and dimensions.
   - Generate only requested maps. Do not invent a complete set unless useful and authorized.
   - Prefer power-of-two dimensions. Default to 1024×1024 for authored production maps and 512×512 for quick iteration.

5. Save the agent-produced PNG to a temporary or working path. Do not manually place it in the final material directory.

6. Call Adriatic MCP `material_attach_map` with:

   ```json
   {
     "material": "Exact Material Name",
     "kind": "normal",
     "path": "/absolute/path/to/agent-output.png",
     "save": true
   }
   ```

   The tool imports it atomically to:

   ```text
   assets/materials/<material-slug>/<kind>.png
   ```

   It then attaches the imported asset, refreshes the live preview, and saves the material library.

7. Verify the MCP result reports `ok: true`, `saved: true`, and the expected `asset_path`. Inspect the running preview. Iterate through the image tool and reattach if seams, scale, polarity, or response are wrong.

## Reference-texture requests

When the user says “based on this texture,” “derive a normal map,” or similar:

1. Inspect the supplied image before editing.
2. Use it as an image-generation/editing reference, not merely as a text description.
3. Preserve its UV registration and aspect ratio.
4. Remove lighting information appropriate to the target map.
5. Attach the resulting PNG with `material_attach_map`.

If the source image is missing or inaccessible, ask the user to attach it again. Never silently replace a reference-based request with unrelated procedural generation.

## Safety and ownership

- Treat image generation as the user's agent responsibility.
- Treat Adriatic MCP as an import, attachment, persistence, and live-preview boundary.
- Keep all committed material maps under `assets/materials/`.
- Do not overwrite a different material's directory or attach a map to an approximate name.
- Preserve source files outside `assets/materials/`; MCP copies the finished result into the project.
