#!/usr/bin/env python3
"""Convert a static glTF/GLB prop to USDZ for RealityKit.

Usage:
  blender --background --python tools/convert_prop.py -- input.(gltf|glb) output.usdz
"""
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from flatten_materials import flatten_all_materials  # noqa: E402


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    src, dst = argv[0], argv[1]

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    flatten_all_materials()

    result = bpy.ops.wm.usd_export(
        filepath=dst,
        export_animation=False,
        export_materials=True,
        export_shapekeys=False,
        export_armatures=False,
        generate_preview_surface=True,
        export_textures_mode="NEW",
        overwrite_textures=True,
        convert_world_material=False,
        export_mesh_colors=False,
        convert_orientation=True,
        export_global_up_selection="Y",
        export_global_forward_selection="NEGATIVE_Z",
        usdz_downscale_size="CUSTOM",
        usdz_downscale_custom_size=1024,
    )
    print(f"[prop] {result} -> {dst}")


if __name__ == "__main__":
    main()
