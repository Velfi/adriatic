"""Render neutral audit views of the authored mouse mailbag."""

import pathlib
import sys

import bpy
from mathutils import Vector


PREFIXES = ("Bag_", "Buckle_", "LeatherCorner_", "Postal_", "Urgent_")


def point_camera(camera: bpy.types.Object, target: Vector) -> None:
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    output = pathlib.Path(argv[0] if argv else "build/captures").resolve()
    output.mkdir(parents=True, exist_ok=True)

    keep = [o for o in bpy.context.scene.objects if o.name.startswith(PREFIXES)]
    for obj in bpy.context.scene.objects:
        obj.hide_render = obj not in keep

    corners = []
    for obj in keep:
        corners.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    minimum = Vector(tuple(min(p[i] for p in corners) for i in range(3)))
    maximum = Vector(tuple(max(p[i] for p in corners) for i in range(3)))
    center = (minimum + maximum) * 0.5
    extent = max(maximum - minimum)

    bpy.ops.object.light_add(type="AREA", location=(-extent * 2, -extent * 2, extent * 3))
    key = bpy.context.object
    key.data.energy = 450
    key.data.shape = "DISK"
    key.data.size = extent * 3
    point_camera(key, center)

    camera_data = bpy.data.cameras.new("AuditCamera")
    camera = bpy.data.objects.new("AuditCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    bpy.context.scene.camera = camera
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = extent * 1.35

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shading.cavity_type = "BOTH"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False

    views = {
        "side": Vector((-extent * 3, center.y, center.z + extent * 0.15)),
        "top": Vector((center.x, center.y, center.z + extent * 4)),
        "three-quarter": center + Vector((-extent * 2.5, -extent * 2.5, extent * 1.8)),
    }
    for name, position in views.items():
        camera.location = position
        point_camera(camera, center)
        scene.render.filepath = str(output / f"mouse-mailbag-audit-{name}.png")
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
