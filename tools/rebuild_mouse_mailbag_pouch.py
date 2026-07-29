"""Rebuild the Blender mailbag pouch as a compact game-ready asset."""

import bpy
from mathutils import Vector


PREFIXES = ("Bag_", "Buckle_", "LeatherCorner_", "Postal_", "Urgent_")


def material(name: str, color: tuple[float, float, float, float], metallic=0.0, roughness=0.8):
    result = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    result.diffuse_color = color
    result.use_nodes = True
    principled = result.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = color
    principled.inputs["Metallic"].default_value = metallic
    principled.inputs["Roughness"].default_value = roughness
    return result


def bevel_box(name, location, dimensions, mat, bevel=0.002, segments=1):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        modifier = obj.modifiers.new("EdgeSoftening", "BEVEL")
        modifier.width = bevel
        modifier.segments = segments
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.data.materials.append(mat)
    return obj


def curved_flap(canvas):
    xs = (-0.039, 0.039)
    ys = (-0.043, -0.018, 0.008, 0.030, 0.044)
    zs = (0.034, 0.038, 0.037, 0.032, 0.023)
    vertices = [(x, y, z) for y, z in zip(ys, zs) for x in xs]
    faces = []
    for row in range(len(ys) - 1):
        a = row * 2
        faces.append((a, a + 2, a + 3, a + 1))
    mesh = bpy.data.meshes.new("Bag_RainFlap_GameMesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(canvas)
    obj = bpy.data.objects.new("Bag_RainFlap_QuadGrid", mesh)
    bpy.context.collection.objects.link(obj)
    solidify = obj.modifiers.new("CanvasThickness", "SOLIDIFY")
    solidify.thickness = 0.0025
    solidify.offset = 0
    bevel = obj.modifiers.new("SoftFlapEdges", "BEVEL")
    bevel.width = 0.0012
    bevel.segments = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=solidify.name)
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def insignia(red):
    vertices = [(-0.012, -0.012, 0.0405), (0.012, -0.012, 0.0405), (0, 0.010, 0.0405)]
    mesh = bpy.data.meshes.new("Postal_Insignia_GameMesh")
    mesh.from_pydata(vertices, [], [(0, 1, 2)])
    mesh.materials.append(red)
    obj = bpy.data.objects.new("Postal_Insignia", mesh)
    bpy.context.collection.objects.link(obj)
    solidify = obj.modifiers.new("InsigniaThickness", "SOLIDIFY")
    solidify.thickness = 0.001
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=solidify.name)


def main():
    for obj in list(bpy.data.objects):
        if obj.name.startswith(PREFIXES):
            bpy.data.objects.remove(obj, do_unlink=True)

    canvas = material("MAT_OchreCanvas", (0.48, 0.27, 0.09, 1), roughness=0.92)
    canvas_dark = material("MAT_OchreCanvasDark", (0.30, 0.15, 0.055, 1), roughness=0.94)
    leather = material("MAT_DarkLeather", (0.16, 0.065, 0.025, 1), roughness=0.72)
    brass = material("MAT_AgedBrass", (0.48, 0.29, 0.08, 1), metallic=0.55, roughness=0.48)
    paper = material("MAT_AgedPaper", (0.76, 0.67, 0.48, 1), roughness=0.95)
    red = material("MAT_MutedPostalRed", (0.42, 0.07, 0.045, 1), roughness=0.88)

    # One closed, rounded volume carries the silhouette. Two bevel segments are
    # enough to read as loaded canvas without spending geometry below gameplay
    # pixel size.
    bevel_box(
        "Bag_CanvasBody_QuadStrip",
        (0, 0, 0.016),
        (0.072, 0.084, 0.030),
        canvas,
        bevel=0.008,
        segments=2,
    )
    curved_flap(canvas)

    # End gussets are attached shallow caps, not detached planes.
    bevel_box("Bag_FrontGusset", (0, 0.0425, 0.016), (0.058, 0.0035, 0.024), canvas_dark, 0.002, 1)
    bevel_box("Bag_RearGusset", (0, -0.0425, 0.016), (0.058, 0.0035, 0.024), canvas_dark, 0.002, 1)

    # One readable urgent pocket and envelope on the near side.
    bevel_box("Bag_UrgentPocket_QuadGrid", (-0.037, 0.008, 0.017), (0.003, 0.042, 0.014), leather, 0.0015, 1)
    bevel_box("Urgent_Envelope", (-0.039, 0.008, 0.018), (0.0012, 0.032, 0.010), paper, 0.0006, 1)

    # Four compact reinforced corners establish construction without thin,
    # floating decorative sheets.
    corner_data = (
        ("LeatherCorner_FrontLeft", -0.0345, 0.039),
        ("LeatherCorner_FrontRight", 0.0345, 0.039),
        ("LeatherCorner_RearLeft", -0.0345, -0.039),
        ("LeatherCorner_RearRight", 0.0345, -0.039),
    )
    for name, x, y in corner_data:
        bevel_box(name, (x, y, 0.014), (0.008, 0.010, 0.020), leather, 0.0015, 1)

    # Mouse-scale keepers mark attachment points. The dynamic harness supplies
    # the long straps, so these remain deliberately simple.
    bevel_box("Buckle_LeftShoulder", (-0.039, 0.030, 0.016), (0.003, 0.011, 0.010), brass, 0.001, 1)
    bevel_box("Buckle_RightShoulder", (0.039, 0.030, 0.016), (0.003, 0.011, 0.010), brass, 0.001, 1)
    bevel_box("Buckle_RearStabilizer", (0, -0.0435, 0.016), (0.013, 0.003, 0.009), brass, 0.001, 1)
    insignia(red)

    for obj in bpy.context.scene.objects:
        if obj.type == "MESH" and obj.name.startswith(PREFIXES):
            for polygon in obj.data.polygons:
                polygon.use_smooth = False

    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    print("rebuilt game-ready mouse mailbag pouch")


if __name__ == "__main__":
    main()
