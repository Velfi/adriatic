# Material Lab maps

Material Lab texture sets live in one slugged directory per material:

```text
assets/materials/<material-name>/
  albedo.png
  specular.png
  roughness.png
  normal.png
```

Texture generation belongs to the user's agent and its image tools, not to
Adriatic. The agent may generate a map from a prompt or derive it from an input
texture, then call the Adriatic MCP `material_attach_map` tool with the finished
PNG. The tool imports it to this directory, attaches it to the open Material Lab
material, refreshes the preview, and saves the material library.
