#!/usr/bin/env python3
"""Convert a rigged GLB avatar (with shape keys) to USDZ for RealityKit.

Usage:
  blender --background --python tools/convert_avatar.py -- input.glb output.usdz

Exports armature (UsdSkel) + shape keys (USD BlendShapes) + materials.
"""
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from flatten_materials import flatten_all_materials  # noqa: E402


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    src, dst = argv[0], argv[1]

    # Wipe the default scene (cube, camera, light).
    bpy.ops.wm.read_factory_settings(use_empty=True)

    bpy.ops.import_scene.gltf(filepath=src)
    print(f"[convert] imported {src}")
    flatten_all_materials()

    # RealityKit merges all skinned meshes under one skeleton into a single
    # ModelEntity but keeps only ONE mesh's blend-shape bindings. Join every
    # morphed mesh (head/teeth/eyes) into one so that surviving weight set
    # drives the whole face. Blender's join merges shape keys by name.
    morphed = [o for o in bpy.data.objects
               if o.type == "MESH" and o.data.shape_keys
               and len(o.data.shape_keys.key_blocks) > 1]
    if len(morphed) > 1:
        bpy.ops.object.select_all(action="DESELECT")
        for o in morphed:
            o.select_set(True)
        # Prefer the biggest mesh (the head) as join target so its material
        # slots and armature modifier lead.
        active = max(morphed, key=lambda o: len(o.data.vertices))
        bpy.context.view_layer.objects.active = active
        bpy.ops.object.join()
        active.name = "Face_Merged"
        n_keys = len(active.data.shape_keys.key_blocks) - 1
        print(f"[convert] joined {len(morphed)} morphed meshes -> "
              f"{active.name} ({len(active.data.vertices)} verts, {n_keys} keys)")
    for obj in bpy.data.objects:
        shape_keys = getattr(obj.data, "shape_keys", None) if obj.type == "MESH" else None
        n_keys = len(shape_keys.key_blocks) - 1 if shape_keys else 0
        print(f"[convert]   {obj.type}: {obj.name} shapekeys={n_keys}")

    result = bpy.ops.wm.usd_export(
        filepath=dst,
        export_animation=False,
        export_hair=False,
        export_uvmaps=True,
        export_normals=True,
        export_materials=True,
        export_armatures=True,
        export_shapekeys=True,
        generate_preview_surface=True,
        export_textures_mode="NEW",
        overwrite_textures=True,
        convert_world_material=False,
        selected_objects_only=False,
        export_mesh_colors=False,
        convert_orientation=True,
        usdz_downscale_size="CUSTOM",
        usdz_downscale_custom_size=1024,
        export_global_up_selection="Y",
        export_global_forward_selection="NEGATIVE_Z",
    )
    print(f"[convert] export result: {result} -> {dst}")


if __name__ == "__main__":
    main()
