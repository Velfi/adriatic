"""Export the authored mailbag pouch and hardware for Adriatic.

Run with:
  Blender --background assets/concepts/mouse-mailbag-source.blend \
    --python tools/export_mouse_mailbag_glb.py -- \
    assets/models/mouse-mailbag-pouch.glb
"""

import pathlib
import sys

import bpy


EXPORT_PREFIXES = (
    "Bag_",
    "Buckle_",
    "LeatherCorner_",
    "Postal_",
    "Urgent_",
)


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(argv) != 1:
        raise SystemExit("expected one output .glb path after --")

    output = pathlib.Path(argv[0]).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.object.select_all(action="DESELECT")
    selected = []
    for obj in bpy.context.scene.objects:
        if obj.name.startswith(EXPORT_PREFIXES):
            obj.hide_set(False)
            obj.hide_render = False
            obj.select_set(True)
            selected.append(obj)

    if not selected:
        raise SystemExit("no mailbag pouch objects found")

    bpy.context.view_layer.objects.active = selected[0]
    # Curves carry the authored brass buckles and insignia. Convert them so the
    # runtime GLB loader receives one straightforward triangle mesh stream.
    for obj in list(selected):
        if obj.type == "CURVE":
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.convert(target="MESH")

    # Collapse the authored construction pieces into one runtime mesh. Material
    # slots remain distinct, so the GLB carries six draw ranges instead of one
    # node/primitive per tiny corner guard or buckle.
    bpy.ops.object.select_all(action="DESELECT")
    mesh_objects = [o for o in bpy.context.scene.objects if o.name.startswith(EXPORT_PREFIXES) and o.type == "MESH"]
    for obj in mesh_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objects[0]
    bpy.ops.object.join()
    bpy.context.object.name = "MouseMailbag_Pouch_GameReady"

    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
        export_texcoords=True,
        export_normals=True,
    )
    print(f"exported {len(selected)} mailbag objects to {output}")


if __name__ == "__main__":
    main()
