"""Generate Adriatic's stylized modular cliff-rock kit and review render.

Run with:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/generate_cliff_rock_kit.py
"""

from __future__ import annotations

import math
import os
import random

import bpy
from mathutils import Vector


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_DIR = os.path.join(ROOT, "assets", "models", "cliff-rocks")
CONCEPT_DIR = os.path.join(ROOT, "assets", "concepts")
MATERIAL_DIR = os.path.join(ROOT, "assets", "materials", "weathered-adriatic-cliff-limestone")
BLEND_PATH = os.path.join(CONCEPT_DIR, "cliff-rock-kit-source.blend")
RENDER_PATH = os.path.join(CONCEPT_DIR, "cliff-rock-kit-review.png")


# Dimensions are metres. Each silhouette fills a practical level-design role.
ROCKS = (
    ("cliff-rock-01-buttress", (7.4, 4.8, 8.6), 11, 0.16, 0.08, 0.10),
    ("cliff-rock-02-wide-shelf", (11.0, 5.2, 4.8), 23, -0.08, 0.34, 0.18),
    ("cliff-rock-03-tall-pillar", (4.8, 4.2, 11.5), 37, 0.24, 0.12, 0.06),
    ("cliff-rock-04-leaning-slab", (5.0, 3.4, 9.2), 41, -0.30, 0.22, 0.12),
    ("cliff-rock-05-corner-wedge", (8.6, 7.1, 6.7), 53, 0.12, 0.16, 0.28),
    ("cliff-rock-06-low-boulder", (8.2, 6.8, 4.2), 67, -0.06, 0.28, 0.04),
    ("cliff-rock-07-overhang", (9.0, 4.4, 7.8), 79, 0.32, 0.24, 0.16),
    ("cliff-rock-08-narrow-fin", (4.1, 2.8, 9.7), 83, -0.22, 0.10, 0.30),
    ("cliff-rock-09-terrace", (10.4, 7.4, 5.5), 97, 0.08, 0.38, 0.22),
    ("cliff-rock-10-hero-stack", (7.2, 5.7, 10.2), 109, -0.18, 0.18, 0.26),
)


def rock_material():
    material = bpy.data.materials.new("Weathered Adriatic Cliff Limestone")
    material.diffuse_color = (0.62, 0.58, 0.46, 1.0)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.62, 0.58, 0.46, 1.0)
    shader.inputs["Roughness"].default_value = 0.88
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    albedo = nodes.new("ShaderNodeTexImage")
    albedo.name = "Cliff_Limestone_Albedo"
    albedo.image = bpy.data.images.load(os.path.join(MATERIAL_DIR, "albedo.png"), check_existing=True)
    albedo.image.colorspace_settings.name = "sRGB"
    links.new(albedo.outputs["Color"], shader.inputs["Base Color"])
    roughness = nodes.new("ShaderNodeTexImage")
    roughness.name = "Cliff_Limestone_Roughness"
    roughness.image = bpy.data.images.load(os.path.join(MATERIAL_DIR, "roughness.png"), check_existing=True)
    roughness.image.colorspace_settings.name = "Non-Color"
    links.new(roughness.outputs["Color"], shader.inputs["Roughness"])
    specular = nodes.new("ShaderNodeTexImage")
    specular.name = "Cliff_Limestone_Specular"
    specular.image = bpy.data.images.load(os.path.join(MATERIAL_DIR, "specular.png"), check_existing=True)
    specular.image.colorspace_settings.name = "Non-Color"
    specular_input = shader.inputs.get("Specular IOR Level") or shader.inputs.get("Specular")
    if specular_input is not None:
        links.new(specular.outputs["Color"], specular_input)
    normal_texture = nodes.new("ShaderNodeTexImage")
    normal_texture.name = "Cliff_Limestone_Normal"
    normal_texture.image = bpy.data.images.load(os.path.join(MATERIAL_DIR, "normal.png"), check_existing=True)
    normal_texture.image.colorspace_settings.name = "Non-Color"
    normal = nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = 0.58
    links.new(normal_texture.outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], shader.inputs["Normal"])
    return material


def box_project_uv(obj, metres_per_tile=2.8):
    uv_layer = obj.data.uv_layers.get("Cliff_Box_UV") or obj.data.uv_layers.new(name="Cliff_Box_UV")
    for polygon in obj.data.polygons:
        normal = polygon.normal
        axis = max(range(3), key=lambda index: abs(normal[index]))
        for loop_index in polygon.loop_indices:
            point = obj.data.vertices[obj.data.loops[loop_index].vertex_index].co / metres_per_tile
            if axis == 2:
                uv = (point.x, point.y)
            elif axis == 0:
                uv = (point.y, point.z)
            else:
                uv = (point.x, point.z)
            uv_layer.data[loop_index].uv = uv


def make_rock(name, dimensions, seed, lean, crown, asymmetry, material):
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = f"{name}-mesh"

    # Low-frequency harmonics give each rock a designed, readable silhouette.
    phases = [rng.uniform(-math.pi, math.pi) for _ in range(7)]
    for vertex in obj.data.vertices:
        p = vertex.co.normalized()
        azimuth = math.atan2(p.y, p.x)
        elevation = math.asin(max(-1.0, min(1.0, p.z)))
        strata = math.sin(elevation * 7.0 + phases[0]) * 0.055
        large_planes = (
            math.sin(azimuth * 3.0 + phases[1]) * 0.10
            + math.sin(azimuth * 5.0 + elevation * 2.0 + phases[2]) * 0.045
            + math.cos(elevation * 4.0 + phases[3]) * 0.055
        )
        directional = asymmetry * (0.55 * p.x - 0.35 * p.y) * (0.45 + 0.55 * (p.z + 1.0) * 0.5)
        radius = 1.0 + strata + large_planes + directional

        x = p.x * radius * dimensions[0] * 0.5
        y = p.y * radius * dimensions[1] * 0.5
        z_norm = p.z
        # A compressed crown makes placeable ledges and strong top planes.
        if z_norm > 0.34:
            z_norm = 0.34 + (z_norm - 0.34) * (1.0 - crown * 0.78)
        z = z_norm * radius * dimensions[2] * 0.5
        x += lean * (z / dimensions[2]) * dimensions[0]
        # Slight vertical stepping evokes weathered Adriatic limestone strata.
        z += math.sin((z / dimensions[2] + 0.5) * math.pi * 6.0 + phases[4]) * dimensions[2] * 0.012
        vertex.co = (x, y, z)

    # Ground every piece at Z=0 and keep its origin useful for placement.
    minimum_z = min(v.co.z for v in obj.data.vertices)
    for vertex in obj.data.vertices:
        vertex.co.z -= minimum_z

    obj.data.materials.append(material)

    # Collapse nearly coplanar facets into broad planes, then softly catch edges.
    decimate = obj.modifiers.new("Broad_Planes", "DECIMATE")
    decimate.decimate_type = "DISSOLVE"
    decimate.angle_limit = math.radians(7.5)
    decimate.use_dissolve_boundaries = False
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=decimate.name)

    bevel = obj.modifiers.new("Weathered_Edges", "BEVEL")
    bevel.width = min(dimensions) * 0.018
    bevel.segments = 1
    bevel.affect = "EDGES"
    bpy.ops.object.modifier_apply(modifier=bevel.name)

    # Preserve the designed low-poly silhouette while interpolating normals
    # continuously across its broad planes and weathered bevels.
    for polygon in obj.data.polygons:
        polygon.use_smooth = True

    # Metre-scaled box UVs keep strata horizontal and texel density consistent.
    box_project_uv(obj)
    obj.select_set(False)
    return obj


def export_one(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(MODEL_DIR, f"{obj.name}.glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
        export_normals=True,
        export_texcoords=True,
    )
    obj.select_set(False)


def build_review_scene(objects):
    for index, obj in enumerate(objects):
        column = index % 5
        row = index // 5
        obj.location.x = (column - 2) * 13.0
        obj.location.y = 0.0
        obj.location.z = (1 - row) * 14.0

    bpy.ops.mesh.primitive_plane_add(size=90, location=(0, 0, -0.04))
    ground = bpy.context.object
    ground.name = "Review_Ground"
    mat = bpy.data.materials.new("MAT_Review_Ground")
    mat.diffuse_color = (0.12, 0.15, 0.14, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.12, 0.15, 0.14, 1)
    shader.inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(mat)

    world = bpy.context.scene.world or bpy.data.worlds.new("Review_World")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.07, 0.10, 0.12, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.32

    bpy.ops.object.light_add(type="AREA", location=(-22, -20, 30))
    bpy.context.object.data.energy = 5200
    bpy.context.object.data.shape = "DISK"
    bpy.context.object.data.size = 18
    bpy.ops.object.light_add(type="AREA", location=(25, 8, 18))
    bpy.context.object.data.energy = 2800
    bpy.context.object.data.color = (0.48, 0.64, 1.0)
    bpy.context.object.data.size = 14

    bpy.ops.object.camera_add(location=(0, -72, 12))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 70
    direction = Vector((0, 0, 12)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = RENDER_PATH
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    bpy.ops.render.render(write_still=True)


def main():
    os.makedirs(MODEL_DIR, exist_ok=True)
    os.makedirs(CONCEPT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    material = rock_material()
    objects = [make_rock(name, dims, seed, lean, crown, asymmetry, material) for name, dims, seed, lean, crown, asymmetry in ROCKS]
    for obj in objects:
        export_one(obj)
    build_review_scene(objects)
    for obj in objects:
        print(f"{obj.name}: {len(obj.data.vertices)} vertices, {len(obj.data.polygons)} faces")
    print(f"wrote {len(objects)} cliff rocks to {MODEL_DIR}")


if __name__ == "__main__":
    main()
